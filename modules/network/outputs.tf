output "vnet_id" {
  value = azurerm_virtual_network.lab.id
}

output "vnet_name" {
  value = azurerm_virtual_network.lab.name
}

output "subnet_bastion_id" {
  value = azurerm_subnet.bastion.id
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

output "nsg_bastion_id" {
  value = azurerm_network_security_group.bastion.id
}

output "bastion_host_id" {
  value = length(azurerm_bastion_host.lab) > 0 ? azurerm_bastion_host.lab[0].id : null
}

output "bastion_public_ip" {
  value = length(azurerm_public_ip.bastion) > 0 ? azurerm_public_ip.bastion[0].ip_address : null
}
