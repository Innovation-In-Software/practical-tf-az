# Lab 7 solution: environments/prod/prod.tfvars

environment              = "prod"
location                 = "eastus"
vnet_address_space       = ["10.20.0.0/16"]
vm_size                  = "Standard_B2s"
storage_name_suffix      = "<suffix>"
storage_replication_type = "ZRS"
