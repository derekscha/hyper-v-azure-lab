output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "dsc_pull_server_vm_id" {
  value = module.dsc_pull_server.vm_id
}

output "dsc_pull_server_vm_name" {
  value = module.dsc_pull_server.vm_name
}

output "dsc_pull_server_private_ip" {
  value = module.dsc_pull_server.private_ip_address
}

output "dsc_pull_server_nic_id" {
  value = module.dsc_pull_server.nic_id
}
