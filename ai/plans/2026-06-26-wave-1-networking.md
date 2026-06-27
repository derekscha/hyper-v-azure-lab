# Wave 1: Networking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and apply the Azure virtual networking layer (vNet, subnets, NSGs) using Terraform with remote state backend backed by the Wave 0 bootstrap Storage Account.

**Architecture:** `environments/dev/wave1-net/` is the Terraform root for this wave. It calls `modules/network` (repo root, shared) to create one vNet, four subnets (snet-mgmt, snet-cluster, snet-vm-a, snet-vm-b), and four NSGs with associations — all in a dedicated resource group `rg-hlb-dev-net-001`. State is stored remotely in the Wave 0 Storage Account under key `dev/wave1-net/terraform.tfstate`. Outputs (subnet IDs, vNet ID) are written to state so Wave 2 can read them via `terraform_remote_state`.

**Tech Stack:** Terraform >= 1.8, AzureRM provider ~> 3.110, Azure South Central US

## Global Constraints

- Region: `southcentralus`
- All resources tagged: `Project = "hyper-v-azure-lab"`, `Environment = "development"`, `ManagedBy = "Terraform"`, `workload = "hyper-v-azure-lab"`
- Wave 1 TF root: `environments/dev/wave1-net/`
- Wave 1 resource group: `rg-hlb-dev-net-001` (Terraform-managed, Wave 1 only)
- Bootstrap resource group: `rg-hlb-dev-001` (pre-existing, holds TF state SA + KV)
- vNet address space: `10.50.0.0/16`
- snet-mgmt CIDR: `10.50.1.0/24`
- snet-cluster CIDR: `10.50.2.0/24`
- snet-vm-a CIDR: `10.50.3.0/24` (cluster node NIC 2 — VM traffic VLAN set A)
- snet-vm-b CIDR: `10.50.4.0/24` (cluster node NIC 3 — VM traffic VLAN set B)
- State key for this wave: `dev/wave1-net/terraform.tfstate`
- Container name (from Wave 0): `terraform-state`

**NIC layout for Hyper-V cluster nodes (4 NICs):**
| NIC | Subnet | Purpose |
|-----|--------|---------|
| NIC 0 | snet-mgmt | Host management |
| NIC 1 | snet-cluster | Cluster heartbeat + CSV traffic |
| NIC 2 | snet-vm-a | VM traffic / VLAN set A |
| NIC 3 | snet-vm-b | VM traffic / VLAN set B |

Support VMs (DSC, DC, CA) use 1–2 NICs on snet-mgmt only.

---

## Context

Wave 0 (bootstrap.ps1) creates the Storage Account for Terraform remote state and the Key Vault for secrets. All lab infrastructure starts in Wave 1. Every subsequent wave (VMs, DSC, AD, PKI, cluster) depends on the network resources created here — subnet IDs and NSG IDs are the primary cross-wave contract.

Parallel to Wave 1 Terraform work, DSC fixes (CA configs, credential refactor, publish.ps1 corrections) should be done as pre-Wave-2 tasks. These do not block Wave 1 networking but must be complete before Wave 2 (DSC Pull Server) can be applied.

---

## File Map

**Create (new files):**

- `environments/dev/wave1-net/provider.tf` — AzureRM provider + backend config
- `environments/dev/wave1-net/variables.tf` — Wave 1 input variables
- `environments/dev/wave1-net/outputs.tf` — Wave 1 outputs (written to remote state; consumed by later waves via `terraform_remote_state`)
- `environments/dev/wave1-net/main.tf` — Resource group + module call
- `environments/dev/wave1-net/terraform.tfvars` — Dev values (subscription ID, admin CIDR, etc.) — `.gitignore` covers `*.tfvars` ✓
- `modules/network/main.tf` — vNet, subnets, NSGs, associations
- `modules/network/variables.tf` — Module input variables
- `modules/network/outputs.tf` — Module outputs (IDs consumed by Wave 1 outputs)

**Not touched in Wave 1:**

