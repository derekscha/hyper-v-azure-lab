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
  description = "Resource group for Wave 2 DSC pull server resources"
  default     = "rg-hlb-dev-dsc-001"
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

variable "key_vault_name" {
  type        = string
  description = "Name of the Wave 0 Key Vault containing lab secrets (e.g., kv-hlb-dev-001)"
}

variable "key_vault_resource_group" {
  type        = string
  description = "Resource group containing the Wave 0 Key Vault"
  default     = "rg-hlb-dev-001"
}

variable "vm_admin_username" {
  type        = string
  description = "Local administrator username for VMs in this wave"
  default     = "labadmin"
}
