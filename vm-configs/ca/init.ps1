#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)][string]$DomainName,
    [Parameter(Mandatory)][string]$AdminUsername,
    [Parameter(Mandatory)][string]$AdminPassword,
    [Parameter(Mandatory)][string]$DcIpAddress,
    [string]$CaCommonName = 'Corp-Lab-Root-CA'
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$logFile = 'C:\init.log'
function Write-Log { param($msg) "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Tee-Object -FilePath $logFile -Append }

Write-Log 'CA init.ps1 starting.'

Write-Log 'Installing RSAT-AD-Tools.'
Install-WindowsFeature -Name RSAT-AD-Tools -IncludeManagementTools | Out-Null

Write-Log "Setting NIC DNS server to $DcIpAddress."
$nic = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $nic.InterfaceIndex -ServerAddresses $DcIpAddress

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

Write-Log 'Writing C:\ca-configure.ps1.'
$configureScript = @"
`$ErrorActionPreference = 'Stop'
`$logFile = 'C:\ca-configure.log'
function Write-Log { param(`$msg) "`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') `$msg" | Tee-Object -FilePath `$logFile -Append }

Write-Log 'CA configure starting.'
`$adcsInstalled = (Get-WindowsFeature ADCS-Cert-Authority).Installed

if (`$adcsInstalled) {
    Write-Log 'AD CS already installed. Removing scheduled task.'
    Unregister-ScheduledTask -TaskName 'ConfigureCA' -Confirm:`$false -ErrorAction SilentlyContinue
    exit 0
}

Write-Log 'Installing ADCS-Cert-Authority feature.'
Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools | Out-Null

Write-Log 'Configuring Enterprise Root CA: $CaCommonName'
`$secPass = ConvertTo-SecureString '$AdminPassword' -AsPlainText -Force
`$cred    = New-Object PSCredential ('$DomainName\$AdminUsername', `$secPass)

Install-AdcsCertificationAuthority ``
    -CAType EnterpriseRootCa ``
    -CACommonName '$CaCommonName' ``
    -KeyLength 4096 ``
    -HashAlgorithmName SHA256 ``
    -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' ``
    -ValidityPeriod Years ``
    -ValidityPeriodUnits 10 ``
    -Credential `$cred ``
    -Force | Out-Null

Write-Log 'Enterprise Root CA installed and running.'

Write-Log 'Verifying CA is responding (certutil -ping).'
`$pingOutput = & certutil -ping 2>&1 | Out-String
if (`$LASTEXITCODE -ne 0) {
    Write-Log "WARNING: certutil -ping failed (exit code `$LASTEXITCODE)."
    Write-Log `$pingOutput.Trim()
} else {
    Write-Log 'certutil -ping: CA responding successfully.'
}

Write-Log 'Checking Root CA cert in Cert:\LocalMachine\Root.'
`$rootCert = Get-ChildItem Cert:\LocalMachine\Root | ``
    Where-Object { `$_.Subject -like '*$CaCommonName*' }
if (`$rootCert) {
    Write-Log "Root CA cert found: `$(`$rootCert.Subject) [Thumbprint: `$(`$rootCert.Thumbprint)]"
} else {
    Write-Log 'WARNING: Root CA cert NOT found in Cert:\LocalMachine\Root. Auto-publish may not have completed yet.'
}

Unregister-ScheduledTask -TaskName 'ConfigureCA' -Confirm:`$false
"@

$configureScript | Out-File -FilePath 'C:\ca-configure.ps1' -Encoding UTF8 -Force

Write-Log 'Registering ConfigureCA scheduled task.'
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
                -Argument '-NonInteractive -ExecutionPolicy Bypass -File C:\ca-configure.ps1' `
                -WorkingDirectory 'C:\'
$trigger   = New-ScheduledTaskTrigger -AtStartup
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName 'ConfigureCA' `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Log 'Scheduling reboot in 30s. init.ps1 complete.'
shutdown /r /t 30
