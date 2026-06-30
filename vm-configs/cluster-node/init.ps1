#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)][string]$DomainName,
    [Parameter(Mandatory)][string]$AdminUsername,
    [Parameter(Mandatory)][string]$AdminPassword,
    [Parameter(Mandatory)][string]$DcIpAddress,
    [Parameter(Mandatory)][string]$DscPullServerIp,
    [Parameter(Mandatory)][string]$ClusterNodeConfigId
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$logFile = 'C:\init.log'
function Write-Log { param($msg) "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Tee-Object -FilePath $logFile -Append }

Write-Log 'Cluster node init.ps1 starting.'

Write-Log 'Installing RSAT-AD-Tools.'
Install-WindowsFeature -Name RSAT-AD-Tools -IncludeManagementTools | Out-Null

Write-Log "Setting DNS to $DcIpAddress on management NIC (10.50.1.x)."
$mgmtAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
    $ip = Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ip -and $ip.IPAddress -like '10.50.1.*') { $_ }
} | Select-Object -First 1

if ($mgmtAdapter) {
    Set-DnsClientServerAddress -InterfaceIndex $mgmtAdapter.InterfaceIndex -ServerAddresses $DcIpAddress
    Write-Log "DNS set on adapter: $($mgmtAdapter.Name) ($($mgmtAdapter.InterfaceIndex))"
} else {
    Write-Log 'WARNING: Could not identify management NIC by 10.50.1.x address. Setting DNS on first Up adapter.'
    $firstAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    Set-DnsClientServerAddress -InterfaceIndex $firstAdapter.InterfaceIndex -ServerAddresses $DcIpAddress
}

$secPass = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$cred    = New-Object PSCredential ("$DomainName\$AdminUsername", $secPass)

Write-Log "Polling for domain $DomainName every 60s until available."
while ($true) {
    try {
        Get-ADDomain -Server $DomainName -Credential $cred -ErrorAction Stop | Out-Null
        Get-ADForest  -Server $DomainName -Credential $cred -ErrorAction Stop | Out-Null
        Write-Log "Domain $DomainName is reachable."
        break
    } catch {
        Write-Log "Domain not yet available: $_"
        Write-Log 'Waiting 60s before retry.'
        Start-Sleep -Seconds 60
    }
}

Write-Log "Joining domain $DomainName."
Add-Computer -DomainName $DomainName -Credential $cred -Force
Write-Log 'Domain join complete.'

# Phase 1 variables are injected as literal strings into configure-node.ps1 via here-string interpolation.
# Phase 2 variables (computed at startup time) are backtick-escaped so they evaluate in the child context.
Write-Log 'Writing C:\configure-node.ps1.'
$configureScript = @"
`$ErrorActionPreference = 'Stop'
`$logFile = 'C:\configure-node.log'
function Write-Log { param(`$msg) "`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') `$msg" | Tee-Object -FilePath `$logFile -Append }

Write-Log 'configure-node.ps1 starting.'

`$hvInstalled = (Get-WindowsFeature Hyper-V).Installed
`$lcmPullMode = (Get-DscLocalConfigurationManager).RefreshMode -eq 'Pull'
if (`$hvInstalled -and `$lcmPullMode) {
    Write-Log 'Already configured (Hyper-V installed, LCM in Pull mode). Unregistering task and exiting.'
    Unregister-ScheduledTask -TaskName 'ConfigureClusterNode' -Confirm:`$false -ErrorAction SilentlyContinue
    exit 0
}

Write-Log 'Installing Hyper-V and Failover Clustering features.'
Install-WindowsFeature -Name Hyper-V                    -IncludeManagementTools | Out-Null
Install-WindowsFeature -Name Failover-Clustering         -IncludeManagementTools | Out-Null
Install-WindowsFeature -Name RSAT-Clustering-Mgmt                               | Out-Null
Install-WindowsFeature -Name RSAT-Clustering-PowerShell                         | Out-Null
Install-WindowsFeature -Name RSAT-Hyper-V-Tools                                 | Out-Null
Write-Log 'Feature installation complete.'

Write-Log 'Retrieving DSC pull server certificate thumbprint.'
`$thumbprint = `$null
try {
    Add-Type -TypeDefinition @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCerts : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int certProblem) {
        return true;
    }
}
'@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCerts
    `$webReq = [System.Net.WebRequest]::Create('https://${DscPullServerIp}:8080/PSDSCPullServer.svc')
    `$webReq.Timeout = 30000
    try { `$webReq.GetResponse().Close() } catch {}
    `$rawCert = `$webReq.ServicePoint.Certificate
    if (`$rawCert) {
        `$thumbprint = ([System.Security.Cryptography.X509Certificates.X509Certificate2]`$rawCert).Thumbprint
        Write-Log "Pull server thumbprint: `$thumbprint"
    } else {
        Write-Log 'WARNING: Could not retrieve pull server certificate. LCM will allow unsecure connection.'
    }
} catch {
    Write-Log "WARNING: Exception retrieving pull server cert: `$_"
}

Write-Log 'Configuring DSC LCM in Pull mode.'
`$dscServerUrl  = 'https://${DscPullServerIp}:8080/PSDSCPullServer.svc'
`$nodeConfigId  = '${ClusterNodeConfigId}'
`$allowUnsecure = (`$thumbprint -eq `$null)

[DSCLocalConfigurationManager()]
Configuration LcmPullConfig {
    Node 'localhost' {
        Settings {
            RefreshMode          = 'Pull'
            ConfigurationMode    = 'ApplyAndAutoCorrect'
            RefreshFrequencyMins = 30
            RebootNodeIfNeeded   = `$true
            ConfigurationID      = `$nodeConfigId
        }
        ConfigurationRepositoryWeb DSCPullServer {
            ServerURL               = `$dscServerUrl
            CertificateID           = `$thumbprint
            AllowUnsecureConnection = `$allowUnsecure
        }
    }
}
New-Item -Path 'C:\LcmConfig' -ItemType Directory -Force | Out-Null
LcmPullConfig -OutputPath 'C:\LcmConfig'
Set-DscLocalConfigurationManager -Path 'C:\LcmConfig' -Verbose
Write-Log 'LCM configured.'

