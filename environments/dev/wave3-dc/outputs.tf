output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "dc_vm_id" {
  value = module.dc.vm_id
}

output "dc_vm_name" {
  value = module.dc.vm_name
}

output "dc_private_ip" {
  value       = module.dc.private_ip_address
  description = "Static IP of the DC — add to wave1-net VNet DNS servers after deployment."
}

output "domain_name" {
  value = var.domain_name
}

output "ca_vm_id" {
  value = module.ca.vm_id
}

output "ca_vm_name" {
  value = module.ca.vm_name
}

output "ca_private_ip" {
  value = module.ca.private_ip_address
}
