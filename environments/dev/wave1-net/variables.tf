variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "location" {
  type        = string
  description = "Azure region for all resources"
  default     = "southcentralus"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for Wave 1 networking resources"
  default     = "rg-hlb-dev-net-001"
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default = {
    Project     = "hyper-v-azure-lab"
    Environment = "development"
    ManagedBy   = "Terraform"
    workload    = "hyper-v-azure-lab"
  }
}

variable "admin_cidr" {
  type        = string
  description = "Your public IP CIDR allowed for HTTPS (443) access to Azure Bastion (e.g., 1.2.3.4/32)"
}

variable "subnet_bastion_cidr" {
  type        = string
  description = "CIDR for AzureBastionSubnet (minimum /26)"
  default     = "10.50.0.0/26"
}

variable "deploy_bastion" {
  type        = bool
  description = "Deploy Bastion host and public IP. Set false to destroy and stop billing."
  default     = false
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.50.0.0/16"]
}

variable "subnet_mgmt_cidr" {
  type    = string
  default = "10.50.1.0/24"
}

variable "subnet_cluster_cidr" {
  type    = string
  default = "10.50.2.0/24"
}

variable "subnet_vm_a_cidr" {
  type        = string
  description = "VM traffic subnet A (cluster node NIC 2 / VLAN set A)"
  default     = "10.50.3.0/24"
}

variable "subnet_vm_b_cidr" {
  type        = string
  description = "VM traffic subnet B (cluster node NIC 3 / VLAN set B)"
  default     = "10.50.4.0/24"
}