- `modules/compute/`, `modules/storage/`, `modules/security/` — Wave 2+
- `environments/dev/wave2-dsc/` through `wave5-cluster/` — future waves
- `environments/qa/`, `environments/prod/` — future environments
- All DSC configs — parallel pre-Wave-2 track (see Task 6+)

---

## Wave 1 Tasks

### Task 1: Validate Wave 0 artifacts

**Purpose:** Confirm the Storage Account and Key Vault from bootstrap.ps1 exist. Retrieve the storage account name (it has a generated suffix) for use in the backend config.

**Files:** None created — read-only verification step.

- [ ] **Step 1: Run bootstrap.ps1 if not already done**

  If you haven't already run the bootstrap script in a previous session:

  ```powershell
  Set-Location d:\eeznuts\hyper-v-azure-lab
  .\scripts\bootstrap.ps1
  ```

  If it was already run, skip this step.

- [ ] **Step 2: Retrieve and record the storage account name**

  ```powershell
  az storage account list --resource-group rg-hlb-dev-001 --query "[].name" -o tsv
  ```

  Expected output: a single name like `sthlbdev001`. Record this — you need it for `provider.tf`.

- [ ] **Step 3: Verify Key Vault exists**

  ```powershell
  az keyvault list --resource-group rg-hlb-dev-001 --query "[].name" -o tsv
  ```

  Expected output: a Key Vault name like `kv-hyperv-lab-XXXXXX`. Confirm it exists.

- [ ] **Step 4: Confirm blob container exists**

  ```powershell
  $saName = "<storage account name from Step 2>"
  az storage container list --account-name $saName --auth-mode login --query "[].name" -o tsv
  ```

  Expected output: `tfstate`

---

### Task 2: Root Terraform provider and backend

**Files:**

- Create: `d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\provider.tf`
- Create: `d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\variables.tf`
- Create: `d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\terraform.tfvars`

**Interfaces:**

- Produces: `var.subscription_id`, `var.location`, `var.resource_group_name`, `var.tags`, `var.admin_cidr`, subnet CIDR variables — consumed by Task 3 and Task 4

- [ ] **Step 1: Write provider.tf**

  Replace `<STORAGE_ACCOUNT_NAME>` with the value from Task 1 Step 2.

  ```hcl
  # d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\provider.tf
  terraform {
    required_version = ">= 1.8"

    required_providers {
      azurerm = {
        source  = "hashicorp/azurerm"
        version = "~> 3.110"
      }
    }

    backend "azurerm" {
      resource_group_name  = "rg-hlb-dev-001"
      storage_account_name = "<STORAGE_ACCOUNT_NAME>"
      container_name       = "terraform-state"
      key                  = "dev/wave1-net/terraform.tfstate"
    }
  }

  provider "azurerm" {
    features {}
    subscription_id = var.subscription_id
  }
  ```

- [ ] **Step 2: Write variables.tf**

  ```hcl
  # d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\variables.tf
  variable "subscription_id" {
    type        = string
    description = "Azure subscription ID"
  }

  variable "location" {
    type        = string
    description = "Azure region for all resources"
    default     = "southcentralus"
  }

  variable "resource_group_name" {
    type        = string
    description = "Resource group for Wave 1 networking resources"
    default     = "rg-hlb-dev-net-001"
  }

  variable "tags" {
    type        = map(string)
    description = "Common tags applied to all resources"
    default = {
      Project     = "hyper-v-azure-lab"
      Environment = "development"
      ManagedBy   = "Terraform"
      workload    = "hyper-v-azure-lab"
    }
  }

  variable "admin_cidr" {
    type        = string
    description = "Your public IP CIDR allowed for RDP/WinRM (e.g., 1.2.3.4/32)"
  }

  variable "vnet_address_space" {
    type    = list(string)
    default = ["10.50.0.0/16"]
  }

  variable "subnet_mgmt_cidr" {
    type    = string
    default = "10.50.1.0/24"
  }

  variable "subnet_cluster_cidr" {
    type    = string
    default = "10.50.2.0/24"
  }

  variable "subnet_vm_a_cidr" {
    type        = string
    description = "VM traffic subnet A (cluster node NIC 2 / VLAN set A)"
    default     = "10.50.3.0/24"
  }

  variable "subnet_vm_b_cidr" {
    type        = string
    description = "VM traffic subnet B (cluster node NIC 3 / VLAN set B)"
    default     = "10.50.4.0/24"
  }
  ```

