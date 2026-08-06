# Lab 9 solution: environments/legacy-reporting/imports.tf
#
# Replace <sub-id> with the subscription id and <suffix> with the student
# suffix. Get the real IDs with:
#   az resource list --resource-group rg-legacy-reporting --query "[].id" -o tsv
#
# These blocks are safe to keep after the import. Terraform ignores an import
# block whose target is already in state. Delete them in a tidy-up commit once
# every environment has applied.

import {
  to = azurerm_resource_group.legacy
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting"
}

import {
  to = azurerm_storage_account.reports
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting/providers/Microsoft.Storage/storageAccounts/stsmtlegacy<suffix>"
}

import {
  to = azurerm_storage_container.reports
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting/providers/Microsoft.Storage/storageAccounts/stsmtlegacy<suffix>/blobServices/default/containers/reports"
}

import {
  to = azurerm_virtual_network.legacy
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting/providers/Microsoft.Network/virtualNetworks/legacy-reporting-vnet"
}

import {
  to = azurerm_subnet.default
  id = "/subscriptions/<sub-id>/resourceGroups/rg-legacy-reporting/providers/Microsoft.Network/virtualNetworks/legacy-reporting-vnet/subnets/default"
}
