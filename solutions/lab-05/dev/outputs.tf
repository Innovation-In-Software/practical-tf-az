output "vm_public_ip" {
  description = "Public IP address of the Orders dev VM."
  value       = azurerm_public_ip.app.ip_address
}

output "vm_ssh_command" {
  description = "Copy and paste this to connect."
  value       = "ssh azureuser@${azurerm_public_ip.app.ip_address}"
}

output "storage_account_name" {
  description = "Name of the Orders dev storage account."
  value       = azurerm_storage_account.orders.name
}
