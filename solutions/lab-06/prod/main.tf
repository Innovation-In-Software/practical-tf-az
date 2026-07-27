# Lab 6 solution: environments/prod/main.tf

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
