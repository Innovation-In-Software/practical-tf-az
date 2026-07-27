# ---------------------------------------------------------------------------
# Lab 11, Part 1: a configuration a colleague left behind.
#
# It contains FOUR faults, one from each layer of the stack:
#
#   1. HCL syntax        Terraform cannot parse the file
#   2. Terraform         the file parses, but a reference points at nothing
#   3. Provider schema   an argument that does not exist in azurerm v4
#   4. Azure API         everything is valid, but Azure says no
#
# Fix them one at a time, in that order, running `terraform validate` and then
# `terraform plan` after each fix. Do NOT try to spot all four by reading.
# The point of the exercise is to let the tool tell you.
#
# You will never apply this. Plan only.
# ---------------------------------------------------------------------------

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

# The team keeps shared tooling in its own resource group. We only read it.
data "azurerm_resource_group" "shared" {
  name = "rg-summit-shared-services"
}

resource "azurerm_resource_group" "sbx" {
  name "rg-summit-sandbox"
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
  resource_group_name      = azurerm_resource_group.sandbox.name
  location                 = azurerm_resource_group.sandbox.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  enable_https_traffic_only = true

  tags = azurerm_resource_group.sandbox.tags
}

output "shared_resource_group_location" {
  description = "Where the shared tooling lives."
  value       = data.azurerm_resource_group.shared.location
}
