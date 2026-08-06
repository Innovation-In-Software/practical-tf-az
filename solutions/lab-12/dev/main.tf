# Lab 12 solution: environments/dev/main.tf
# Dev rebuilt on the shared modules, matching the shape of prod.
# See moved.tf for the blocks that make this a zero-destroy refactor.

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

locals {
  name_prefix = "${var.org}-${var.solution}-${var.environment}"

  tags = {
    environment = var.environment
    solution    = var.solution
    owner       = var.owner
    managed_by  = "terraform"
    cost_center = "retail-ops"
    ticket      = "INC-4471"
  }
}

data "azurerm_key_vault" "orders" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name
}

data "azurerm_key_vault_secret" "vm_admin_password" {
  name         = "vm-admin-password"
  key_vault_id = data.azurerm_key_vault.orders.id
}

# A one-line resource does not earn a module.
resource "azurerm_resource_group" "orders" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//network?ref=v1.1.0"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  address_space       = var.vnet_address_space

  subnets = {
    app = { address_prefix = cidrsubnet(var.vnet_address_space[0], 8, 1) }
  }

  inbound_rules = {
    AllowSSHFromAdmin = {
      priority               = 100
      protocol               = "Tcp"
      destination_port_range = "22"
      source_address_prefix  = var.allowed_ssh_source
    }
  }

  tags = local.tags
}

module "app_vm" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//linux-vm?ref=v1.1.0"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  subnet_id           = module.network.subnet_ids["app"]

  vm_size        = var.vm_size
  admin_username = var.vm_admin_username
  admin_password = data.azurerm_key_vault_secret.vm_admin_password.value

  tags = merge(local.tags, { role = "app-server" })
}

module "storage" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//storage?ref=v1.1.0"

  name_prefix         = local.name_prefix
  name_suffix         = var.storage_name_suffix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  containers          = var.storage_containers

  tags = local.tags
}
