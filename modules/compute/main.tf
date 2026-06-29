resource "azurerm_network_interface" "vm" {
  name                          = "${var.vm_name}-nic"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  accelerated_networking_enabled = var.enable_accelerated_networking
  tags                          = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = var.private_ip_address != "" ? "Static" : "Dynamic"
    private_ip_address            = var.private_ip_address != "" ? var.private_ip_address : null
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = var.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = var.tags

  network_interface_ids = [azurerm_network_interface.vm.id]
  patch_mode            = "AutomaticByPlatform"

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  lifecycle {
    ignore_changes = [admin_password]
  }
}

resource "azurerm_virtual_machine_extension" "cse" {
  count                      = var.custom_script_command != "" ? 1 : 0
  name                       = "CustomScriptExtension"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = jsonencode({
    commandToExecute = var.custom_script_command
  })
}
