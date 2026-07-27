# Lab 6 solution: environments/dev/dev.tfvars
# No secrets here. This file is committed.

environment         = "dev"
location            = "eastus"
vnet_address_space  = ["10.10.0.0/16"]
vm_size             = "Standard_B1s"
storage_name_suffix = "<suffix>"
