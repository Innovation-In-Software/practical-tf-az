# Lab 7 solution: environments/prod/main.tf
# Production built entirely from Summit's shared modules.
# Storage is pinned to v1.1.0 after the upgrade exercise in Part 7.

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
  }
}

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
    app  = { address_prefix = cidrsubnet(var.vnet_address_space[0], 8, 1) }
    data = { address_prefix = cidrsubnet(var.vnet_address_space[0], 8, 2) }
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
  admin_password = var.vm_admin_password

  tags = merge(local.tags, { role = "app-server" })
}

module "storage" {
  source = "git::https://github.com/Innovation-In-Software/az-tf-ops-modules.git//storage?ref=v1.1.0"

  name_prefix         = local.name_prefix
  name_suffix         = var.storage_name_suffix
  resource_group_name = azurerm_resource_group.orders.name
  location            = var.location
  replication_type    = var.storage_replication_type

  containers = {
    "orders-data" = { access_type = "private" }
    "orders-logs" = { access_type = "private" }
  }

  tags = local.tags
}
