# Infrastructure Architecture Design
**Date:** 2026-04-24  
**Author:** Derek Schaefer  
**Status:** Planning — no Terraform written yet

---

## Project Goal

Proof-of-concept Hyper-V failover cluster hosted on Azure VMs running Windows Server 2025. Fully automated provisioning via Terraform + PowerShell DSC. Architecture must be portable: DSC pull server pattern chosen deliberately to support future refactoring for on-premises VMware vSphere or Proxmox deployments without dependency on Azure-specific tooling (Arc, Azure Automation DSC).

---

## VM Inventory

| Role | Count | SKU | vCPU | RAM | Notes |
|------|-------|-----|------|-----|-------|
| DSC Pull Server | 1 | Standard_D2s_v5 | 2 | 8 GiB | Utility/config server |
| Domain Controller | 1 | Standard_D4s_v5 | 4 | 16 GiB | Single DC acceptable for PoC |
| CA Primary (Root CA) | 1 | Standard_D4s_v5 | 4 | 16 GiB | Offline standalone root CA |
| CA Secondary (Issuing CA) | 1 | Standard_D4s_v5 | 4 | 16 GiB | Enterprise subordinate CA |
| Hyper-V Cluster Node | 2 | Standard_D8s_v5 | 8 | 32 GiB | Nested virtualization required |

**Total: 6 VMs.** Optional 2nd DC adds ~$14/48hr but eliminates SPOF on domain.

Consider upgrading cluster nodes to **Standard_D8ds_v5** (+$0.064/hr each) for the 300 GiB local NVMe temp disk, useful for Hyper-V checkpoint scratch space.

---

## Deployment Wave Sequence

| Wave | Scope | Key Resources | Dependency |
|------|-------|---------------|------------|
| 0 | Bootstrap | Storage Account (Terraform state), Key Vault (secrets) | None — done via Azure CLI / bootstrap script, NOT Terraform-managed |
| 1 | Networking | vNet, subnets, NSGs, NICs | Wave 0 |
| 2 | DSC Pull Server | DSC VM, DSC service config, MOF upload from Git | Wave 1 |
| 3 | Domain | Domain Controller VM, AD DS, DNS | Wave 2 (pulls DSC config) |
| 4 | PKI | CA Primary VM, CA Secondary VM, ADCS | Wave 3 (needs domain) |
| 5 | Cluster | Hyper-V Node 1 + Node 2, failover cluster formation | Waves 3 + 4 (needs domain + certs) |

**Wave 0 note:** Terraform cannot store state in a Storage Account it creates itself (chicken-and-egg). Wave 0 must be a separate bootstrap script or a standalone Terraform workspace with local state that is not subsequently modified.

---

## Terraform Module Structure

```
modules/
  network/       vNet, subnets (mgmt, cluster, storage), NSGs
  compute/       Windows VM resource, NIC attachment, OS disk, custom script extension
  storage/       Premium SSD managed disks, shared disk config, Storage Account
  security/      Key Vault, access policies, secrets
  arc/           Reserved — future Arc integration (currently empty)
  operations/    Reserved — monitoring, Log Analytics (currently empty)

environments/
  dev/           Variable overrides for dev deployment
  qa/            Variable overrides for QA deployment
  prod/          Variable overrides for prod deployment
```

Separate Terraform workspaces per wave with remote state data sources for cross-wave output sharing.

---

## Networking Design

**Single vNet, multiple subnets, South Central US.**

| Subnet | Purpose |
|--------|---------|
| snet-mgmt | Host management, RDP/WinRM, Terraform, DSC registration |
| snet-cluster | Cluster heartbeat, CSV/storage traffic |
| snet-vm | VM external traffic, VLAN testing |

**NIC layout per Hyper-V cluster node (4 NICs — matches D8s_v5 max):**

| NIC | Subnet | Purpose |
|-----|--------|---------|
| NIC 0 | snet-mgmt | Host management |
| NIC 1 | snet-cluster | Cluster heartbeat + CSV traffic |
| NIC 2 | snet-vm | VM traffic / VLAN set A |
| NIC 3 | snet-vm | VM traffic / VLAN set B |

Support VMs (DSC, DC, CA) use 1–2 NICs on snet-mgmt only.

---

## Cluster Storage Decision

**Azure Shared Disks (Premium SSD, maxShares=2)** — not S2D.

S2D requires direct-attached local NVMe. The D8s_v5 series does not expose local NVMe to the guest in a way suitable for S2D. Azure Shared Disks are purpose-built for Windows Server Failover Clustering, attach natively as Cluster Shared Volumes (CSVs), and require no additional software-defined storage layer.

Recommended sizing: **P20 (512 GiB)** for basic PoC lab. Upgrade to P30 (1 TiB) if you plan to host multiple nested VMs.

---

## DSC Architecture

Pull server model. Each VM's LCM registers with the DSC Pull Server on first boot via init.ps1. MOF files are compiled from configs in `dsc-configs/` and published to the pull server as part of Wave 2.

**Current DSC status:**

| Config | File | Status |
|--------|------|--------|
| Domain Controller | dsc-configs/domain-controller/domainConfig.ps1 | Draft — functional but uses Get-Credential (blocks automation) |
| Cluster Node | dsc-configs/cluster-node/clusterNodeConfig.ps1 | Draft — functional but uses Get-Credential |
| CA Primary | dsc-configs/ca-primary/caPrimaryConfig.ps1 | BROKEN — is a copy of clusterNodeConfig, not ADCS config |
| CA Secondary | dsc-configs/ca-secondary/caSecondaryConfig.ps1 | BROKEN — same copy-paste error |
| DSC Pull Server | dsc-configs/dsc-pull-server/setupDscPullServer.ps1 | Looks complete |
| All publish.ps1 | dsc-configs/*/publish.ps1 | All import wrong config file — need per-role customization |

**Required DSC fixes before Wave 2:**
1. Rewrite CA Primary config — ADCS standalone offline root CA using `xAdcsDeployment`
2. Rewrite CA Secondary config — ADCS enterprise subordinate CA
3. Refactor all configs to accept `[PSCredential]` parameters (no `Get-Credential` calls)
4. Fix each `publish.ps1` to import its own role's config file

---

## Credential / Secrets Strategy

All credentials (domain admin, safe mode password, local admin) stored in Key Vault (Wave 0). Terraform retrieves secrets from Key Vault and passes them as `PSCredential` parameters to DSC configs via `custom_script_extension` or `azurerm_virtual_machine_extension`. No interactive credential prompts anywhere in the automation path.

---

## Cost Reference (48-Hour PAYG, South Central US)

| Category | ~48hr Cost |
|----------|-----------|
| VM Compute (6 VMs) | $103.67 |
| Storage (OS disks + shared disk + data disks) | $17.53 |
| Networking (public IPs + ILB) | $2.69 |
| Supporting services (Key Vault, Storage Account) | $0.18 |
| **Total (VMs on 24hr/day)** | **~$124** |
| **Total (VMs on 8hr/day × 2 days)** | **~$55–65** |

Disk costs accrue even when VMs are deallocated. Deallocating VMs when not actively working saves ~$2.16/hr across all 6 VMs.

---

## Immediate Next Steps (as of 2026-04-24)

1. Bootstrap script (Azure CLI/PowerShell) — Storage Account for Terraform state + Key Vault
2. `modules/network` — first Terraform module, everything depends on it
3. Fix DSC CA configs and credential handling in parallel with Terraform work
4. `modules/compute` and `modules/storage`
5. Wave 2 end-to-end: DSC Pull Server deploys, MOFs upload, LCM registers
