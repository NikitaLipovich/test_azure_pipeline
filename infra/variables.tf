variable "location" {
  type        = string
  description = "Azure region where resources will be deployed."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the Azure Resource Group."
}

variable "virtual_machine_size" {
  type        = string
  description = "Azure VM size. Standard_B1s for free-tier. Fallback: Standard_B1ls, Standard_B1ms."
}

variable "admin_username" {
  type        = string
  description = "Admin username for the Linux VM."
}

# Never store this in tfvars — passed via TF_VAR_ssh_public_key environment variable.
variable "ssh_public_key" {
  type        = string
  description = "SSH public key content (e.g. ssh-ed25519 AAAA...)."
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
}

variable "auto_shutdown_time" {
  type        = string
  description = "Daily auto-shutdown time in HHmm format (e.g. 2200 = 22:00)."
}

variable "auto_shutdown_timezone" {
  type        = string
  description = "Timezone for the auto-shutdown schedule (Windows timezone name)."
}
