# Lab 11 Part 1 solution: the sandbox configuration with all four faults fixed.
#
# What changed from broken/main.tf:
#   1. HCL syntax       name "rg-summit-sandbox"      -> name = "rg-summit-sandbox"
#   2. Terraform        azurerm_resource_group.sandbox -> azurerm_resource_group.sbx  (three places)
#   3. Provider schema  enable_https_traffic_only     -> https_traffic_only_enabled   (renamed in azurerm v4)
#   4. Azure API        rg-summit-shared-services      -> rg-summit-tfstate            (the first does not exist)
#
# Plan only. Never applied.

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

variable "location" {
  description = "Azure region for the sandbox."
  type        = string
  default     = "eastus"
}

variable "name_suffix" {
  description = "Your student suffix, for global storage account uniqueness."
  type        = string
}

data "azurerm_resource_group" "shared" {
  name = "rg-summit-tfstate"
}

resource "azurerm_resource_group" "sbx" {
  name     = "rg-summit-sandbox"
  location = var.location

  tags = {
    environment = "sandbox"
    solution    = "orders"
    owner       = "ops-team"
    managed_by  = "terraform"
  }
}

resource "azurerm_storage_account" "sbx" {
  name                     = "stsummitsbx${var.name_suffix}"
  resource_group_name      = azurerm_resource_group.sbx.name
  location                 = azurerm_resource_group.sbx.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  https_traffic_only_enabled = true

  tags = azurerm_resource_group.sbx.tags
}

output "shared_resource_group_location" {
  description = "Where the shared tooling lives."
  value       = data.azurerm_resource_group.shared.location
}
