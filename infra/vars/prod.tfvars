location             = "westeurope"
resource_group_name  = "resource-group-terraform-azure-vm-prod"
virtual_machine_size = "Standard_B1s"
admin_username       = "azureuser"
auto_shutdown_time   = "2300"
auto_shutdown_timezone = "Israel Standard Time"

tags = {
  project     = "terraform-azure-vm"
  environment = "prod"
  owner       = "devops-assignment"
  managed_by  = "terraform"
}