- [ ] **Step 3: Write terraform.tfvars**

  Fill in your actual subscription ID and public IP. This file is secrets-adjacent — confirm `.gitignore` covers `*.tfvars` before committing.

  ```hcl
  # d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\terraform.tfvars
  subscription_id     = "YOUR-SUBSCRIPTION-ID-HERE"
  location            = "southcentralus"
  resource_group_name = "rg-hlb-dev-net-001"
  admin_cidr          = "YOUR.PUBLIC.IP.ADDRESS/32"
  vnet_address_space  = ["10.50.0.0/16"]
  subnet_mgmt_cidr    = "10.50.1.0/24"
  subnet_cluster_cidr = "10.50.2.0/24"
  subnet_vm_a_cidr    = "10.50.3.0/24"
  subnet_vm_b_cidr    = "10.50.4.0/24"
  ```

- [ ] **Step 4: Verify .gitignore covers terraform.tfvars**

  ```powershell
  Select-String -Path d:\eeznuts\hyper-v-azure-lab\.gitignore -Pattern "tfvars"
  ```

  If no match, add `*.tfvars` (but NOT `*.tfvars.example`) to `.gitignore` before committing.

---

### Task 3: Root main.tf and outputs.tf

**Files:**

- Create: `d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\main.tf`
- Create: `d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\outputs.tf`

**Interfaces:**

- Consumes: `var.*` from Task 2, `module.network.*` outputs from Task 4
- Produces: root-level outputs written to state, consumed by Wave 2 via `terraform_remote_state`

- [ ] **Step 1: Write main.tf**

  ```hcl
  # d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\main.tf
  resource "azurerm_resource_group" "lab" {
    name     = var.resource_group_name
    location = var.location
    tags     = var.tags
  }

  module "network" {
    source = "../../../modules/network"

    resource_group_name = azurerm_resource_group.lab.name
    location            = var.location
    tags                = var.tags

    address_space       = var.vnet_address_space
    subnet_mgmt_cidr    = var.subnet_mgmt_cidr
    subnet_cluster_cidr = var.subnet_cluster_cidr
    subnet_vm_a_cidr    = var.subnet_vm_a_cidr
    subnet_vm_b_cidr    = var.subnet_vm_b_cidr
    admin_cidr          = var.admin_cidr
  }
  ```

- [ ] **Step 2: Write outputs.tf**

  ```hcl
  # d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net\outputs.tf
  output "vnet_id" {
    value = module.network.vnet_id
  }

  output "vnet_name" {
    value = module.network.vnet_name
  }

  output "subnet_mgmt_id" {
    value = module.network.subnet_mgmt_id
  }

  output "subnet_cluster_id" {
    value = module.network.subnet_cluster_id
  }

  output "subnet_vm_a_id" {
    value = module.network.subnet_vm_a_id
  }

  output "subnet_vm_b_id" {
    value = module.network.subnet_vm_b_id
  }

  output "nsg_mgmt_id" {
    value = module.network.nsg_mgmt_id
  }

  output "nsg_cluster_id" {
    value = module.network.nsg_cluster_id
  }

  output "resource_group_name" {
    value = azurerm_resource_group.lab.name
  }

  output "location" {
    value = var.location
  }
  ```

---

### Task 4: modules/network implementation

**Files:**

- Create: `d:\eeznuts\hyper-v-azure-lab\modules\network\main.tf`
- Create: `d:\eeznuts\hyper-v-azure-lab\modules\network\variables.tf`
- Create: `d:\eeznuts\hyper-v-azure-lab\modules\network\outputs.tf`

**Interfaces:**

