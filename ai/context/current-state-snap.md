# Current State Snapshot

**Captured:** 2026-07-10
**Session summary:** Cut over from Windows to Linux dev machine. Recreated missing `terraform.tfvars` for all four waves. Intentionally destroyed Waves 1–4 (to stop billing and validate a from-scratch deploy on the new machine). Redeployed Waves 1–3 successfully. Wave 4 partially deployed — VMs and disks created, but the `scripts` blob container/blob collided with a pre-existing Wave 0 artifact, so both CSE extensions never ran and the cluster nodes are unconfigured. All VMs deallocated at end of session to stop billing.

---

## What This Repo Is

Automation project to deploy a proof-of-concept Hyper-V failover cluster on Azure VMs running Windows Server 2025. Provisioning via Terraform (infrastructure) + PowerShell DSC (configuration). DSC pull server pattern chosen for portability to future on-prem VMware/Proxmox deployments.

---

## Repo State as of This Session

### Overall completion: ~80%

**What exists and is functional:**

- `scripts/bootstrap.ps1` — Wave 0 complete, idempotent. Creates RG, Storage Account (key-based auth disabled), `terraform-state` + `scripts` containers, Key Vault, placeholder secrets.
- `environments/dev/wave1-net/` — Wave 1 Terraform root. **Redeployed clean** on Linux: 23 resources added, 0 destroyed. DNS: `["10.50.1.10", "168.63.129.16"]`.
- `modules/network/` — network module: vNet, 5 subnets, 5 NSGs, NAT gateway, Azure Bastion toggle (off by default).
- `modules/compute/` — generic Windows VM module: NIC (static or dynamic IP), VM, CSE extension.
- `environments/dev/wave2-dsc/` — Wave 2 Terraform root. **Redeployed clean**: 4 resources added. CSE completed in 8m48s.
- `vm-configs/dsc-pull-server/init.ps1` — **Deployed and verified.** OData endpoint (`https://localhost:8080/PSDSCPullServer.svc`) confirmed healthy via `az vm run-command` (HTTP 200).
- `environments/dev/wave3-dc/` — Wave 3 Terraform root. **Redeployed clean**: 7 resources added. DC CSE completed in 5m58s, CA CSE in 9m10s.
- `vm-configs/domain-controller/init.ps1` — **Deployed and verified.** `Get-ADDomain` confirms NetBIOS `CORP`, domain mode `Windows2025Domain`, ADWS/DNS/NTDS all `Running`.
- `vm-configs/ca/init.ps1` — **Deployed and verified.** Domain-joined to `corp.lab`, `CertSvc` running.
- `vm-configs/cluster-node/init.ps1` — Written, not yet executed this session (CSE never ran — see blocker below).
- `environments/dev/wave4-cluster/` — Terraform plan clean (26 to add). **Apply partially failed**: 21/26 resources created (RG, both VMs, all 8 NICs, 3 shared disks, 6 disk attachments, managed identity). Failed on `azurerm_storage_container.scripts` — "already exists" — which blocked the role assignment and both CSE extensions.
- `dsc-configs/cluster-node/clusterNodeConfig.ps1` — Unchanged, ready to publish once nodes are configured.
- All `dsc-configs/*/publish.ps1` files — compile and publish MOF to pull server.

**What is stale/superseded:**

- `dsc-configs/ca-primary/caPrimaryConfig.ps1`, `dsc-configs/ca-secondary/caSecondaryConfig.ps1` — dual-CA architecture dropped
- `vm-configs/ca-primary/init.ps1`, `vm-configs/ca-secondary/init.ps1` — superseded and abandoned

**What is empty (stub files only):**

- `vm-configs/shared/functions.ps1`
- `modules/{arc,operations,security,storage}/` — no .tf files
- `docs/wiki/`

---

## Active Blocker: Wave 4 `scripts` container/blob ownership conflict

**Root cause:** `environments/dev/wave4-cluster/main.tf` declares `resource "azurerm_storage_container" "scripts"` and `resource "azurerm_storage_blob" "cluster_init"`, trying to manage both with Terraform. But the `scripts` container lives in Wave 0's storage account (`sthlbdev001`), which is never destroyed — so on every from-scratch Wave 4 redeploy, Terraform tries to create a container that already exists and errors: `A resource with the ID "https://sthlbdev001.blob.core.windows.net/scripts" already exists`.

