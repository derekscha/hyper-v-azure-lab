# Current State Snapshot

**Captured:** 2026-06-29
**Session summary:** Wave 4 Terraform complete and plan verified. Blocked on regional vCPU quota increase. Waves 2 & 3 redeployed with DSv4 SKUs. Wave 1 re-applied with dual DNS. Storage auth redesigned to managed identity.

---

## What This Repo Is

Automation project to deploy a proof-of-concept Hyper-V failover cluster on Azure VMs running Windows Server 2025. Provisioning via Terraform (infrastructure) + PowerShell DSC (configuration). DSC pull server pattern chosen for portability to future on-prem VMware/Proxmox deployments.

---

## Repo State as of This Session

### Overall completion: ~75%

**What exists and is functional:**

- `scripts/bootstrap.ps1` — Wave 0 complete. Now creates TWO containers: `terraform-state` and `scripts`. Scripts container needed for wave 4 CSE blob download. Idempotent — safe to re-run.
- `environments/dev/wave1-net/` — Wave 1 Terraform root. Deployed. DNS updated: `["10.50.1.10", "168.63.129.16"]` — DC first, Azure resolver fallback for provisioning-time internet access.
- `modules/network/` — network module: vNet, 5 subnets, 5 NSGs, NAT gateway, Azure Bastion toggle.
- `modules/compute/` — generic Windows VM module: NIC (static or dynamic IP), VM, CSE extension.
- `environments/dev/wave2-dsc/` — Wave 2 Terraform root. **Redeployed** on Standard_D2s_v4.
- `vm-configs/dsc-pull-server/init.ps1` — Two-phase init: installs xPSDesiredStateConfiguration, runs DSC configuration in child process. **Deployed and verified.**
- `environments/dev/wave3-dc/` — Wave 3 Terraform root. SKUs changed to D4s_v4. Redeploy pending or complete.
- `vm-configs/domain-controller/init.ps1` — Two-phase DC promotion (CSE + scheduled task). Uses `Install-PackageProvider -Name NuGet` + `Install-Module ActiveDirectoryDsc`. **Deployed and verified.**
- `vm-configs/ca/init.ps1` — Enterprise Root CA init. NuGet bootstrap line removed (CA never needed it — no PSGallery modules installed). **Deployed and verified.**
- `vm-configs/cluster-node/init.ps1` — **Written.** Two-phase: domain join + scheduled task (Phase 1 via CSE), feature install + LCM pull config (Phase 2 via startup task). Validation log written to `C:\configure-node-validation.log`.
- `environments/dev/wave4-cluster/` — **Terraform complete. Plan verified. Apply blocked on vCPU quota.**
- `dsc-configs/cluster-node/clusterNodeConfig.ps1` — Updated. No params, no external modules, `Node 'localhost'`, five WindowsFeature blocks only.
- All `dsc-configs/*/publish.ps1` files — compile and publish MOF to pull server.

**What is stale/superseded:**

- `dsc-configs/ca-primary/caPrimaryConfig.ps1`, `dsc-configs/ca-secondary/caSecondaryConfig.ps1` — dual-CA architecture dropped
- `vm-configs/ca-primary/init.ps1`, `vm-configs/ca-secondary/init.ps1` — superseded and abandoned

**What is empty (stub files only):**

- `vm-configs/shared/functions.ps1`
- `modules/{arc,operations,security,storage}/` — no .tf files
- `docs/wiki/`

---

## Deployed Infrastructure (dev)