- Consumes: `var.resource_group_name`, `var.location`, `var.tags`, `var.address_space`, `var.subnet_mgmt_cidr`, `var.subnet_cluster_cidr`, `var.subnet_vm_a_cidr`, `var.subnet_vm_b_cidr`, `var.admin_cidr`
- Produces: `vnet_id`, `vnet_name`, `subnet_mgmt_id`, `subnet_cluster_id`, `subnet_vm_a_id`, `subnet_vm_b_id`, `nsg_mgmt_id`, `nsg_cluster_id` — consumed by root `outputs.tf`

- [ ] **Step 1: Write modules/network/variables.tf**

  ```hcl
  # d:\eeznuts\hyper-v-azure-lab\modules\network\variables.tf
  variable "resource_group_name" {
    type = string
  }

  variable "location" {
    type = string
  }

  variable "tags" {
    type    = map(string)
    default = {}
  }

  variable "address_space" {
    type    = list(string)
    default = ["10.50.0.0/16"]
  }

  variable "subnet_mgmt_cidr" {
    type = string
  }

  variable "subnet_cluster_cidr" {
    type = string
  }

  variable "subnet_vm_a_cidr" {
    type        = string
    description = "VM traffic subnet A (cluster node NIC 2)"
  }

  variable "subnet_vm_b_cidr" {
    type        = string
    description = "VM traffic subnet B (cluster node NIC 3)"
  }

  variable "admin_cidr" {
    type        = string
    description = "CIDR allowed inbound for RDP (3389) and WinRM (5985-5986) on snet-mgmt"
  }
  ```

- [ ] **Step 2: Write modules/network/main.tf**

  ```hcl
  # d:\eeznuts\hyper-v-azure-lab\modules\network\main.tf
  resource "azurerm_virtual_network" "lab" {
    name                = "vnet-hyperv-lab"
    location            = var.location
    resource_group_name = var.resource_group_name
    address_space       = var.address_space
    tags                = var.tags
  }

  resource "azurerm_subnet" "mgmt" {
    name                 = "snet-mgmt"
    resource_group_name  = var.resource_group_name
    virtual_network_name = azurerm_virtual_network.lab.name
    address_prefixes     = [var.subnet_mgmt_cidr]
  }

  resource "azurerm_subnet" "cluster" {
    name                 = "snet-cluster"
    resource_group_name  = var.resource_group_name
    virtual_network_name = azurerm_virtual_network.lab.name
    address_prefixes     = [var.subnet_cluster_cidr]
  }

  resource "azurerm_subnet" "vm_a" {
    name                 = "snet-vm-a"
    resource_group_name  = var.resource_group_name
    virtual_network_name = azurerm_virtual_network.lab.name
    address_prefixes     = [var.subnet_vm_a_cidr]
  }

  resource "azurerm_subnet" "vm_b" {
    name                 = "snet-vm-b"
    resource_group_name  = var.resource_group_name
    virtual_network_name = azurerm_virtual_network.lab.name
    address_prefixes     = [var.subnet_vm_b_cidr]
  }

  # NSG: Management subnet — allow RDP and WinRM from admin IP only
  resource "azurerm_network_security_group" "mgmt" {
    name                = "nsg-mgmt"
    location            = var.location
    resource_group_name = var.resource_group_name
    tags                = var.tags

    security_rule {
      name                       = "Allow-RDP-Inbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = var.admin_cidr
      destination_address_prefix = "*"
    }

    security_rule {
      name                       = "Allow-WinRM-Inbound"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "5985-5986"
      source_address_prefix      = var.admin_cidr
      destination_address_prefix = "*"
    }

    security_rule {
      name                       = "Allow-DSC-Pull-Inbound"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "8080"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "*"
    }
  }

  # NSG: Cluster subnet — allow all intra-subnet traffic (heartbeat, CSV, shared disk)
  resource "azurerm_network_security_group" "cluster" {
    name                = "nsg-cluster"
    location            = var.location
    resource_group_name = var.resource_group_name
    tags                = var.tags

    security_rule {
      name                       = "Allow-ClusterIntranet-Inbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = var.subnet_cluster_cidr
      destination_address_prefix = var.subnet_cluster_cidr
    }
  }

  # NSG: VM subnets — permissive for now, tighten per nested VM workload later
  resource "azurerm_network_security_group" "vm_a" {
    name                = "nsg-vm-a"
    location            = var.location
    resource_group_name = var.resource_group_name
    tags                = var.tags
  }

  resource "azurerm_network_security_group" "vm_b" {
    name                = "nsg-vm-b"
    location            = var.location
    resource_group_name = var.resource_group_name
    tags                = var.tags
  }

  resource "azurerm_subnet_network_security_group_association" "mgmt" {
    subnet_id                 = azurerm_subnet.mgmt.id
    network_security_group_id = azurerm_network_security_group.mgmt.id
  }

  resource "azurerm_subnet_network_security_group_association" "cluster" {
    subnet_id                 = azurerm_subnet.cluster.id
    network_security_group_id = azurerm_network_security_group.cluster.id
  }

  resource "azurerm_subnet_network_security_group_association" "vm_a" {
    subnet_id                 = azurerm_subnet.vm_a.id
    network_security_group_id = azurerm_network_security_group.vm_a.id
  }

  resource "azurerm_subnet_network_security_group_association" "vm_b" {
    subnet_id                 = azurerm_subnet.vm_b.id
    network_security_group_id = azurerm_network_security_group.vm_b.id
  }
  ```

