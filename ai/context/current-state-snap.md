# Current State Snapshot
**Captured:** 2026-06-26  
**Session summary:** Wave 1 networking deployed to Azure — vNet, 5 subnets, 5 NSGs, Bastion toggle. No public IPs on VMs. Wave 2 (VMs) is next.

---

## What This Repo Is

Automation project to deploy a proof-of-concept Hyper-V failover cluster on Azure VMs running Windows Server 2025. Provisioning via Terraform (infrastructure) + PowerShell DSC (configuration). DSC pull server pattern chosen for portability to future on-prem VMware/Proxmox deployments.

---

## Repo State as of This Session

### Overall completion: ~30-35%

**What exists and is functional:**
- Full directory/folder hierarchy
- `scripts/bootstrap.ps1` — Wave 0 complete. Creates resource group, storage account (TF state backend), blob container, Key Vault, assigns RBAC roles, sets firewall rules. `AllowedIpAddress` param is now mandatory (no hardcoded IP default).
- `environments/dev/wave1-net/` — Wave 1 Terraform root. Remote state backend configured (`terraform-state` container, key `dev/wave1-net/terraform.tfstate`).
- `modules/network/` — network module: vNet, 5 subnets, 5 NSGs, Azure Bastion toggle.
- `dsc-configs/domain-controller/domainConfig.ps1` — installs AD DS, creates first DC. Uses `[PSCredential]` params (no `Get-Credential`).
- `dsc-configs/cluster-node/clusterNodeConfig.ps1` — joins domain, installs Hyper-V + Failover Clustering. Uses `[PSCredential]` params.
- `dsc-configs/ca-primary/caPrimaryConfig.ps1` — rewritten as StandaloneRootCA using `ActiveDirectoryCSDsc`. RSA 4096, SHA256, 10yr validity.
- `dsc-configs/ca-secondary/caSecondaryConfig.ps1` — rewritten as EnterpriseSubordinateCA using `ActiveDirectoryCSDsc`. RSA 2048, SHA256.
- `dsc-configs/dsc-pull-server/setupDscPullServer.ps1` — configures DSC Pull Server on IIS port 8080.
- All `publish.ps1` files — each dot-sources its own role's config file and invokes the correct Configuration function.

**What is empty (stub files only):**

- All `vm-configs/*/init.ps1` files
- `vm-configs/shared/functions.ps1`
- `modules/{arc,compute,operations,security,storage}/` — no .tf files
- `docs/wiki/`

---

## Deployed Infrastructure (dev)

| Resource | Name | State |
| -------- | ---- | ----- |
| Resource Group (Wave 0) | `rg-hlb-dev-001` | Deployed |
| Storage Account (TF state) | `sthlbdev001` (approx) | Deployed |
| Key Vault | — | Deployed |
| Resource Group (Wave 1) | `rg-hlb-dev-net-001` | Deployed |
| VNet | `vnet-hyperv-lab` (10.50.0.0/16) | Deployed |
| Subnet — Bastion | `AzureBastionSubnet` (10.50.0.0/26) | Deployed |
| Subnet — Mgmt | `snet-mgmt` (10.50.1.0/24) | Deployed |
| Subnet — Cluster | `snet-cluster` (10.50.2.0/24) | Deployed |
| Subnet — VM-A | `snet-vm-a` (10.50.3.0/24) | Deployed |
| Subnet — VM-B | `snet-vm-b` (10.50.4.0/24) | Deployed |
| NSG — Bastion | `nsg-bastion` | Deployed |
| NSG — Mgmt | `nsg-mgmt` | Deployed |
| NSG — Cluster | `nsg-cluster` | Deployed |
| NSG — VM-A | `nsg-vm-a` | Deployed |
| NSG — VM-B | `nsg-vm-b` | Deployed |
| Azure Bastion + PIP | `bas-hyperv-lab` / `pip-bastion` | **Toggled off** (`deploy_bastion = false`) |