Write-Log 'Writing validation log.'
`$valLog = 'C:\configure-node-validation.log'
function Write-Check {
    param([string]`$Label, [bool]`$Result, [string]`$Detail = '')
    `$status = if (`$Result) { '[PASS]' } else { '[FAIL]' }
    `$line   = if (`$Detail) { "`$status `$Label -- `$Detail" } else { "`$status `$Label" }
    `$line | Tee-Object -FilePath `$valLog -Append
}

"Validation run: `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File `$valLog -Encoding UTF8 -Force

`$features = @('Hyper-V','Failover-Clustering','RSAT-Clustering-Mgmt','RSAT-Clustering-PowerShell','RSAT-Hyper-V-Tools')
foreach (`$f in `$features) {
    `$state = (Get-WindowsFeature `$f).InstallState
    Write-Check "Feature: `$f" (`$state -eq 'Installed') `$state
}

`$lcm = Get-DscLocalConfigurationManager
Write-Check 'LCM RefreshMode' (`$lcm.RefreshMode -eq 'Pull') `$lcm.RefreshMode
Write-Check 'LCM ConfigurationID' (`$lcm.ConfigurationID -eq '${ClusterNodeConfigId}') "`$(`$lcm.ConfigurationID)"

`$domainMember = (Get-WmiObject Win32_ComputerSystem).PartOfDomain
Write-Check 'Domain membership' `$domainMember (if (`$domainMember) { 'True' } else { 'False' })

`$rawDiskCount = (Get-Disk | Where-Object { `$_.PartitionStyle -eq 'RAW' }).Count
Write-Check 'Shared disk count (RAW) >= 3' (`$rawDiskCount -ge 3) "`$rawDiskCount RAW disks found"

try {
    `$pullResp = Invoke-WebRequest -Uri 'https://${DscPullServerIp}:8080/PSDSCPullServer.svc' ``
        -UseBasicParsing -SkipCertificateCheck -TimeoutSec 10 -ErrorAction Stop
    Write-Check 'Pull server reachable' (`$pullResp.StatusCode -lt 400) "HTTP `$(`$pullResp.StatusCode)"
} catch {
    Write-Check 'Pull server reachable' `$false `$_.Exception.Message
}

`$anyFail = (Get-Content `$valLog | Where-Object { `$_ -like '*[FAIL]*' }).Count -gt 0
if (-not `$anyFail) {
    'Validation complete. All checks passed.' | Tee-Object -FilePath `$valLog -Append
} else {
    'Validation complete. One or more checks FAILED -- review entries above.' | Tee-Object -FilePath `$valLog -Append
}

Write-Log 'Unregistering ConfigureClusterNode scheduled task.'
Unregister-ScheduledTask -TaskName 'ConfigureClusterNode' -Confirm:`$false -ErrorAction SilentlyContinue

Write-Log 'configure-node.ps1 complete. LCM RebootNodeIfNeeded will trigger reboot if features require it.'
"@

$configureScript | Out-File -FilePath 'C:\configure-node.ps1' -Encoding UTF8 -Force

Write-Log 'Registering ConfigureClusterNode scheduled task.'
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
                -Argument '-NonInteractive -ExecutionPolicy Bypass -File C:\configure-node.ps1' `
                -WorkingDirectory 'C:\'
$trigger   = New-ScheduledTaskTrigger -AtStartup
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName 'ConfigureClusterNode' `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Log 'Scheduling reboot in 30s. init.ps1 complete.'
shutdown /r /t 30
