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

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed inbound for RDP (3389) and WinRM (5985-5986) on snet-mgmt"
}
