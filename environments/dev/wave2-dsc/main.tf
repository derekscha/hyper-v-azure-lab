resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Cross-wave: pull Wave 1 networking outputs (subnet IDs, VNet ID)
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

# Wave 0 Key Vault — retrieve secrets for VM provisioning
data "azurerm_key_vault" "lab" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group
}

data "azurerm_key_vault_secret" "local_admin_password" {
  name         = "local-admin-password"
  key_vault_id = data.azurerm_key_vault.lab.id
}

# Build the CSE command: base64-encode init.ps1, write to disk on the VM, then execute.
# base64encode() produces UTF-8; WriteAllText with UTF8 encoding writes it correctly.
# Forward slashes used in the path to avoid HCL backslash escape complexity.
locals {
  init_script_b64 = base64encode(file("${path.root}/../../../vm-configs/dsc-pull-server/init.ps1"))
  cse_command     = "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[IO.File]::WriteAllText('C:/init.ps1',[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${local.init_script_b64}')));& 'C:/init.ps1'\""
}

module "dsc_pull_server" {
  source = "../../../modules/compute"

  vm_name             = "vm-dsc-dev-001"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  vm_size   = "Standard_D2s_v5"
  subnet_id = data.terraform_remote_state.wave1_net.outputs.subnet_mgmt_id

  admin_username = var.vm_admin_username
  admin_password = data.azurerm_key_vault_secret.local_admin_password.value

  custom_script_command = local.cse_command
}
