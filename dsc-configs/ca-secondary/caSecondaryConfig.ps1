# dsc-configs/ca-secondary/caSecondaryConfig.ps1
Configuration CASecondaryConfig {
    param (
        [Parameter(Mandatory)]
        [PSCredential] $CAAdminCredential,

        [Parameter(Mandatory)]
        [PSCredential] $DomainAdminCredential
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryCSDsc

    Node $AllNodes.NodeName {

        WindowsFeature ADCS-Cert-Authority {
            Ensure = 'Present'
            Name   = 'ADCS-Cert-Authority'
        }

        WindowsFeature ADCS-Web-Enrollment {
            Ensure    = 'Present'
            Name      = 'ADCS-Web-Enrollment'
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority'
        }

        ADCSCertificationAuthority IssuingCA {
            Ensure                    = 'Present'
            Credential                = $DomainAdminCredential
            CAType                    = 'EnterpriseSubordinateCA'
            CACommonName              = 'HyperV-Lab-Issuing-CA'
            CADistinguishedNameSuffix = 'DC=hyperv,DC=lab'
            CryptoProviderName        = 'RSA#Microsoft Software Key Storage Provider'
            HashAlgorithmName         = 'SHA256'
            KeyLength                 = 2048
            DependsOn                 = '[WindowsFeature]ADCS-Cert-Authority'
        }
    }
}
