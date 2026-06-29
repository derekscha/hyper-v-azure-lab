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

variable "subnet_bastion_cidr" {
  type        = string
  description = "CIDR for AzureBastionSubnet (Azure requires exactly this name, minimum /26)"
}

variable "deploy_bastion" {
  type        = bool
  description = "Deploy Bastion host and public IP. Set false to destroy and stop billing; subnet and NSG remain."
  default     = false
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed HTTPS (443) inbound to Azure Bastion — no direct VM access"
}

variable "dns_servers" {
  type        = list(string)
  default     = []
  description = "Custom DNS servers for the VNet. Empty list uses Azure-provided DNS."
}
