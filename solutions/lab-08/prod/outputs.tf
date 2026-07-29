# Lab 7 solution: environments/prod/outputs.tf
# A module's outputs are not automatically yours. Re-export what you need.

output "resource_group_name" {
  description = "Name of the production resource group."
  value       = azurerm_resource_group.orders.name
}

output "vm_ssh_command" {
  description = "Ready-to-paste SSH command for the production VM."
  value       = module.app_vm.ssh_command
}

output "vm_private_ip" {
  description = "Private IP of the production VM."
  value       = module.app_vm.private_ip_address
}

output "subnet_ids" {
  description = "Map of subnet short name to resource ID."
  value       = module.network.subnet_ids
}

output "storage_account_name" {
  description = "Name of the production storage account."
  value       = module.storage.storage_account_name
}
