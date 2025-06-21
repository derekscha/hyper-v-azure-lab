Configuration ClusterNodeConfig {

    param (
        [Parameter(Mandatory)]
        [String]$NodeName,

        [Parameter(Mandatory)]
        [String]$DomainName
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xComputerManagement

    Node $NodeName {

        # Optional: Join the domain (if not done manually or by Azure AD DS extension)
        xComputer JoinDomain {
            Name       = $NodeName
            DomainName = $DomainName
            Credential = (Get-Credential -UserName "CORP\\JoinUser" -Message "Domain Join Credential")
        }

        WindowsFeature HyperV {
            Name   = "Hyper-V"
            Ensure = "Present"
        }

        WindowsFeature FailoverCluster {
            Name   = "Failover-Clustering"
            Ensure = "Present"
        }

        WindowsFeature RSATClusteringMgmt {
            Name   = "RSAT-Clustering-Mgmt"
            Ensure = "Present"
        }

        WindowsFeature RSATClusteringPowerShell {
            Name   = "RSAT-Clustering-PowerShell"
            Ensure = "Present"
        }

        WindowsFeature RSATHyperVTools {
            Name   = "RSAT-Hyper-V-Tools"
            Ensure = "Present"
        }

        # Optional: Reboot if needed
        xPendingReboot RebootAfterInstall {
            Name = "RebootNodeIfNeeded"
        }

    }
}
