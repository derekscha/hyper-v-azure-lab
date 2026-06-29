# Current State Snapshot

**Captured:** 2026-06-28
**Session summary:** Waves 0–3 fully deployed and verified. DC + CA healthy. Wave 1 DNS re-applied. Wave 4 = Cluster Nodes (next).

---

## What This Repo Is

Automation project to deploy a proof-of-concept Hyper-V failover cluster on Azure VMs running Windows Server 2025. Provisioning via Terraform (infrastructure) + PowerShell DSC (configuration). DSC pull server pattern chosen for portability to future on-prem VMware/Proxmox deployments.

---

## Repo State as of This Session

### Overall completion: ~60%

**What exists and is functional:**

- `scripts/bootstrap.ps1` — Wave 0 complete. Creates resource group, storage account (TF state backend), blob container, Key Vault, assigns RBAC roles, sets firewall rules.
- `environments/dev/wave1-net/` — Wave 1 Terraform root. Deployed. DNS re-applied with DC IP.
- `modules/network/` — network module: vNet, 5 subnets, 5 NSGs, NAT gateway, Azure Bastion toggle.
- `modules/compute/` — generic Windows VM module: NIC (static or dynamic IP), VM, CSE extension. **Complete — not a stub.**
- `environments/dev/wave2-dsc/` — Wave 2 Terraform root. Deployed.
- `vm-configs/dsc-pull-server/init.ps1` — Two-phase init: installs xPSDesiredStateConfiguration in parent process, runs DSC configuration in child process (required for module visibility). **Written and deployed.**
- `environments/dev/wave3-dc/` — Wave 3 Terraform root. Deployed. DC + CA in same RG.
- `vm-configs/domain-controller/init.ps1` — Two-phase DC promotion (CSE + scheduled task). **Deployed and verified.**
- `vm-configs/ca/init.ps1` — Enterprise Root CA: polls domain with explicit domain credentials, joins, scheduled task installs AD CS after reboot. **Deployed and verified.**
- `dsc-configs/domain-controller/domainConfig.ps1` — Updated to use `ActiveDirectoryDsc` (replaces deprecated `xActiveDirectory`).
- `dsc-configs/cluster-node/clusterNodeConfig.ps1` — Draft. Uses `[PSCredential]` params.
- All `dsc-configs/*/publish.ps1` files — compile and publish MOF to pull server.

**What is stale/superseded:**

- `dsc-configs/ca-primary/caPrimaryConfig.ps1`, `dsc-configs/ca-secondary/caSecondaryConfig.ps1` — dual-CA architecture dropped; CA is now init.ps1-only via `vm-configs/ca/init.ps1`

**What is empty (stub files only):**

- `vm-configs/ca-primary/init.ps1`, `vm-configs/ca-secondary/init.ps1` — superseded and abandoned (dual-CA arch dropped)
- `vm-configs/cluster-node/init.ps1` — next to write (Wave 4)
- `vm-configs/shared/functions.ps1`
- `modules/{arc,operations,security,storage}/` — no .tf files
- `docs/wiki/`

---

## Deployed Infrastructure (dev)

| Resource | Name | State |
| -------- | ---- | ----- |
| Resource Group (Wave 0) | `rg-hlb-dev-001` | Deployed |
| Storage Account (TF state) | `sthlbdev001` | Deployed |
| Key Vault | `kv-hlb-dev-001` | Deployed |
| Resource Group (Wave 1) | `rg-hlb-dev-net-001` | Deployed |
| VNet | `vnet-hyperv-lab` (10.50.0.0/16) | Deployed — DNS: 10.50.1.10 |
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
| NAT Gateway + PIP | `ngw-hyperv-lab` / `pip-nat` | Deployed |
| Azure Bastion + PIP | `bas-hyperv-lab` / `pip-bastion` | Toggle — on when needed |
| Resource Group (Wave 2) | `rg-hlb-dev-dsc-001` | Deployed |
| DSC Pull Server VM | `vm-dsc-dev-001` (Standard_D2s_v5, 10.50.1.x) | Deployed |
| DSC Pull Server endpoint | `https://<ip>:8080/PSDSCPullServer.svc` | **Confirmed healthy** |
| Resource Group (Wave 3) | `rg-hlb-dev-dc-001` | Deployed |
| Domain Controller VM | `vm-dc-dev-001` (Standard_D4s_v5, 10.50.1.10 static) | **Confirmed healthy** — `corp.lab` |
| Certificate Authority VM | `vm-ca-dev-001` (Standard_D4s_v5, dynamic IP) | **Confirmed healthy** — domain-joined, AD CS running |

**NAT Gateway subnet associations:** snet-mgmt, snet-vm-a, snet-vm-b (snet-cluster excluded — internal only).

**Access model:** No public IPs on any VM. RDP only via Azure Bastion. Enable with `deploy_bastion = true` in wave1 tfvars, destroy when done (~$0.19/hr Basic SKU).

**NSG rules summary:**

