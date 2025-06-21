Configuration DomainConfig {

    param (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [String]$SafeModeAdministratorPassword
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
            DomainAdministratorCredential = (Get-Credential -UserName "Administrator" -Message "Domain Admin")
            SafemodeAdministratorPassword = (New-Object System.Management.Automation.PSCredential (
                                                    "unused",
                                                    (ConvertTo-SecureString $SafeModeAdministratorPassword -AsPlainText -Force)
                                                ))
            DependsOn = '[WindowsFeature]ADDSInstall'
            DomainNetbiosName             = $DomainName.Split('.')[0].ToUpper()
        }
    }
}
