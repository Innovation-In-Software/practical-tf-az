# Lab 6 solution: environments/prod/variables.tf
# Prod is still just a resource group at this point. Lab 7 adds the rest.

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
