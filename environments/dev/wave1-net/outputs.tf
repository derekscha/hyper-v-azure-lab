output "vnet_id" {
  value = module.network.vnet_id
}

output "vnet_name" {
  value = module.network.vnet_name
}

output "subnet_bastion_id" {
  value = module.network.subnet_bastion_id
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

output "nsg_bastion_id" {
  value = module.network.nsg_bastion_id
}

output "bastion_host_id" {
  value = module.network.bastion_host_id
}

output "bastion_public_ip" {
  value = module.network.bastion_public_ip
}

output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "location" {
  value = var.location
}
