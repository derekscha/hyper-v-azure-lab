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
  description = "Resource group for Wave 4 cluster node resources"
  default     = "rg-hlb-dev-cluster-001"
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
  description = "Active Directory domain name"
  default     = "corp.lab"
}

variable "dc_private_ip" {
  type        = string
  description = "Static private IP of the DC — used for DNS and domain poll in init.ps1"
  default     = "10.50.1.10"
}

variable "cluster_node_config_id" {
  type        = string
  description = "Fixed GUID used as the DSC ConfigurationID for both cluster nodes. Generate once with [System.Guid]::NewGuid() and commit to tfvars. Must match the -ConfigurationId passed to publish.ps1."
}

variable "quorum_disk_size_gb" {
  type        = number
  description = "Size of the cluster quorum witness disk in GB"
  default     = 32
}

variable "csv_disk_size_gb" {
  type        = number
  description = "Size of each Cluster Shared Volume disk in GB (csv_a and csv_b are the same size)"
  default     = 512
}
