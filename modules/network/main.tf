resource "azurerm_virtual_network" "lab" {
  name                = "vnet-hyperv-lab"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

# AzureBastionSubnet — name must be exactly this (Azure requirement), minimum /26
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.subnet_bastion_cidr]
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

# NSG: Bastion subnet — Azure-required rules + restrict HTTPS access to admin IP only
resource "azurerm_network_security_group" "bastion" {
  name                = "nsg-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Inbound: HTTPS access locked to admin IP (no open Internet access)
  security_rule {
    name                       = "Allow-HTTPS-From-Admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  # Inbound: Required — Azure Bastion control plane
  security_rule {
    name                       = "Allow-GatewayManager-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  # Inbound: Required — Azure load balancer health probes
  security_rule {
    name                       = "Allow-AzureLoadBalancer-Inbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Inbound: Required — Bastion host internal communication
  security_rule {
    name                       = "Allow-BastionHostComm-Inbound"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Outbound: RDP/SSH to VMs in the VNet
  security_rule {
    name                       = "Allow-RDP-SSH-To-VNet"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["3389", "22"]
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  # Outbound: Required — Bastion control plane
  security_rule {
    name                       = "Allow-AzureCloud-Outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  # Outbound: Required — Bastion host internal communication
  security_rule {
    name                       = "Allow-BastionHostComm-Outbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Outbound: Required — session information service
  security_rule {
    name                       = "Allow-GetSessionInfo-Outbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# NSG: Management subnet — RDP only from Bastion, WinRM/DSC from VNet only
resource "azurerm_network_security_group" "mgmt" {
  name                = "nsg-mgmt"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-RDP-From-Bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.subnet_bastion_cidr
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
    source_address_prefix      = "VirtualNetwork"
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

resource "azurerm_subnet_network_security_group_association" "bastion" {
  subnet_id                 = azurerm_subnet.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
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

# Bastion public IP and host — toggled by var.deploy_bastion to control billing
# Subnet and NSG remain always-on to avoid redeployment delay when re-enabling
resource "azurerm_public_ip" "bastion" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "pip-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "lab" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "bas-hyperv-lab"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic"
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "lab" {
  name                    = "ngw-hyperv-lab"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "lab" {
  nat_gateway_id       = azurerm_nat_gateway.lab.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate NAT GW to all VM-hosting subnets. AzureBastionSubnet is excluded —
# NAT GW + Bastion subnet is unsupported by Azure.
resource "azurerm_subnet_nat_gateway_association" "mgmt" {
  subnet_id      = azurerm_subnet.mgmt.id
  nat_gateway_id = azurerm_nat_gateway.lab.id
}

resource "azurerm_subnet_nat_gateway_association" "vm_a" {
  subnet_id      = azurerm_subnet.vm_a.id
  nat_gateway_id = azurerm_nat_gateway.lab.id
}

resource "azurerm_subnet_nat_gateway_association" "vm_b" {
  subnet_id      = azurerm_subnet.vm_b.id
  nat_gateway_id = azurerm_nat_gateway.lab.id
}
