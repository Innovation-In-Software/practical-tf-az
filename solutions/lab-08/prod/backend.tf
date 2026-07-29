# Lab 5 solution: environments/prod/backend.tf
# Only the key differs from dev. Separate key, separate state, separate blast radius.

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-summit-tfstate"
    storage_account_name = "stsummittfstate<suffix>"
    container_name       = "tfstate"
    key                  = "orders-prod.terraform.tfstate"
  }
}
