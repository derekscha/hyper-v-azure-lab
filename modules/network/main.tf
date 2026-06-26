resource "azurerm_virtual_network" "lab" {
  name                = "vnet-hyperv-lab"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.subnet_mgmt_cidr]
}

resource "azurerm_subnet" "cluster" {
  name                 = "snet-cluster"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.subnet_cluster_cidr]
}

resource "azurerm_subnet" "vm_a" {
  name                 = "snet-vm-a"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.subnet_vm_a_cidr]
}

resource "azurerm_subnet" "vm_b" {
  name                 = "snet-vm-b"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.subnet_vm_b_cidr]
}

# NSG: Management subnet — allow RDP and WinRM from admin IP only
resource "azurerm_network_security_group" "mgmt" {
  name                = "nsg-mgmt"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-RDP-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-WinRM-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985-5986"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-DSC-Pull-Inbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

# NSG: Cluster subnet — allow all intra-subnet traffic (heartbeat, CSV, shared disk)
resource "azurerm_network_security_group" "cluster" {
  name                = "nsg-cluster"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-ClusterIntranet-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.subnet_cluster_cidr
    destination_address_prefix = var.subnet_cluster_cidr
  }
}

# NSG: VM subnets — permissive for now, tighten per nested VM workload later
resource "azurerm_network_security_group" "vm_a" {
  name                = "nsg-vm-a"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "vm_b" {
  name                = "nsg-vm-b"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

resource "azurerm_subnet_network_security_group_association" "cluster" {
  subnet_id                 = azurerm_subnet.cluster.id
  network_security_group_id = azurerm_network_security_group.cluster.id
}

resource "azurerm_subnet_network_security_group_association" "vm_a" {
  subnet_id                 = azurerm_subnet.vm_a.id
  network_security_group_id = azurerm_network_security_group.vm_a.id
}

resource "azurerm_subnet_network_security_group_association" "vm_b" {
  subnet_id                 = azurerm_subnet.vm_b.id
  network_security_group_id = azurerm_network_security_group.vm_b.id
}
