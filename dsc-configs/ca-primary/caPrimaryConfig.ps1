# dsc-configs/ca-primary/caPrimaryConfig.ps1
Configuration CAPrimaryConfig {
    param (
        [Parameter(Mandatory)]
        [PSCredential] $CAAdminCredential
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryCSDsc

    Node "localhost" {

        WindowsFeature ADCS-Cert-Authority {
            Ensure = 'Present'
            Name   = 'ADCS-Cert-Authority'
        }

        WindowsFeature ADCS-Web-Enrollment {
            Ensure    = 'Present'
            Name      = 'ADCS-Web-Enrollment'
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority'
        }

        ADCSCertificationAuthority RootCA {
            Ensure                    = 'Present'
            Credential                = $CAAdminCredential
            CAType                    = 'StandaloneRootCA'
            CACommonName              = 'HyperV-Lab-Root-CA'
            CADistinguishedNameSuffix = 'DC=hyperv,DC=lab'
            CryptoProviderName        = 'RSA#Microsoft Software Key Storage Provider'
            HashAlgorithmName         = 'SHA256'
            KeyLength                 = 4096
            ValidityPeriod            = 'Years'
            ValidityPeriodUnits       = 10
            DependsOn                 = '[WindowsFeature]ADCS-Cert-Authority'
        }
    }
}
