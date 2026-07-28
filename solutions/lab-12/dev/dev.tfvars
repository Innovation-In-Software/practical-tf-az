# Lab 12 solution: environments/dev/dev.tfvars
# A vault NAME is an address, not a secret. Committing it is fine.

environment                   = "dev"
location                      = "eastus"
vnet_address_space            = ["10.10.0.0/16"]
vm_size                       = "Standard_F1als_v7"
storage_name_suffix           = "<suffix>"
key_vault_name                = "kv-summit-dev-<suffix>"
key_vault_resource_group_name = "rg-summit-security"
