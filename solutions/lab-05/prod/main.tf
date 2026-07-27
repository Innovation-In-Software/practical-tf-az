# Lab 5 solution: environments/prod/main.tf
# Prod is scaffolding at this point. Lab 7 fills it in from shared modules.

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
  name     = "rg-summit-orders-prod"
  location = "eastus"

  tags = {
    environment = "prod"
    solution    = "orders"
    owner       = "ops-team"
    managed_by  = "terraform"
  }
}
