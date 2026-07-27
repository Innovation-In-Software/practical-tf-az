variable "vm_admin_password" {
  description = "Admin password for the Orders dev VM. Supplied at run time, never stored in the repo."
  type        = string
  sensitive   = true
}

variable "allowed_ssh_source" {
  description = "The single public IP address allowed to reach the VM on port 22, in CIDR form."
  type        = string
}
