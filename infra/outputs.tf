output "public_ip" {
  description = "Public IP address of the VM (populated after apply; empty during plan)."
  value       = azurerm_public_ip.public_ip.ip_address
}

output "virtual_machine_name" {
  description = "Name of the created Linux VM."
  value       = azurerm_linux_virtual_machine.virtual_machine.name
}

output "resource_group" {
  description = "Resource group containing all provisioned resources."
  value       = azurerm_resource_group.resource_group.name
}

output "ssh_command" {
  description = "SSH command to connect to the VM (public IP may be empty until apply completes)."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.public_ip.ip_address}"
}
