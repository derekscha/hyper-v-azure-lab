# Current State Snapshot
**Captured:** 2026-04-24  
**Session summary:** Initial repo review + architecture planning discussion

---

## What This Repo Is

Automation project to deploy a proof-of-concept Hyper-V failover cluster on Azure VMs running Windows Server 2025. Provisioning via Terraform (infrastructure) + PowerShell DSC (configuration). DSC pull server pattern chosen for portability to future on-prem VMware/Proxmox deployments.

---

## Repo State as of This Session

### Overall completion: ~10-15%

**What exists and is functional (or near-functional):**
- Full directory/folder hierarchy
- `dsc-configs/domain-controller/domainConfig.ps1` — installs AD DS, creates first DC. Has `Get-Credential` call that must be refactored for automation.
- `dsc-configs/cluster-node/clusterNodeConfig.ps1` — joins domain, installs Hyper-V + Failover Clustering features. Has same `Get-Credential` issue.
- `dsc-configs/dsc-pull-server/setupDscPullServer.ps1` — configures DSC Pull Server on IIS port 8080. Appears complete.
- Generic `publish.ps1` template present in all DSC role folders.

**What is broken:**
- `dsc-configs/ca-primary/caPrimaryConfig.ps1` — is a copy-paste of clusterNodeConfig, not an ADCS config. Must be rewritten.
- `dsc-configs/ca-secondary/caSecondaryConfig.ps1` — same copy-paste error.
- All `publish.ps1` files import the wrong config file (all reference DomainConfig instead of their own role's config).

**What is empty (stub files only):**
- All Terraform files: `main.tf`, `provider.tf`, `variables.tf`, `terraform.tfvars` (root)
- All `environments/{dev,qa,prod}/` Terraform files
- All `modules/{arc,compute,network,operations,security,storage}/` directories (no .tf files at all)
- All `vm-configs/*/init.ps1` files
- `vm-configs/shared/functions.ps1`
- `scripts/` directory
- `docs/wiki/`

---

## Architecture Decisions Made This Session

### VM SKUs
- Hyper-V Cluster Nodes: **Standard_D8s_v5** (nested virtualization, 4 NIC max, 16 data disks)
- Support VMs (DC, CA x2): **Standard_D4s_v5**
- DSC Pull Server: **Standard_D2s_v5**
- Optional upgrade for cluster nodes: **Standard_D8ds_v5** for local NVMe temp disk

### Cluster Storage
- **Azure Shared Disks** (Premium SSD, maxShares=2) — not S2D
- S2D ruled out: D8s_v5 doesn't expose local NVMe suitable for S2D
- Shared disks attach natively as CSVs in Windows Server Failover Clustering

### Networking
- Single vNet, 3 subnets: snet-mgmt, snet-cluster, snet-vm
- 4 NICs per cluster node: mgmt / cluster heartbeat+CSV / VM traffic A / VM traffic B
- 1-2 NICs on support VMs (mgmt only)

### DSC
- Pull server model retained (not Arc/Azure Automation DSC)
- Rationale: portability to vSphere/Proxmox; backwards compatibility

### Credentials/Secrets
- All secrets in Azure Key Vault (Wave 0)
- Terraform retrieves and injects as PSCredential parameters
- No Get-Credential calls anywhere in automation path

---

## Deployment Wave Sequence Agreed Upon

| Wave | Scope | Notes |
|------|-------|-------|
| 0 | Bootstrap: Storage Account (TF state) + Key Vault | Azure CLI/PS script, NOT Terraform-managed (chicken-and-egg) |
| 1 | Networking: vNet, subnets, NSGs, NICs | Foundation for all other waves |
| 2 | DSC Pull Server VM + MOF upload | Must be up before VMs pull configs |
| 3 | Domain Controller(s) | Pulls DSC config; establishes AD DS + DNS |
| 4 | CA Primary + CA Secondary | Needs domain; cluster nodes need certs |
| 5 | Hyper-V Cluster Nodes | Needs domain + CA + DSC all healthy |

Separate Terraform workspaces per wave. Cross-wave output sharing via remote state data sources.

---

## Cost Context

48-hour run with VMs deallocated when not in use (~8hr/day active):
- Estimated total: **$55–65**
- Full 48hr powered on: **~$124**
- Disk costs continue even when VMs are deallocated

Region: **South Central US**  
Licensing: Windows Server PAYG (included in VM rate)

---

## Immediate Next Steps Agreed Upon

1. **Bootstrap script** — Azure CLI or PowerShell to create Storage Account + Key Vault before any Terraform is run
2. **`modules/network`** — first Terraform module; all other waves depend on it
3. **Fix DSC CA configs** — rewrite caPrimaryConfig.ps1 (offline root CA) and caSecondaryConfig.ps1 (enterprise subordinate CA) using `xAdcsDeployment`
4. **Refactor DSC credential handling** — replace all Get-Credential calls with PSCredential parameters
5. **Fix all publish.ps1 scripts** — each must import its own role's config file

Steps 2 and 3 can be done in parallel.

---

## Files to Reference in Future Sessions

- `ai/plans/2026-04-24_infra-arch-design.md` — full architecture plan with tables and rationale
- `dsc-configs/domain-controller/domainConfig.ps1` — working draft DSC config
- `dsc-configs/cluster-node/clusterNodeConfig.ps1` — working draft DSC config
- `dsc-configs/dsc-pull-server/setupDscPullServer.ps1` — appears complete
- `dsc-configs/ca-primary/caPrimaryConfig.ps1` — needs full rewrite (ADCS)
- `dsc-configs/ca-secondary/caSecondaryConfig.ps1` — needs full rewrite (ADCS)
