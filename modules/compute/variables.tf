variable "vm_name" {
  type        = string
  description = "Name of the virtual machine"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the VM and NIC"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "vm_size" {
  type        = string
  description = "VM SKU (e.g., Standard_D2s_v5)"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the primary NIC"
}

variable "admin_username" {
  type        = string
  description = "Local administrator username"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Local administrator password (retrieved from Key Vault)"
}

variable "os_disk_size_gb" {
  type        = number
  default     = 128
  description = "OS disk size in GB"
}

variable "os_disk_storage_type" {
  type        = string
  default     = "Premium_LRS"
  description = "OS disk storage account type"
}

variable "image_publisher" {
  type    = string
  default = "MicrosoftWindowsServer"
}

variable "image_offer" {
  type    = string
  default = "WindowsServer"
}

variable "image_sku" {
  type        = string
  default     = "2025-datacenter-azure-edition"
  description = "Windows Server 2025 Azure Edition — supports hot-patching and Azure-specific optimizations"
}

variable "image_version" {
  type    = string
  default = "latest"
}

variable "enable_accelerated_networking" {
  type    = bool
  default = true
}

variable "custom_script_command" {
  type        = string
  default     = ""
  description = "Full commandToExecute string for the Custom Script Extension. Empty string disables CSE."
}

variable "private_ip_address" {
  type        = string
  default     = ""
  description = "Static private IP to assign to the NIC. Empty string uses Dynamic allocation (default)."
}
