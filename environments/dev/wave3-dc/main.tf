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

data "azurerm_key_vault_secret" "safemode_password" {
  name         = "safe-mode-admin-password"
  key_vault_id = data.azurerm_key_vault.lab.id
}

locals {
  init_script_b64    = base64encode(file("${path.root}/../../../vm-configs/domain-controller/init.ps1"))
  ca_init_script_b64 = base64encode(file("${path.root}/../../../vm-configs/ca/init.ps1"))

  cse_command = "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[IO.File]::WriteAllText('C:/init.ps1',[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${local.init_script_b64}')));& 'C:/init.ps1' -DomainName '${var.domain_name}' -AdminPassword '${data.azurerm_key_vault_secret.local_admin_password.value}' -SafeModePassword '${data.azurerm_key_vault_secret.safemode_password.value}'\""

  ca_cse_command = "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[IO.File]::WriteAllText('C:/init.ps1',[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${local.ca_init_script_b64}')));& 'C:/init.ps1' -DomainName '${var.domain_name}' -AdminUsername '${var.vm_admin_username}' -AdminPassword '${data.azurerm_key_vault_secret.local_admin_password.value}' -DcIpAddress '${var.dc_private_ip}' -CaCommonName '${var.ca_common_name}'\""
}

module "dc" {
  source = "../../../modules/compute"

  vm_name             = "vm-dc-dev-001"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  vm_size            = "Standard_D4s_v4"
  subnet_id          = data.terraform_remote_state.wave1_net.outputs.subnet_mgmt_id
  private_ip_address = var.dc_private_ip

  admin_username = var.vm_admin_username
  admin_password = data.azurerm_key_vault_secret.local_admin_password.value

  custom_script_command = local.cse_command
}

module "ca" {
  source = "../../../modules/compute"

  vm_name             = "vm-ca-dev-001"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  vm_size   = "Standard_D4s_v4"
  subnet_id = data.terraform_remote_state.wave1_net.outputs.subnet_mgmt_id

  admin_username = var.vm_admin_username
  admin_password = data.azurerm_key_vault_secret.local_admin_password.value

  custom_script_command = local.ca_cse_command
}
