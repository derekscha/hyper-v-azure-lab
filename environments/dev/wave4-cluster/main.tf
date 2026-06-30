resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "terraform_remote_state" "wave1_net" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-hlb-dev-001"
    storage_account_name = "sthlbdev001"
    container_name       = "terraform-state"
    key                  = "dev/wave1-net/terraform.tfstate"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "wave2_dsc" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-hlb-dev-001"
    storage_account_name = "sthlbdev001"
    container_name       = "terraform-state"
    key                  = "dev/wave2-dsc/terraform.tfstate"
    use_azuread_auth     = true
  }
}

data "azurerm_key_vault" "lab" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group
}

data "azurerm_key_vault_secret" "local_admin_password" {
  name         = "local-admin-password"
  key_vault_id = data.azurerm_key_vault.lab.id
}

resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = "sthlbdev001"
  container_access_type = "private"
}

# Upload init.ps1 to blob so CSE can download it — avoids the Windows command-line
# length limit that occurs when base64-encoding the script inline in commandToExecute.
resource "azurerm_storage_blob" "cluster_init" {
  name                   = "cluster-node-init.ps1"
  storage_account_name   = "sthlbdev001"
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.root}/../../../vm-configs/cluster-node/init.ps1"
}

# User-assigned managed identity — assigned to both cluster nodes so CSE can authenticate
# to the scripts blob container without a storage account key (key-based auth is disabled).
resource "azurerm_user_assigned_identity" "cluster_scripts" {
  name                = "id-hlb-cluster-scripts"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cluster_scripts_reader" {
  scope                = azurerm_storage_container.scripts.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.cluster_scripts.principal_id
}

locals {
  # commandToExecute only carries parameters; the script body is downloaded via fileUris.
  cse_command = "powershell.exe -NonInteractive -ExecutionPolicy Bypass -File cluster-node-init.ps1 -DomainName '${var.domain_name}' -AdminUsername '${var.vm_admin_username}' -AdminPassword '${data.azurerm_key_vault_secret.local_admin_password.value}' -DcIpAddress '${var.dc_private_ip}' -DscPullServerIp '${data.terraform_remote_state.wave2_dsc.outputs.dsc_pull_server_private_ip}' -ClusterNodeConfigId '${var.cluster_node_config_id}'"
}

# ── Shared Disks ──────────────────────────────────────────────────────────────

resource "azurerm_managed_disk" "quorum" {
  name                 = "disk-hlb-cluster-quorum"
  location             = var.location
  resource_group_name  = azurerm_resource_group.lab.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.quorum_disk_size_gb
  max_shares           = 2
  tags                 = var.tags
}

resource "azurerm_managed_disk" "csv_a" {
  name                 = "disk-hlb-cluster-csv-a"
  location             = var.location
  resource_group_name  = azurerm_resource_group.lab.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.csv_disk_size_gb
  max_shares           = 2
  tags                 = var.tags
}

resource "azurerm_managed_disk" "csv_b" {
  name                 = "disk-hlb-cluster-csv-b"
  location             = var.location
  resource_group_name  = azurerm_resource_group.lab.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.csv_disk_size_gb
  max_shares           = 2
  tags                 = var.tags
}

# ── Node 1 NICs ───────────────────────────────────────────────────────────────

resource "azurerm_network_interface" "cn1_nic_mgmt" {
  name                           = "vm-cn-dev-001-nic-mgmt"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.lab.name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.wave1_net.outputs.subnet_mgmt_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.1.20"
  }
}

resource "azurerm_network_interface" "cn1_nic_cluster" {
  name                           = "vm-cn-dev-001-nic-cluster"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.lab.name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.wave1_net.outputs.subnet_cluster_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.2.10"
  }
}

resource "azurerm_network_interface" "cn1_nic_vma" {
  name                           = "vm-cn-dev-001-nic-vma"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.lab.name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.wave1_net.outputs.subnet_vm_a_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.3.10"
  }
}

resource "azurerm_network_interface" "cn1_nic_vmb" {
  name                           = "vm-cn-dev-001-nic-vmb"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.lab.name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.wave1_net.outputs.subnet_vm_b_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.4.10"
  }
}

# ── Node 2 NICs ───────────────────────────────────────────────────────────────

resource "azurerm_network_interface" "cn2_nic_mgmt" {
  name                           = "vm-cn-dev-002-nic-mgmt"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.lab.name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.wave1_net.outputs.subnet_mgmt_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.1.21"
  }
}

resource "azurerm_network_interface" "cn2_nic_cluster" {
  name                           = "vm-cn-dev-002-nic-cluster"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.lab.name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.wave1_net.outputs.subnet_cluster_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.2.11"
  }
}

resource "azurerm_network_interface" "cn2_nic_vma" {
  name                           = "vm-cn-dev-002-nic-vma"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.lab.name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.wave1_net.outputs.subnet_vm_a_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.3.11"
  }
}

