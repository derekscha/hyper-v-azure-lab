#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)][string]$DomainName,
    [Parameter(Mandatory)][string]$AdminPassword,
    [Parameter(Mandatory)][string]$SafeModePassword
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$logFile = 'C:\init.log'
function Write-Log { param($msg) "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Tee-Object -FilePath $logFile -Append }

Write-Log 'DC init.ps1 starting.'

Write-Log 'Installing NuGet package provider.'
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null

Write-Log 'Installing ActiveDirectoryDsc module.'
Install-Module -Name ActiveDirectoryDsc -Force -Scope AllUsers -AllowClobber

Write-Log 'Installing AD-Domain-Services feature.'
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

$netbios = $DomainName.Split('.')[0].ToUpper()
Write-Log "Domain: $DomainName  NetBIOS: $netbios"

Write-Log 'Writing C:\promote-dc.ps1.'
$promoteScript = @"
`$ErrorActionPreference = 'Stop'
`$logFile = 'C:\promote-dc.log'
function Write-Log { param(`$msg) "`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') `$msg" | Tee-Object -FilePath `$logFile -Append }

Write-Log 'DC promotion starting.'
`$safeMode = ConvertTo-SecureString '$SafeModePassword' -AsPlainText -Force
Import-Module ADDSDeployment
Write-Log 'Running Install-ADDSForest for $DomainName.'
Install-ADDSForest ``
    -DomainName '$DomainName' ``
    -DomainNetBIOSName '$netbios' ``
    -SafeModeAdministratorPassword `$safeMode ``
    -InstallDns ``
    -NoRebootOnCompletion:`$false ``
    -Force
Write-Log 'Install-ADDSForest complete. Rebooting.'
Unregister-ScheduledTask -TaskName 'PromoteDC' -Confirm:`$false
"@

$promoteScript | Out-File -FilePath 'C:\promote-dc.ps1' -Encoding UTF8 -Force

Write-Log 'Registering PromoteDC scheduled task.'
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
                -Argument '-NonInteractive -ExecutionPolicy Bypass -File C:\promote-dc.ps1' `
                -WorkingDirectory 'C:\'
$trigger   = New-ScheduledTaskTrigger -AtStartup
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName 'PromoteDC' `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Log 'Starting PromoteDC task. CSE will exit before reboot.'
Start-ScheduledTask -TaskName 'PromoteDC'

Write-Log 'init.ps1 complete.'
