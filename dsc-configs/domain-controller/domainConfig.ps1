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
    Import-DscResource -ModuleName ActiveDirectoryDsc

    Node 'localhost' {

        WindowsFeature ADDSInstall {
            Name   = 'AD-Domain-Services'
            Ensure = 'Present'
        }

        WindowsFeature RSATTools {
            Name      = 'RSAT-AD-Tools'
            Ensure    = 'Present'
            DependsOn = '[WindowsFeature]ADDSInstall'
        }

        ADDomain FirstDC {
            DomainName                    = $DomainName
            DomainNetBIOSName             = $DomainName.Split('.')[0].ToUpper()
            Credential                    = $DomainAdminCredential
            SafemodeAdministratorPassword = $SafeModeAdminCredential
            DependsOn                     = '[WindowsFeature]ADDSInstall'
        }
    }
}
