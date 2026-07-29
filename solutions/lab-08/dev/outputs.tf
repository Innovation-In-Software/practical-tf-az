# Lab 6 solution: environments/dev/outputs.tf

output "resource_group_name" {
  description = "Name of the environment resource group."
  value       = azurerm_resource_group.orders.name
}

output "vm_public_ip" {
  description = "Public IP address of the application VM."
  value       = azurerm_public_ip.app.ip_address
}

output "vm_ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = "ssh ${var.vm_admin_username}@${azurerm_public_ip.app.ip_address}"
}

output "storage_account_name" {
  description = "Name of the environment storage account."
  value       = azurerm_storage_account.orders.name
}

output "container_names" {
  description = "Blob containers created in this environment."
  value       = [for name, cfg in var.storage_containers : name]
}

output "subnet_address_prefix" {
  description = "Address prefix computed for the app subnet."
  value       = one(azurerm_subnet.app.address_prefixes)
}