| Resource | Name | State |
| -------- | ---- | ----- |
| Resource Group (Wave 0) | `rg-hlb-dev-001` | Deployed |
| Storage Account (TF state) | `sthlbdev001` | Deployed — key-based auth **disabled**, AAD only |
| Blob Container | `terraform-state` | Deployed |
| Blob Container | `scripts` | Deployed — created and permitted manually |
| Key Vault | `kv-hlb-dev-001` | Deployed |
| Resource Group (Wave 1) | `rg-hlb-dev-net-001` | Deployed |
| VNet | `vnet-hyperv-lab` (10.50.0.0/16) | Deployed — DNS: `["10.50.1.10", "168.63.129.16"]` |
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
| DSC Pull Server VM | `vm-dsc-dev-001` (**Standard_D2s_v4**, 10.50.1.x) | **Confirmed healthy** |
| DSC Pull Server endpoint | `https://<ip>:8080/PSDSCPullServer.svc` | **Confirmed healthy** |
| Resource Group (Wave 3) | `rg-hlb-dev-dc-001` | Deployed |
| Domain Controller VM | `vm-dc-dev-001` (**Standard_D4s_v4**, 10.50.1.10 static) | **Confirmed healthy** — `corp.lab` |
| Certificate Authority VM | `vm-ca-dev-001` (**Standard_D4s_v4**, dynamic IP) | **Confirmed healthy** — domain-joined, AD CS running |
| Resource Group (Wave 4) | `rg-hlb-cluster-dev-001` | **Not yet deployed — quota blocked** |
| Cluster Node 1 | `vm-cn-dev-001` (Standard_D8s_v5, 10.50.1.20 mgmt) | Pending quota |
| Cluster Node 2 | `vm-cn-dev-002` (Standard_D8s_v5, 10.50.1.21 mgmt) | Pending quota |
| Shared Disk — Quorum | `disk-hlb-cluster-quorum` (32 GB, Premium LRS, maxShares=2) | Pending |
| Shared Disk — CSV A | `disk-hlb-cluster-csv-a` (512 GB, Premium LRS, maxShares=2) | Pending |
| Shared Disk — CSV B | `disk-hlb-cluster-csv-b` (512 GB, Premium LRS, maxShares=2) | Pending |

**NAT Gateway subnet associations:** snet-mgmt, snet-vm-a, snet-vm-b (snet-cluster excluded — internal only).

**Access model:** No public IPs on any VM. RDP only via Azure Bastion.

---

## Blocking Issues (as of 2026-06-29)

1. **Regional vCPU quota** — Total Regional vCPUs exhausted. Wave 4 needs 16 more cores (2× D8s_v5). Quota increase request submitted. No code changes needed — `terraform apply` will succeed once quota is granted.
2. ~~**`scripts` blob container**~~ — ✓ Created and permitted manually. No action needed.

---

## Key Changes Made This Session

| Area | Change |
|------|--------|
| Wave 1 DNS | Added `168.63.129.16` as VNet fallback DNS — fixes PSGallery/internet access during CSE execution before DC is provisioned |
| Wave 2 SKU | `Standard_D2s_v5` → `Standard_D2s_v4` (different quota pool) |
| Wave 3 SKUs | DC + CA: `Standard_D4s_v5` → `Standard_D4s_v4` |
| NuGet bootstrap | Root cause was missing DNS fallback, not PSGallery feed change. Reverted to original `Install-PackageProvider -Name NuGet` after DNS fix confirmed working. CA init.ps1 had dead NuGet call removed (CA installs no PSGallery modules). |
| Storage auth | `sthlbdev001` disallows key-based auth. Wave 4 switched to: `storage_use_azuread = true` in provider + user-assigned managed identity (`id-hlb-cluster-scripts`) on cluster VMs + `Storage Blob Data Reader` role on scripts container + CSE `protected_settings` uses `managedIdentity.clientId` instead of `storageAccountKey` |
| bootstrap.ps1 | Now creates both `terraform-state` and `scripts` containers |
| Wave 4 Terraform | Complete. Plan verified clean. |

---

## Wave 4 Design (for reference)

**Cluster node config GUID:** `ee96e6d2-28b4-4ef3-b8ec-551ce58a1a18`

**init.ps1 phases:**
- Phase 1 (CSE, SYSTEM): install RSAT-AD-Tools, set DNS on mgmt NIC (10.50.1.x), poll domain with explicit creds, domain join, write `C:\configure-node.ps1`, register `ConfigureClusterNode` scheduled task, reboot
- Phase 2 (startup task, SYSTEM): idempotency guard, install Hyper-V + Failover Clustering features, retrieve DSC pull server cert thumbprint dynamically via WebRequest, apply LCM pull config, write `C:\configure-node-validation.log` (10 PASS/FAIL checks), unregister task

**Validation logs to check after apply:**
- `C:\init.log` — Phase 1 (CSE)
- `C:\configure-node.log` — Phase 2 (scheduled task)
- `C:\configure-node-validation.log` — all checks should show `[PASS]`

