# Lab 6 solution: environments/dev/moved.tf
#
# for_each changed the container's address from azurerm_storage_container.orders_data
# to azurerm_storage_container.this["orders-data"]. Without this block Terraform
# would destroy the old address and create the new one. Safe to delete once every
# environment has applied it.

moved {
  from = azurerm_storage_container.orders_data
  to   = azurerm_storage_container.this["orders-data"]
}