- `nsg-bastion`: HTTPS 443 inbound locked to `admin_cidr`. GatewayManager + AzureLoadBalancer + BastionHostComm per Azure requirement.
- `nsg-mgmt`: RDP (3389) from AzureBastionSubnet. WinRM (5985-5986) and DSC pull (8080) from VirtualNetwork. Default AllowVnetInbound (65000) covers AD DS ports (LDAP 389, DNS 53, Kerberos 88, etc.).
- `nsg-cluster`: All intra-subnet traffic (heartbeat, CSV, shared disk).
- `nsg-vm-a` / `nsg-vm-b`: Permissive — tighten per nested VM workload later.

---

## Key Vault Secrets

| Secret Name | Purpose | Status |
| ----------- | ------- | ------ |
| `local-admin-password` | VM local admin (labadmin) + domain admin credential | Set |
| `safe-mode-admin-password` | DSRM/SafeMode password for DC promotion | Set |

---

## Architecture Decisions Made

### VM SKUs

- Hyper-V Cluster Nodes: **Standard_D8s_v5** (nested virtualization, 4 NIC max, 16 data disks)
- Support VMs (DC, CA): **Standard_D4s_v5** — single Enterprise Root CA, not dual-CA
- DSC Pull Server: **Standard_D2s_v5**

### Cluster Storage

- **Azure Shared Disks** (Premium SSD, maxShares=2) — not S2D

### Networking

- Single vNet (10.50.0.0/16), 5 subnets
- 4 NICs per cluster node: mgmt / cluster heartbeat+CSV / VM traffic A / VM traffic B
- Support VMs: 1 NIC on snet-mgmt
- DC static IP: `10.50.1.10` — set as VNet DNS server in Wave 1 (applied)
- No public IPs on any VM

### DSC

- Pull server model (portability to vSphere/Proxmox)
- init.ps1 pattern: parent process installs module → child process runs DSC config (module visibility requirement)
- AD DS promotion via scheduled task (CSE exits 0 before reboot)

### CSE / Automation Credential Pattern

- CSE runs as LOCAL SYSTEM — no domain credentials on a non-domain-joined machine
- All AD operations from SYSTEM context (Get-ADDomain, Add-Computer, etc.) require explicit `-Credential` parameter
- Pattern: create `$cred = New-Object PSCredential("DOMAIN\user", $secPass)` before any AD call; applies to DC poll loops AND domain join in init.ps1
- Must be replicated in cluster-node init.ps1 (Wave 4)

### Credentials/Secrets

- All secrets in Azure Key Vault (Wave 0)
- Terraform retrieves and injects via `data.azurerm_key_vault_secret`
- No `Get-Credential` calls anywhere

### Active Directory

- Domain: `corp.lab` | NetBIOS: `CORP`
- Single DC for PoC (single point of failure acceptable)
- DNS integrated with AD DS on the DC

---

## Deployment Wave Sequence

| Wave | Scope | Status | Notes |
| ---- | ----- | ------ | ----- |
| 0 | Bootstrap: Storage Account + Key Vault | **Complete** | Azure CLI/PS script, NOT Terraform-managed |
| 1 | Networking: vNet, subnets, NSGs, NAT GW, Bastion toggle | **Complete** | DNS 10.50.1.10 applied |
| 2 | DSC Pull Server VM | **Complete** | OData endpoint confirmed healthy |
| 3 | DC + Enterprise Root CA (same RG) | **Complete** | corp.lab healthy; CA domain-joined, AD CS running, certutil -ping verified |
| 4 | Hyper-V Cluster Nodes | Not started | cluster-node init.ps1 not written yet |

---

## Cost Context

48-hour run with VMs deallocated when not in use (~8hr/day active):

- Estimated total: **$55–65**
- Disk costs continue even when VMs are deallocated
- Bastion billing: ~$0.19/hr — toggle off when not actively using RDP
- NAT Gateway: ~$0.045/hr (always on while Wave 1 deployed)

Region: **South Central US**

---

## Files to Reference in Future Sessions

- `ai/plans/2026-04-24_infra-arch-design.md` — full architecture plan
- `environments/dev/wave1-net/` — Wave 1 Terraform root
- `environments/dev/wave2-dsc/` — Wave 2 Terraform root (reference pattern)
- `environments/dev/wave3-dc/` — Wave 3 Terraform root (DC + CA, single RG)
- `modules/network/` — shared network module
- `modules/compute/` — shared compute module (static IP support)
- `vm-configs/dsc-pull-server/init.ps1` — reference for two-phase CSE init pattern
- `vm-configs/domain-controller/init.ps1` — two-phase DC promotion (CSE + scheduled task)
- `vm-configs/ca/init.ps1` — Enterprise Root CA: explicit-credential domain poll, domain join, scheduled task installs AD CS after reboot, certutil/cert-store validation
- `dsc-configs/domain-controller/domainConfig.ps1` — ActiveDirectoryDsc, ready
- `dsc-configs/cluster-node/clusterNodeConfig.ps1` — draft, needs review before Wave 4
