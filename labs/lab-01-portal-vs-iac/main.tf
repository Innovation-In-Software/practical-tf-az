# ---------------------------------------------------------------------------
# Lab 1: The SAME resource group and storage account you built in the portal,
# expressed as Terraform. You are only going to read this file and run
# `terraform plan`. Do NOT run `terraform apply` in this lab.
#
# As you read, keep the portal open next to VS Code and match each portal
# field to a line below.
# ---------------------------------------------------------------------------

terraform {
  # Import blocks, moved blocks, and config generation all need a recent CLI.
  # We standardize the class on Terraform 1.15.x.
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  # The v4 provider needs a feature block, even an empty one.
  features {}

  # v4 also requires an explicit subscription. The cleanest way is to export it
  # before you run Terraform, so it never lives in the file:
  #   export ARM_SUBSCRIPTION_ID="<your-subscription-id>"   (macOS / Linux)
  #   $env:ARM_SUBSCRIPTION_ID="<your-subscription-id>"     (PowerShell)
  #
  # If you prefer, you can uncomment and hard-code it for this lab only:
  # subscription_id = "00000000-0000-0000-0000-000000000000"
}

# Portal step: "Create a resource group" -> this block.
# Portal "Resource group name"  -> name
# Portal "Region"               -> location
# Portal "Tags" tab             -> tags
resource "azurerm_resource_group" "lab1" {
  name     = "rg-summit-lab1"
  location = "eastus"

  tags = {
    environment = "lab"
    solution    = "orders"
    owner       = "ops-team"
  }
}

# Portal step: "Create a storage account" -> this block.
# Portal "Storage account name"           -> name  (globally unique, 3-24 chars, lowercase + numbers only)
# Portal "Subscription / Resource group"  -> resource_group_name
# Portal "Region"                         -> location
# Portal "Performance = Standard"          -> account_tier
# Portal "Redundancy = Locally-redundant"  -> account_replication_type ("LRS")
resource "azurerm_storage_account" "lab1" {
  # CHANGE THIS if you ever apply it: the name must be globally unique across
  # all of Azure. Add your initials or a few random digits.
  name                     = "stsummitlab1xyz"
  resource_group_name      = azurerm_resource_group.lab1.name
  location                 = azurerm_resource_group.lab1.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Reuse the same tags as the resource group instead of retyping them.
  tags = azurerm_resource_group.lab1.tags
}