**Blast radius:** Because that resource fails, its dependents never run: `azurerm_role_assignment.cluster_scripts_reader` (grants the cluster's managed identity read access to the container) and **both `azurerm_virtual_machine_extension` CSE resources** (cn1, cn2). Confirmed via `az vm extension list` — neither node has any extension. The cluster VMs exist, are domain-network-reachable, and have all 4 NICs + 3 shared disks attached, but are **not** domain-joined, have no Hyper-V/Failover Clustering features, and never pulled their DSC config.

**Agreed fix (not yet implemented — see `ai/plans/2026-07-10-wave4-bootstrap-ownership-fix.md`):** Move container creation *and* the `cluster-node-init.ps1` blob upload into `scripts/bootstrap.ps1` (Wave 0), which already creates the `scripts` container idempotently. Wave 4 switches both resources to `data` sources (`data.azurerm_storage_container`, `data.azurerm_storage_blob` — both confirmed present in the installed `hashicorp/azurerm` provider schema), so Terraform only reads them, never owns their lifecycle.

---

## Deployed Infrastructure (dev) — as of session end

| Resource | Name | State |
| -------- | ---- | ----- |
| Resource Group (Wave 0) | `rg-hlb-dev-001` | Deployed (never destroyed) |
| Storage Account (TF state) | `sthlbdev001` | Deployed — key-based auth disabled, AAD only |
| Blob Container | `terraform-state` | Deployed |
| Blob Container | `scripts` | Deployed (persisted through all wave teardowns) |
| Key Vault | `kv-hlb-dev-001` | Deployed |
| Resource Group (Wave 1) | `rg-hlb-dev-net-001` | Redeployed this session |
| VNet | `vnet-hyperv-lab` (10.50.0.0/16) | Redeployed — DNS: `["10.50.1.10", "168.63.129.16"]` |
| Subnets / NSGs / NAT GW | (5 each / 1) | Redeployed — NAT public IP `20.225.49.2` |
| Resource Group (Wave 2) | `rg-hlb-dev-dsc-001` | Redeployed |
| DSC Pull Server VM | `vm-dsc-dev-001` (Standard_D2s_v4, 10.50.1.4) | Redeployed, healthy, **deallocated** |
| Resource Group (Wave 3) | `rg-hlb-dev-dc-001` | Redeployed |
| Domain Controller VM | `vm-dc-dev-001` (Standard_D4s_v4, 10.50.1.10 static) | Redeployed, healthy (`corp.lab`), **deallocated** |
| Certificate Authority VM | `vm-ca-dev-001` (Standard_D4s_v4, 10.50.1.5) | Redeployed, healthy, domain-joined, **deallocated** |
| Resource Group (Wave 4) | `rg-hlb-dev-cluster-001` | Partially deployed |
| Cluster Node 1 | `vm-cn-dev-001` (Standard_D8s_v5, 10.50.1.20 mgmt) | VM up, **not configured** (CSE never ran), **deallocated** |
| Cluster Node 2 | `vm-cn-dev-002` (Standard_D8s_v5, 10.50.1.21 mgmt) | VM up, **not configured** (CSE never ran), **deallocated** |
| Shared Disk — Quorum | `disk-hlb-cluster-quorum` (32 GB, Premium LRS, maxShares=2) | Attached to both nodes |
| Shared Disk — CSV A | `disk-hlb-cluster-csv-a` (512 GB, Premium LRS, maxShares=2) | Attached to both nodes |
| Shared Disk — CSV B | `disk-hlb-cluster-csv-b` (512 GB, Premium LRS, maxShares=2) | Attached to both nodes |
| Managed Identity | `id-hlb-cluster-scripts` | Created, but **no role assignment** (blocked by the container error) |

**All 5 VMs deallocated at end of session** — compute billing stopped, disks/NICs/public IPs (none in use) remain.

**NAT Gateway subnet associations:** snet-mgmt, snet-vm-a, snet-vm-b (snet-cluster excluded — internal only).

**Access model:** No public IPs on any VM. RDP only via Azure Bastion (currently toggled off).

---

## Regional vCPU Quota (validated this session)

southcentralus, subscription `e61ca020-85e9-4d96-8947-b331a6b295fd`:

| Family | Used | Limit |
| ------ | ---- | ----- |
| Standard DSv4 (wave2 D2s_v4 + wave3 2x D4s_v4) | 10 | 20 |
| Standard DSv5 (wave4 2x D8s_v5) | 16 | 20 |
| Total Regional vCPUs | 26 | 60 |

No quota increase needed — the original 2026-06-29 blocker (quota exhausted) is resolved; today's Wave 4 issue is purely the storage container ownership bug above, unrelated to quota.

One unrelated note: `Standard_D8s_v5` has a subscription-level `NotAvailableForSubscription` restriction on **availability zone 2** in `southcentralus`. Not currently an issue since `wave4-cluster/main.tf` doesn't pin VMs to a zone — flag if zone pinning is ever added.

---

## Key Changes Made This Session

| Area | Change |
|------|--------|
| `wave1-net/terraform.tfvars` | Recreated from scratch (missing on new Linux machine — `.gitignore`d, never committed). Added `vnet_dns_servers = ["10.50.1.10", "168.63.129.16"]`. |
| `wave2-dsc/terraform.tfvars`, `wave3-dc/terraform.tfvars`, `wave4-cluster/terraform.tfvars` | Recreated from scratch. Cross-checked against this snapshot for `key_vault_name` and `cluster_node_config_id` (both confirmed correct). |
| Full teardown → redeploy | Confirmed intentional (cost control + fresh-install validation on the new Linux machine). |
| Wave 4 deploy | Failed partway — see Active Blocker above. |
| VM power state | All 5 VMs deallocated at session end. |

---

## Wave 4 Design (for reference)

**Cluster node config GUID:** `ee96e6d2-28b4-4ef3-b8ec-551ce58a1a18` (fixed value, must match `-ConfigurationId` passed to `dsc-configs/cluster-node/publish.ps1`)

**init.ps1 phases:**
- Phase 1 (CSE, SYSTEM): install RSAT-AD-Tools, set DNS on mgmt NIC (10.50.1.x), poll domain with explicit creds, domain join, write `C:\configure-node.ps1`, register `ConfigureClusterNode` scheduled task, reboot
- Phase 2 (startup task, SYSTEM): idempotency guard, install Hyper-V + Failover Clustering features, retrieve DSC pull server cert thumbprint dynamically via WebRequest, apply LCM pull config, write `C:\configure-node-validation.log` (10 PASS/FAIL checks), unregister task

**Validation logs to check after apply (once CSE actually runs):**
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
- Support VMs (DC, CA): **Standard_D4s_v4**
- DSC Pull Server: **Standard_D2s_v4**

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
- **New (pending implementation):** `scripts` container + `cluster-node-init.ps1` blob become Wave 0-owned artifacts, read by Wave 4 via `data` sources instead of managed as Wave 4 `resource`s (see Active Blocker above)

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
| 0 | Bootstrap: Storage Account + Key Vault | **Complete** | Never destroyed across sessions |
| 1 | Networking: vNet, subnets, NSGs, NAT GW, Bastion toggle | **Complete** | Redeployed clean this session |
| 2 | DSC Pull Server VM | **Complete** | Redeployed clean, OData endpoint healthy |
| 3 | DC + Enterprise Root CA (same RG) | **Complete** | Redeployed clean, `corp.lab` healthy, CA domain-joined |
| 4 | Hyper-V Cluster Nodes | **Blocked — storage container ownership bug** | VMs/disks up, CSE never ran. Fix planned, not yet applied. |

---

## Files to Reference in Future Sessions

- `ai/plans/2026-04-24_infra-arch-design.md` — full architecture plan
- `ai/plans/2026-07-10-wave4-bootstrap-ownership-fix.md` — Wave 4 blob/container fix + future CD pipeline design notes
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
