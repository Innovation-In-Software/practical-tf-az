# Lab 12 solution: environments/dev/outputs.tf
# Every value now comes from a module output.

output "resource_group_name" {
  description = "Name of the environment resource group."
  value       = azurerm_resource_group.orders.name
}

output "vm_public_ip" {
  description = "Public IP address of the application VM."
  value       = module.app_vm.public_ip_address
}

output "vm_ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = module.app_vm.ssh_command
}

output "storage_account_name" {
  description = "Name of the environment storage account."
  value       = module.storage.storage_account_name
}

output "container_names" {
  description = "Blob containers created in this environment."
  value       = module.storage.container_names
}

output "subnet_ids" {
  description = "Map of subnet short name to resource ID."
  value       = module.network.subnet_ids
}