**After wave 4 nodes are healthy:** run `.\dsc-configs\cluster-node\publish.ps1 -ConfigurationId ee96e6d2-28b4-4ef3-b8ec-551ce58a1a18` from the DSC pull server.

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
- Support VMs (DC, CA): **Standard_D4s_v4** — moved from v5 to free DSv5 quota for cluster nodes
- DSC Pull Server: **Standard_D2s_v4** — moved from v5 for same reason

### Cluster Storage

- **Azure Shared Disks** (Premium SSD, maxShares=2) — not S2D
- Two CSV disks (csv-a, csv-b) for live storage migration testing

### Networking

- Single vNet (10.50.0.0/16), 5 subnets
- 4 NICs per cluster node: mgmt / cluster heartbeat+CSV / VM traffic A / VM traffic B
- Support VMs: 1 NIC on snet-mgmt
- DC static IP: `10.50.1.10` — primary VNet DNS
- Azure DNS `168.63.129.16` — VNet DNS fallback (critical for PSGallery access during CSE)
- No public IPs on any VM

### Storage Auth

- `sthlbdev001` has key-based auth disabled (set during bootstrap)
- Terraform state backend uses `use_azuread_auth = true` (all waves)
- Wave 4 storage data plane uses `storage_use_azuread = true` in provider
- Wave 4 CSE blob download uses user-assigned managed identity (not storage key)

### DSC

- Pull server model (portability to vSphere/Proxmox)
- init.ps1 pattern: parent process installs module → child process runs DSC config (module visibility requirement)
- AD DS promotion via scheduled task (CSE exits 0 before reboot)

### CSE / Automation Credential Pattern

- CSE runs as LOCAL SYSTEM — no domain credentials on a non-domain-joined machine
- All AD operations from SYSTEM context require explicit `-Credential` parameter
- Pattern: `$cred = New-Object PSCredential("DOMAIN\user", $secPass)` before any AD call

### Active Directory

- Domain: `corp.lab` | NetBIOS: `CORP`
- Single DC for PoC
- DNS integrated with AD DS on DC

---

## Deployment Wave Sequence

| Wave | Scope | Status | Notes |
| ---- | ----- | ------ | ----- |
| 0 | Bootstrap: Storage Account + Key Vault | **Complete** | `scripts` container created and permitted manually |
| 1 | Networking: vNet, subnets, NSGs, NAT GW, Bastion toggle | **Complete** | DNS: 10.50.1.10 + 168.63.129.16 |
| 2 | DSC Pull Server VM | **Complete** | D2s_v4. OData endpoint confirmed healthy |
| 3 | DC + Enterprise Root CA (same RG) | **Complete** | D4s_v4. corp.lab healthy; CA domain-joined, AD CS running |
| 4 | Hyper-V Cluster Nodes | **Blocked — quota** | Terraform plan clean. Waiting on Total Regional vCPU quota increase. |

---

## Files to Reference in Future Sessions

- `ai/plans/2026-04-24_infra-arch-design.md` — full architecture plan
- `scripts/bootstrap.ps1` — Wave 0 bootstrap (creates storage account, both containers, Key Vault)
- `environments/dev/wave1-net/` — Wave 1 Terraform root
- `environments/dev/wave2-dsc/` — Wave 2 Terraform root
- `environments/dev/wave3-dc/` — Wave 3 Terraform root (DC + CA, single RG)
- `environments/dev/wave4-cluster/` — Wave 4 Terraform root (cluster nodes, managed identity, fileUris CSE)
- `modules/network/` — shared network module
- `modules/compute/` — shared compute module
- `vm-configs/dsc-pull-server/init.ps1` — reference for two-phase CSE init pattern
- `vm-configs/domain-controller/init.ps1` — two-phase DC promotion
- `vm-configs/ca/init.ps1` — Enterprise Root CA: explicit-credential domain poll, domain join, scheduled task
- `vm-configs/cluster-node/init.ps1` — cluster node: 4-NIC DNS targeting, domain join, feature install, LCM pull config, validation log
- `dsc-configs/cluster-node/clusterNodeConfig.ps1` — five WindowsFeature blocks, ready to publish
