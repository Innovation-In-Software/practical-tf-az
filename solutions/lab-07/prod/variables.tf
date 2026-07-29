# Lab 7 solution: environments/prod/variables.tf

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
  description = "Environment name."
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
}

variable "owner" {
  description = "Team responsible for this environment."
  type        = string
  default     = "ops-team"
}

variable "vnet_address_space" {
  description = "Address space for the production virtual network."
  type        = list(string)
}

variable "vm_size" {
  description = "Azure VM size for the production application server."
  type        = string
  default     = "Standard_D2als_v7"
}

variable "vm_admin_password" {
  description = "Admin password for the production VM. Supplied at run time."
  type        = string
  sensitive   = true
}

variable "allowed_ssh_source" {
  description = "The one public IP allowed to reach the VM on port 22, in CIDR form."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_source, 0))
    error_message = "allowed_ssh_source must be valid CIDR notation."
  }
}

variable "storage_name_suffix" {
  description = "Your 4-character student suffix, for global storage account uniqueness."
  type        = string
}

variable "storage_replication_type" {
  description = "Redundancy for the production storage account. Requires storage module v1.1.0 or later."
  type        = string
  default     = "LRS"
}