**Access model:** No public IPs on any VM. RDP only via Azure Bastion. Enable with `deploy_bastion = true` in `terraform.tfvars`, destroy when done to stop billing (~$0.19/hr Basic SKU).

**NSG rules summary:**

- `nsg-bastion`: HTTPS 443 inbound locked to `admin_cidr` only (not open Internet). GatewayManager + AzureLoadBalancer + BastionHostComm allowed per Azure requirement. RDP/SSH outbound to VirtualNetwork.
- `nsg-mgmt`: RDP (3389) from `AzureBastionSubnet` only. WinRM (5985-5986) and DSC pull (8080) from VirtualNetwork only.
- `nsg-cluster`: All intra-subnet traffic (heartbeat, CSV, shared disk).
- `nsg-vm-a` / `nsg-vm-b`: Permissive — tighten per nested VM workload in a later wave.

---

## Architecture Decisions Made

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

- Single vNet (`10.50.0.0/16`), 5 subnets (Bastion, mgmt, cluster, vm-a, vm-b)
- 4 NICs per cluster node: mgmt / cluster heartbeat+CSV / VM traffic A / VM traffic B
- 1-2 NICs on support VMs (mgmt only)
- **No public IPs on any VM** — Bastion is the sole ingress

### DSC

- Pull server model retained (not Arc/Azure Automation DSC)
- Rationale: portability to vSphere/Proxmox; backwards compatibility

### Credentials/Secrets

- All secrets in Azure Key Vault (Wave 0)
- Terraform retrieves and injects as PSCredential parameters
- No `Get-Credential` calls anywhere in automation path

---

## Deployment Wave Sequence

| Wave | Scope | Status | Notes |
| ---- | ----- | ------ | ----- |
| 0 | Bootstrap: Storage Account (TF state) + Key Vault | **Complete** | Azure CLI/PS script, NOT Terraform-managed |
| 1 | Networking: vNet, subnets, NSGs, Bastion toggle | **Complete — deployed** | Foundation for all other waves |
| 2 | DSC Pull Server VM + MOF upload | **Next** | Must be up before VMs pull configs |
| 3 | Domain Controller(s) | Not started | Pulls DSC config; establishes AD DS + DNS |
| 4 | CA Primary + CA Secondary | Not started | Needs domain; cluster nodes need certs |
| 5 | Hyper-V Cluster Nodes | Not started | Needs domain + CA + DSC all healthy |

Separate Terraform workspaces per wave. Cross-wave output sharing via `terraform_remote_state` data sources.

---

## Cost Context

48-hour run with VMs deallocated when not in use (~8hr/day active):

- Estimated total: **$55–65**
- Full 48hr powered on: **~$124**
- Disk costs continue even when VMs are deallocated
- Bastion billing: ~$0.19/hr — keep toggled off when not actively using RDP

Region: **South Central US**  
Licensing: Windows Server PAYG (included in VM rate)

---

## Files to Reference in Future Sessions

- `ai/plans/2026-04-24_infra-arch-design.md` — full architecture plan with tables and rationale
- `ai/plans/2026-06-26-wave-1-networking.md` — Wave 1 implementation plan (complete)
- `environments/dev/wave1-net/` — Wave 1 Terraform root (provider, variables, main, outputs, tfvars)
- `modules/network/` — shared network module (vnet, subnets, NSGs, bastion toggle)
- `dsc-configs/domain-controller/domainConfig.ps1` — working draft DSC config
- `dsc-configs/cluster-node/clusterNodeConfig.ps1` — working draft DSC config
- `dsc-configs/dsc-pull-server/setupDscPullServer.ps1` — appears complete
- `dsc-configs/ca-primary/caPrimaryConfig.ps1` — rewritten, ready
- `dsc-configs/ca-secondary/caSecondaryConfig.ps1` — rewritten, ready
