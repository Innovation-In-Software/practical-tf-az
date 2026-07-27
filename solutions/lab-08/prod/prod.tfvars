# Lab 8 solution: environments/prod/prod.tfvars

environment                   = "prod"
location                      = "eastus"
vnet_address_space            = ["10.20.0.0/16"]
vm_size                       = "Standard_B2s"
storage_name_suffix           = "<suffix>"
storage_replication_type      = "ZRS"
key_vault_name                = "kv-summit-prod-<suffix>"
key_vault_resource_group_name = "rg-summit-security"
