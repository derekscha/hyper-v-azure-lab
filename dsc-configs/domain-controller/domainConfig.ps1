Configuration DomainConfig {

    param (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [PSCredential]$DomainAdminCredential,

        [Parameter(Mandatory)]
        [PSCredential]$SafeModeAdminCredential
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xActiveDirectory

    Node "localhost" {

        WindowsFeature 'ADDSInstall' {
            Name   = 'AD-Domain-Services'
            Ensure = 'Present'
        }

        WindowsFeature 'RSATTools' {
            Name   = 'RSAT-AD-Tools'
            Ensure = 'Present'
        }

        xADDomain FirstDC {
            DomainName                    = $DomainName
            DomainAdministratorCredential = $DomainAdminCredential
            SafemodeAdministratorPassword = $SafeModeAdminCredential
            DependsOn = '[WindowsFeature]ADDSInstall'
            DomainNetbiosName             = $DomainName.Split('.')[0].ToUpper()
        }
    }
}
