output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "cn1_vm_id" {
  value = azurerm_windows_virtual_machine.cn1.id
}

output "cn1_vm_name" {
  value = azurerm_windows_virtual_machine.cn1.name
}

output "cn1_mgmt_ip" {
  value       = azurerm_network_interface.cn1_nic_mgmt.private_ip_address
  description = "Management NIC IP for cn1 — use for Bastion RDP."
}

output "cn2_vm_id" {
  value = azurerm_windows_virtual_machine.cn2.id
}

output "cn2_vm_name" {
  value = azurerm_windows_virtual_machine.cn2.name
}

output "cn2_mgmt_ip" {
  value       = azurerm_network_interface.cn2_nic_mgmt.private_ip_address
  description = "Management NIC IP for cn2 — use for Bastion RDP."
}

output "cluster_node_config_id" {
  value       = var.cluster_node_config_id
  description = "DSC ConfigurationID for both cluster nodes. Pass to publish.ps1 -ConfigurationId."
}

output "quorum_disk_id" {
  value = azurerm_managed_disk.quorum.id
}

output "csv_a_disk_id" {
  value = azurerm_managed_disk.csv_a.id
}

output "csv_b_disk_id" {
  value = azurerm_managed_disk.csv_b.id
}