- [ ] **Step 3: Write modules/network/outputs.tf**

  ```hcl
  # d:\eeznuts\hyper-v-azure-lab\modules\network\outputs.tf
  output "vnet_id" {
    value = azurerm_virtual_network.lab.id
  }

  output "vnet_name" {
    value = azurerm_virtual_network.lab.name
  }

  output "subnet_mgmt_id" {
    value = azurerm_subnet.mgmt.id
  }

  output "subnet_cluster_id" {
    value = azurerm_subnet.cluster.id
  }

  output "subnet_vm_a_id" {
    value = azurerm_subnet.vm_a.id
  }

  output "subnet_vm_b_id" {
    value = azurerm_subnet.vm_b.id
  }

  output "nsg_mgmt_id" {
    value = azurerm_network_security_group.mgmt.id
  }

  output "nsg_cluster_id" {
    value = azurerm_network_security_group.cluster.id
  }
  ```

---

### Task 5: Terraform init, plan, and apply

**Files:** None created — execution steps only.

**Interfaces:**

- Consumes: All files from Tasks 2-4 + Task 1 Storage Account
- Produces: Azure resources; `wave1/terraform.tfstate` in remote backend with subnet/vNet IDs

- [ ] **Step 1: Authenticate to Azure**

  ```powershell
  az login
  az account set --subscription "YOUR-SUBSCRIPTION-ID-HERE"
  az account show --query "{name:name, id:id}" -o table
  ```

  Confirm correct subscription is selected.

- [ ] **Step 2: Run terraform init**

  ```powershell
  Set-Location d:\eeznuts\hyper-v-azure-lab\environments\dev\wave1-net
  terraform init
  ```

  Expected: "Terraform has been successfully initialized!" and backend config accepted. If backend fails, verify the storage account name in `provider.tf` matches Task 1 Step 2 exactly.

- [ ] **Step 3: Run terraform validate**

  ```powershell
  terraform validate
  ```

  Expected: `Success! The configuration is valid.`
  If errors appear, fix them before proceeding.

- [ ] **Step 4: Run terraform plan**

  ```powershell
  terraform plan -out=wave1.tfplan
  ```

  Expected: Plan shows 14 resources to add: 1 resource group, 1 vNet, 4 subnets, 4 NSGs, 4 NSG associations.
  Review the plan output — verify CIDRs match the global constraints above. No destroy actions should appear.

- [ ] **Step 5: Apply**

  ```powershell
  terraform apply wave1.tfplan
  ```

  Expected: `Apply complete! Resources: 14 added, 0 changed, 0 destroyed.`

