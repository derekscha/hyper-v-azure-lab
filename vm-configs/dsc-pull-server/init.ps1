#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
Install-Module -Name xPSDesiredStateConfiguration -Force -Scope AllUsers -AllowClobber

$cert = New-SelfSignedCertificate `
    -Subject "CN=$env:COMPUTERNAME" `
    -DnsName $env:COMPUTERNAME, 'localhost' `
    -CertStoreLocation 'Cert:\LocalMachine\My' `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(5)

$thumbprint = $cert.Thumbprint

# The DSC Configuration block must run in a child process. DSC's Import-DscResource
# resolver only sees modules present when the session started — Install-Module writes
# to disk but the current session's DSC engine cannot find it until a new process spawns.
$configScript = @"
`$ErrorActionPreference = 'Stop'
`$thumbprint = '$thumbprint'

Configuration SetupDscPullServer {
    param ([Parameter(Mandatory)][String]`$CertificateThumbprint)

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xPSDesiredStateConfiguration

    Node 'localhost' {
        WindowsFeature DSCServiceFeature {
            Name   = 'DSC-Service'
            Ensure = 'Present'
        }
        WindowsFeature IIS {
            Name   = 'Web-Server'
            Ensure = 'Present'
        }
        xDscWebService PSDSCPullServer {
            Ensure                   = 'Present'
            EndpointName             = 'PSDSCPullServer'
            Port                     = 8080
            PhysicalPath             = "`$env:SystemDrive\inetpub\wwwroot\PSDSCPullServer"
            CertificateThumbPrint    = `$CertificateThumbprint
            ModulePath               = "`$env:ProgramFiles\WindowsPowerShell\DscService\Modules"
            ConfigurationPath        = "`$env:ProgramFiles\WindowsPowerShell\DscService\Configuration"
            State                    = 'Started'
            UseSecurityBestPractices = `$true
            DependsOn                = '[WindowsFeature]DSCServiceFeature'
        }
        File CreateConfigFolder {
            DestinationPath = "`$env:ProgramFiles\WindowsPowerShell\DscService\Configuration"
            Type            = 'Directory'
            Ensure          = 'Present'
        }
        File CreateModuleFolder {
            DestinationPath = "`$env:ProgramFiles\WindowsPowerShell\DscService\Modules"
            Type            = 'Directory'
            Ensure          = 'Present'
        }
    }
}

`$mofOutputPath = 'C:\Windows\Temp\DscPullServer'
New-Item -ItemType Directory -Path `$mofOutputPath -Force | Out-Null
SetupDscPullServer -CertificateThumbprint `$thumbprint -OutputPath `$mofOutputPath
Start-DscConfiguration -Path `$mofOutputPath -Wait -Verbose -Force
"@

$configScript | Out-File -FilePath 'C:\dsc-configure.ps1' -Encoding UTF8 -Force

$proc = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', 'C:\dsc-configure.ps1' `
    -Wait -PassThru `
    -RedirectStandardOutput 'C:\dsc-configure.log' `
    -RedirectStandardError  'C:\dsc-configure-err.log'

if ($proc.ExitCode -ne 0) {
    $errLog = if (Test-Path 'C:\dsc-configure-err.log') { Get-Content 'C:\dsc-configure-err.log' -Raw } else { '(no stderr log)' }
    throw "DSC configuration child process exited $($proc.ExitCode). Stderr: $errLog"
}