resource "azurerm_network_interface" "cn2_nic_vmb" {
  name                           = "vm-cn-dev-002-nic-vmb"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.lab.name
  accelerated_networking_enabled = true
  tags                           = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.terraform_remote_state.wave1_net.outputs.subnet_vm_b_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.50.4.11"
  }
}

# ── VMs ───────────────────────────────────────────────────────────────────────

resource "azurerm_windows_virtual_machine" "cn1" {
  name                = "vm-cn-dev-001"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  size                = "Standard_D8s_v5"
  admin_username      = var.vm_admin_username
  admin_password      = data.azurerm_key_vault_secret.local_admin_password.value
  tags                = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster_scripts.id]
  }

  network_interface_ids = [
    azurerm_network_interface.cn1_nic_mgmt.id,
    azurerm_network_interface.cn1_nic_cluster.id,
    azurerm_network_interface.cn1_nic_vma.id,
    azurerm_network_interface.cn1_nic_vmb.id,
  ]

  patch_mode = "AutomaticByPlatform"

  os_disk {
    name                 = "vm-cn-dev-001-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "latest"
  }

  lifecycle {
    ignore_changes = [admin_password]
  }
}

resource "azurerm_windows_virtual_machine" "cn2" {
  name                = "vm-cn-dev-002"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  size                = "Standard_D8s_v5"
  admin_username      = var.vm_admin_username
  admin_password      = data.azurerm_key_vault_secret.local_admin_password.value
  tags                = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster_scripts.id]
  }

  network_interface_ids = [
    azurerm_network_interface.cn2_nic_mgmt.id,
    azurerm_network_interface.cn2_nic_cluster.id,
    azurerm_network_interface.cn2_nic_vma.id,
    azurerm_network_interface.cn2_nic_vmb.id,
  ]

  patch_mode = "AutomaticByPlatform"

  os_disk {
    name                 = "vm-cn-dev-002-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "latest"
  }

  lifecycle {
    ignore_changes = [admin_password]
  }
}

# ── CSE Extensions ────────────────────────────────────────────────────────────

resource "azurerm_virtual_machine_extension" "cn1_cse" {
  name                       = "CustomScriptExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.cn1.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = jsonencode({
    fileUris         = [azurerm_storage_blob.cluster_init.url]
    commandToExecute = local.cse_command
  })

  protected_settings = jsonencode({
    managedIdentity = {
      clientId = azurerm_user_assigned_identity.cluster_scripts.client_id
    }
  })
}

resource "azurerm_virtual_machine_extension" "cn2_cse" {
  name                       = "CustomScriptExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.cn2.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = jsonencode({
    fileUris         = [azurerm_storage_blob.cluster_init.url]
    commandToExecute = local.cse_command
  })

  protected_settings = jsonencode({
    managedIdentity = {
      clientId = azurerm_user_assigned_identity.cluster_scripts.client_id
    }
  })
}

# ── Shared Disk Attachments ───────────────────────────────────────────────────
# Shared disks require caching = "None". Both nodes attach each disk at the
# same LUN so Windows presents a consistent disk numbering after cluster formation.

resource "azurerm_virtual_machine_data_disk_attachment" "cn1_quorum" {
  managed_disk_id    = azurerm_managed_disk.quorum.id
  virtual_machine_id = azurerm_windows_virtual_machine.cn1.id
  lun                = 0
  caching            = "None"
}

resource "azurerm_virtual_machine_data_disk_attachment" "cn1_csv_a" {
  managed_disk_id    = azurerm_managed_disk.csv_a.id
  virtual_machine_id = azurerm_windows_virtual_machine.cn1.id
  lun                = 1
  caching            = "None"
}

resource "azurerm_virtual_machine_data_disk_attachment" "cn1_csv_b" {
  managed_disk_id    = azurerm_managed_disk.csv_b.id
  virtual_machine_id = azurerm_windows_virtual_machine.cn1.id
  lun                = 2
  caching            = "None"
}

resource "azurerm_virtual_machine_data_disk_attachment" "cn2_quorum" {
  managed_disk_id    = azurerm_managed_disk.quorum.id
  virtual_machine_id = azurerm_windows_virtual_machine.cn2.id
  lun                = 0
  caching            = "None"
}

resource "azurerm_virtual_machine_data_disk_attachment" "cn2_csv_a" {
  managed_disk_id    = azurerm_managed_disk.csv_a.id
  virtual_machine_id = azurerm_windows_virtual_machine.cn2.id
  lun                = 1
  caching            = "None"
}

resource "azurerm_virtual_machine_data_disk_attachment" "cn2_csv_b" {
  managed_disk_id    = azurerm_managed_disk.csv_b.id
  virtual_machine_id = azurerm_windows_virtual_machine.cn2.id
  lun                = 2
  caching            = "None"
}
