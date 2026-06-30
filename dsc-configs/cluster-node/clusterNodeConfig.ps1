Configuration ClusterNodeConfig {

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node 'localhost' {

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

    }
}
