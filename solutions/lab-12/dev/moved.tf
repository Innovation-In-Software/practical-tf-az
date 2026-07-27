# Lab 12 solution: environments/dev/moved.tf
#
# Dev was written as inline resources before Summit's shared modules existed.
# These blocks re-point the existing resources at their new addresses inside
# the modules. Nothing is created and nothing is destroyed.
#
# Expected plan: 0 to add, 3 to change, 0 to destroy.
#   - module.storage.azurerm_storage_account.this   allow_nested_items_to_be_public true -> false
#   - module.app_vm.azurerm_network_interface.this  gains the role tag
#   - module.app_vm.azurerm_public_ip.this[0]       gains the role tag
#
# Safe to delete once every environment has applied this change.

moved {
  from = azurerm_virtual_network.orders
  to   = module.network.azurerm_virtual_network.this
}

moved {
  from = azurerm_subnet.app
  to   = module.network.azurerm_subnet.this["app"]
}

moved {
  from = azurerm_network_security_group.orders
  to   = module.network.azurerm_network_security_group.this
}

moved {
  from = azurerm_network_security_rule.ssh
  to   = module.network.azurerm_network_security_rule.inbound["AllowSSHFromAdmin"]
}

moved {
  from = azurerm_subnet_network_security_group_association.app
  to   = module.network.azurerm_subnet_network_security_group_association.this["app"]
}

# The linux-vm module uses count for the optional public IP, so the new
# address carries a list index, not a map key.
moved {
  from = azurerm_public_ip.app
  to   = module.app_vm.azurerm_public_ip.this[0]
}

moved {
  from = azurerm_network_interface.app
  to   = module.app_vm.azurerm_network_interface.this
}

moved {
  from = azurerm_linux_virtual_machine.app
  to   = module.app_vm.azurerm_linux_virtual_machine.this
}

moved {
  from = azurerm_storage_account.orders
  to   = module.storage.azurerm_storage_account.this
}

moved {
  from = azurerm_storage_container.this["orders-data"]
  to   = module.storage.azurerm_storage_container.this["orders-data"]
}

moved {
  from = azurerm_storage_container.this["orders-logs"]
  to   = module.storage.azurerm_storage_container.this["orders-logs"]
}
