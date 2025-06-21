Configuration SetupDscPullServer {

    param (
        [Parameter(Mandatory)]
        [String]$CertificateThumbprint
    )

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
            Ensure                  = 'Present'
            EndpointName            = 'PSDSCPullServer'
            Port                    = 8080
            PhysicalPath            = "$env:SystemDrive\inetpub\wwwroot\PSDSCPullServer"
            CertificateThumbPrint   = $CertificateThumbprint
            ModulePath              = "$env:ProgramFiles\WindowsPowerShell\DscService\Modules"
            ConfigurationPath       = "$env:ProgramFiles\WindowsPowerShell\DscService\Configuration"
            State                   = 'Started'
            UseSecurityBestPractices = $true
            DependsOn               = '[WindowsFeature]DSCServiceFeature'
        }

        File CreateConfigFolder {
            DestinationPath = "$env:ProgramFiles\WindowsPowerShell\DscService\Configuration"
            Type            = 'Directory'
            Ensure          = 'Present'
        }

        File CreateModuleFolder {
            DestinationPath = "$env:ProgramFiles\WindowsPowerShell\DscService\Modules"
            Type            = 'Directory'
            Ensure          = 'Present'
        }
    }
}
