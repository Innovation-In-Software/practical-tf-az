# Lab 5 solution: environments/dev/backend.tf
# Replace <suffix> with the student suffix. Backend blocks cannot use variables.

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-summit-tfstate"
    storage_account_name = "stsummittfstate<suffix>"
    container_name       = "tfstate"
    key                  = "orders-dev.terraform.tfstate"
  }
}
