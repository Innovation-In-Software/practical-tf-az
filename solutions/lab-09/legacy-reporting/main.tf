# Lab 9 solution: environments/legacy-reporting/main.tf
#
# This is the FINAL state, after both pull requests:
#   PR 1: import only, matching reality exactly, 0 changes
#   PR 2: disable blob public access and adopt Summit's tag standard, 3 changes
#
# For the state after PR 1, set allow_nested_items_to_be_public back to true and restore
# the original tags:
#   resource group:   Owner = "dave.reporting", CostCentre = "FIN-2019", env = "Production"
#   storage account:  Owner = "dave.reporting", env = "Production"
#   virtual network:  Owner = "dave.reporting"

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
  tags = {
    environment = "prod"
    solution    = "reporting"
    owner       = "ops-team"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "legacy" {
  name     = "rg-legacy-reporting"
  location = "eastus"
  tags     = local.tags
}

resource "azurerm_storage_account" "reports" {
  name                     = "stsmtlegacy<suffix>"
  resource_group_name      = azurerm_resource_group.legacy.name
  location                 = azurerm_resource_group.legacy.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"
  access_tier              = "Cool"

  # Was true at import. Disabled in the second pull request.
  allow_nested_items_to_be_public = false

  tags = local.tags
}

resource "azurerm_storage_container" "reports" {
  name                  = "reports"
  storage_account_id    = azurerm_storage_account.reports.id
  container_access_type = "private"
}

resource "azurerm_virtual_network" "legacy" {
  name                = "legacy-reporting-vnet"
  resource_group_name = azurerm_resource_group.legacy.name
  location            = azurerm_resource_group.legacy.location
  address_space       = ["172.16.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.legacy.name
  virtual_network_name = azurerm_virtual_network.legacy.name
  address_prefixes     = ["172.16.10.0/24"]
}
