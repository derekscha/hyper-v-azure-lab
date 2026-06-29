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
  description = "Resource group for Wave 3 domain controller resources"
  default     = "rg-hlb-dev-dc-001"
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
  description = "Name of the Wave 0 Key Vault containing lab secrets"
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

variable "domain_name" {
  type        = string
  description = "Active Directory domain name (e.g., corp.lab)"
  default     = "corp.lab"
}

variable "dc_private_ip" {
  type        = string
  description = "Static private IP for the DC on snet-mgmt (10.50.1.0/24). Added to VNet DNS after deployment."
  default     = "10.50.1.10"
}

variable "ca_common_name" {
  type        = string
  description = "Common name for the Enterprise Root CA certificate"
  default     = "Corp-Lab-Root-CA"
}
