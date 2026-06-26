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
