# Lab 4 solution: the Lab 3 foundation plus NSG, Linux VM, and storage.
# Replace <suffix> with the student suffix before use.

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "orders" {
  name     = "rg-summit-orders-dev"
  location = "eastus"

  tags = {
    environment = "dev"
    solution    = "orders"
    owner       = "ops-team"
    managed_by  = "terraform"
  }
}

resource "azurerm_virtual_network" "orders" {
  name                = "vnet-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  address_space       = ["10.10.0.0/16"]

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.orders.name
  virtual_network_name = azurerm_virtual_network.orders.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_network_security_group" "orders" {
  name                = "nsg-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "AllowSSHFromAdmin"
  resource_group_name         = azurerm_resource_group.orders.name
  network_security_group_name = azurerm_network_security_group.orders.name

  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = var.allowed_ssh_source
  destination_address_prefix = "*"
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.orders.id
}

resource "azurerm_public_ip" "app" {
  name                = "pip-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_network_interface" "app" {
  name                = "nic-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app.id
  }

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_linux_virtual_machine" "app" {
  name                = "vm-summit-orders-dev"
  resource_group_name = azurerm_resource_group.orders.name
  location            = azurerm_resource_group.orders.location
  size                = "Standard_F1als_v7"

  admin_username                  = "azureuser"
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.app.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_storage_account" "orders" {
  name                     = "stsummitordersdev<suffix>"
  resource_group_name      = azurerm_resource_group.orders.name
  location                 = azurerm_resource_group.orders.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = azurerm_resource_group.orders.tags
}

resource "azurerm_storage_container" "data" {
  name                  = "orders-data"
  storage_account_id    = azurerm_storage_account.orders.id
  container_access_type = "private"
}