- [ ] **Step 6: Verify outputs**

  ```powershell
  terraform output
  ```

  Expected: All outputs populated with Azure resource IDs. Example:

  ```
  location            = "southcentralus"
  nsg_cluster_id      = "/subscriptions/.../nsg-cluster"
  nsg_mgmt_id         = "/subscriptions/.../nsg-mgmt"
  resource_group_name = "rg-hlb-dev-net-001"
  subnet_cluster_id   = "/subscriptions/.../snet-cluster"
  subnet_mgmt_id      = "/subscriptions/.../snet-mgmt"
  subnet_vm_a_id      = "/subscriptions/.../snet-vm-a"
  subnet_vm_b_id      = "/subscriptions/.../snet-vm-b"
  vnet_id             = "/subscriptions/.../vnet-hyperv-lab"
  vnet_name           = "vnet-hyperv-lab"
  ```

- [ ] **Step 7: Verify in portal or CLI**

  ```powershell
  az network vnet show --resource-group rg-hlb-dev-net-001 --name vnet-hyperv-lab --query "{addressSpace:addressSpace, subnets:subnets[].name}" -o table
  ```

  Expected: vnet-hyperv-lab with subnets snet-mgmt, snet-cluster, snet-vm-a, snet-vm-b.

- [ ] **Step 8: Commit**

  ```powershell
  git add environments/dev/wave1-net/ modules/network/
  git commit -m "feat(wave1-net): implement networking layer - vNet, subnets, NSGs"
  ```

---

## Parallel Pre-Wave-2 DSC Track

These tasks do not block Wave 1 Terraform but must be complete before Wave 2 (DSC Pull Server VM).
Can be worked in any order, or in parallel with Wave 1 tasks.

### Task 6: Fix all publish.ps1 scripts

Each `publish.ps1` currently imports `DomainConfig.ps1` regardless of role. Each must import its own role's config file.

**Files to modify:**

- `dsc-configs/domain-controller/publish.ps1`
- `dsc-configs/cluster-node/publish.ps1`
- `dsc-configs/ca-primary/publish.ps1`
- `dsc-configs/ca-secondary/publish.ps1`
- `dsc-configs/dsc-pull-server/publish.ps1`

- [ ] **Step 1: Read current publish.ps1 template**

  Open `dsc-configs/domain-controller/publish.ps1`. Identify the line that imports the config file (will look like `. .\DomainConfig.ps1` or similar dot-sourcing).

- [ ] **Step 2: Fix each publish.ps1**

  For each role, change the dot-source/import line to reference the correct file:
  - `domain-controller/publish.ps1` → `. .\domainConfig.ps1`
  - `cluster-node/publish.ps1` → `. .\clusterNodeConfig.ps1`
  - `ca-primary/publish.ps1` → `. .\caPrimaryConfig.ps1`
  - `ca-secondary/publish.ps1` → `. .\caSecondaryConfig.ps1`
  - `dsc-pull-server/publish.ps1` → `. .\setupDscPullServer.ps1`

- [ ] **Step 3: Commit**

  ```powershell
  git add dsc-configs/
  git commit -m "fix(dsc): correct publish.ps1 import paths for each role"
  ```

---

### Task 7: Refactor DSC credential handling

Replace `Get-Credential` calls in domain-controller and cluster-node configs with `[PSCredential]` parameters. Credentials will be injected by Terraform via the custom script extension at VM boot time.

**Files to modify:**

- `dsc-configs/domain-controller/domainConfig.ps1`
- `dsc-configs/cluster-node/clusterNodeConfig.ps1`

- [ ] **Step 1: Read domainConfig.ps1**

  Open `dsc-configs/domain-controller/domainConfig.ps1`. Find all `Get-Credential` calls and note the variable names they assign to.

- [ ] **Step 2: Refactor domainConfig.ps1**

  Convert the DSC configuration from inline `Get-Credential` to parameter-driven. Pattern:

  Before:

  ```powershell
  Configuration DomainConfig {
      # ...
      $Credential = Get-Credential -Message "Enter domain admin credentials"
  ```

  After:

  ```powershell
  Configuration DomainConfig {
      param (
          [Parameter(Mandatory)]
          [PSCredential] $DomainAdminCredential,

          [Parameter(Mandatory)]
          [PSCredential] $SafeModeAdminCredential
      )
  ```

  Replace every `$Credential` / `Get-Credential` usage downstream with the appropriate parameter name.

