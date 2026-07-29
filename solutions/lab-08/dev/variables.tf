# Lab 8 solution: environments/dev/variables.tf

variable "org" {
  description = "Short organization prefix used in resource names."
  type        = string
  default     = "summit"
}

variable "solution" {
  description = "The solution this environment belongs to."
  type        = string
  default     = "orders"
}

variable "environment" {
  description = "Environment name. Drives naming, tagging, and sizing decisions."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for every resource in this environment."
  type        = string
  default     = "eastus"

  validation {
    condition     = contains(["eastus", "eastus2", "centralus"], var.location)
    error_message = "Summit only deploys to eastus, eastus2, or centralus."
  }
}

variable "owner" {
  description = "Team responsible for this environment. Goes on every tag."
  type        = string
  default     = "ops-team"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = list(string)
}

variable "vm_size" {
  description = "Azure VM size for the application server."
  type        = string
  default     = "Standard_F1als_v7"
}

variable "vm_admin_username" {
  description = "Admin user created on the VM."
  type        = string
  default     = "azureuser"
}

variable "allowed_ssh_source" {
  description = "The one public IP allowed to reach the VM on port 22, in CIDR form."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_source, 0))
    error_message = "allowed_ssh_source must be valid CIDR notation, for example 203.0.113.7/32."
  }
}

variable "storage_name_suffix" {
  description = "Student suffix. Storage account names are globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.storage_name_suffix))
    error_message = "storage_name_suffix must be 2 to 6 lowercase letters or digits."
  }
}

variable "storage_containers" {
  description = "Blob containers to create in the environment storage account, keyed by name."
  type = map(object({
    access_type = string
  }))

  default = {
    "orders-data" = { access_type = "private" }
    "orders-logs" = { access_type = "private" }
  }
}

variable "key_vault_name" {
  description = "Name of the Key Vault holding this environment's secrets."
  type        = string
}

variable "key_vault_resource_group_name" {
  description = "Resource group containing the Key Vault. Owned by the security team."
  type        = string
  default     = "rg-summit-security"
}