- [ ] **Step 3: Read clusterNodeConfig.ps1 and apply same pattern**

  Open `dsc-configs/cluster-node/clusterNodeConfig.ps1`. Apply the same `[PSCredential]` parameter pattern, replacing `Get-Credential` calls.

- [ ] **Step 4: Commit**

  ```powershell
  git add dsc-configs/domain-controller/domainConfig.ps1 dsc-configs/cluster-node/clusterNodeConfig.ps1
  git commit -m "fix(dsc): replace Get-Credential with PSCredential params for automation"
  ```

---

### Task 8: Rewrite CA Primary DSC config (offline root CA)

`caPrimaryConfig.ps1` is currently a copy of `clusterNodeConfig.ps1`. Rewrite it as a proper ADCS standalone offline root CA config using the `ActiveDirectoryCSDsc` DSC resource.

**Files:**

- Rewrite: `dsc-configs/ca-primary/caPrimaryConfig.ps1`

**Interfaces:**

- Consumes: `[PSCredential] $CAAdminCredential` parameter
- Produces: DSC config named `CAPrimaryConfig` that installs ADCS and configures a standalone root CA

- [ ] **Step 1: Write caPrimaryConfig.ps1**

  ```powershell
  # dsc-configs/ca-primary/caPrimaryConfig.ps1
  Configuration CAPrimaryConfig {
      param (
          [Parameter(Mandatory)]
          [PSCredential] $CAAdminCredential
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
  ```

  **Note:** `ADCSCertificationAuthority` is from the `ActiveDirectoryCSDsc` module (v4+, successor to `xAdcsDeployment`). Install on the pull server: `Install-Module -Name ActiveDirectoryCSDsc -Force`.

- [ ] **Step 2: Commit**

  ```powershell
  git add dsc-configs/ca-primary/caPrimaryConfig.ps1
  git commit -m "feat(dsc): implement CA primary offline root CA config using ActiveDirectoryCSDsc"
  ```

---

### Task 9: Rewrite CA Secondary DSC config (enterprise issuing CA)

`caSecondaryConfig.ps1` must be rewritten as an ADCS enterprise subordinate CA. This CA issues certificates for domain members once the root CA signs its CSR.

**Files:**

- Rewrite: `dsc-configs/ca-secondary/caSecondaryConfig.ps1`

**Interfaces:**

- Consumes: `[PSCredential] $CAAdminCredential`, `[PSCredential] $DomainAdminCredential`
- Produces: DSC config named `CASecondaryConfig` that installs ADCS as enterprise subordinate CA

- [ ] **Step 1: Write caSecondaryConfig.ps1**

  ```powershell
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
  ```

  **Note:** The subordinate CA will be in "pending" state after initial deployment — the root CA must sign its CSR before it becomes operational. Plan for this manual/scripted handshake step in Wave 4.

- [ ] **Step 2: Commit**

  ```powershell
  git add dsc-configs/ca-secondary/caSecondaryConfig.ps1
  git commit -m "feat(dsc): implement CA secondary enterprise subordinate CA config"
  ```

---

## Verification

**Wave 1 Terraform is complete when:**

- `terraform apply` succeeded with 14 resources added, 0 errors
- `terraform output` shows all IDs populated
- `az network vnet show` confirms `vnet-hyperv-lab` exists in `rg-hlb-dev-net-001` with 4 subnets (snet-mgmt, snet-cluster, snet-vm-a, snet-vm-b)
- `az network nsg list --resource-group rg-hlb-dev-net-001` shows nsg-mgmt, nsg-cluster, nsg-vm-a, nsg-vm-b

**Pre-Wave-2 DSC work is complete when:**

- No `Get-Credential` calls remain in any DSC config file
- Each `publish.ps1` sources its own role's config file
- `caPrimaryConfig.ps1` defines a `StandaloneRootCA` config using `ADCSCertificationAuthority`
- `caSecondaryConfig.ps1` defines an `EnterpriseSubordinateCA` config using `ADCSCertificationAuthority`

**Wave 2 can begin when all of the above pass.**
