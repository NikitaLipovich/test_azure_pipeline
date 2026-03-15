# Terraform Infrastructure — File-by-File Breakdown

This documentation explains what each `.tf` file in the `infra/` folder does, how they relate to each other, and what resources are created in Azure.

---

## What Gets Created

```
Azure Resource Group
└── Virtual Network (10.10.0.0/16)
    └── Subnet (10.10.1.0/24)
         └── Network Interface (NIC)
              ├── Dynamic Private IP
              ├── Static Public IP (Standard SKU)
              └── Network Security Group (NSG)
                   └── Rule: Allow SSH (port 22)
└── Linux VM (Ubuntu 22.04 LTS)
     └── Auto-shutdown schedule (daily on a schedule)
```

---

## File Structure

```
infra/
├── providers.tf      # Terraform version and Azure provider
├── variables.tf      # Declaration of all input variables
├── main.tf           # Resource Group
├── network.tf        # Networking: VNet, Subnet, Public IP, NIC
├── security.tf       # Firewall: NSG + rules
├── compute.tf        # VM + auto-shutdown schedule
├── outputs.tf        # What to output after apply
└── vars/
    ├── dev.tfvars    # Variable values for dev
    └── prod.tfvars   # Variable values for prod
```

---

## providers.tf — Azure Provider

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

**What it does:**
- Pins the minimum Terraform version (>= 1.6.0) — protects against incompatibilities.
- Connects the `azurerm` provider at version ~4.0 (minor version updates allowed, major upgrade is not).
- `features {}` — a mandatory block for azurerm; without it the provider won't initialize.

**Analogy:** this is like an `import` in code — without it Terraform doesn't know which cloud to work with.

---

## variables.tf — Input Parameters

```hcl
variable "location" { ... }
variable "resource_group_name" { ... }
variable "virtual_machine_size" { ... }
variable "admin_username" { ... }
variable "ssh_public_key" { sensitive = true }
variable "tags" { type = map(string) }
variable "auto_shutdown_time" { ... }
variable "auto_shutdown_timezone" { ... }
```

**What it does:** declares configuration parameters without values — only types and descriptions.

| Variable | Type | Purpose |
|---|---|---|
| `location` | string | Azure region (northeurope, westeurope) |
| `resource_group_name` | string | Resource Group name |
| `virtual_machine_size` | string | VM type (Standard_B1s, Standard_B1ls) |
| `admin_username` | string | Username inside the VM |
| `ssh_public_key` | string | Public SSH key for access |
| `tags` | map(string) | Tags on all resources |
| `auto_shutdown_time` | string | Shutdown time in HHmm format (2200 = 22:00) |
| `auto_shutdown_timezone` | string | Timezone for the schedule (Windows timezone name) |

**Important note about `ssh_public_key`:** marked as `sensitive = true`. The value is passed only via an environment variable and **is never stored in a tfvars file**:
```bash
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
```

---

## vars/dev.tfvars and vars/prod.tfvars — Values per Environment

**dev.tfvars:**
```hcl
location             = "eastus"
resource_group_name  = "resource-group-terraform-azure-vm-dev"
virtual_machine_size = "Standard_D2s_v3"
admin_username       = "azureuser"
auto_shutdown_time   = "2200"
auto_shutdown_timezone = "Israel Standard Time"
tags = { environment = "dev", ... }
```

**prod.tfvars:**
```hcl
location             = "westeurope"
resource_group_name  = "resource-group-terraform-azure-vm-prod"
virtual_machine_size = "Standard_B1s"
auto_shutdown_time   = "2300"
auto_shutdown_timezone = "Israel Standard Time"
```

**Differences between environments:**

| Parameter | dev | prod |
|---|---|---|
| location | eastus | westeurope |
| virtual_machine_size | Standard_D2s_v3 | Standard_B1s |
| resource_group_name | ...-dev | ...-prod |
| auto_shutdown_time | 22:00 | 23:00 |

Running with the desired environment:
```bash
terraform apply -var-file=vars/dev.tfvars
terraform apply -var-file=vars/prod.tfvars
```

---

## main.tf — Resource Group

```hcl
resource "azurerm_resource_group" "resource_group" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
```

**What it does:** creates a **container** for all resources in Azure.

A Resource Group is a logical grouping of resources. Deleting the group deletes everything inside it at once. All other resources reference this group via `azurerm_resource_group.resource_group.name`.

---

## network.tf — Network Infrastructure

### Virtual Network

```hcl
resource "azurerm_virtual_network" "virtual_network" {
  name          = "virtual-network-main"
  address_space = ["10.10.0.0/16"]
  ...
}
```

**VNet** — a virtual private network in Azure. `10.10.0.0/16` provides 65,534 IP addresses for internal resources.

### Subnet

```hcl
resource "azurerm_subnet" "subnet" {
  name             = "subnet-main"
  address_prefixes = ["10.10.1.0/24"]
  ...
}
```

**Subnet** — a sub-network inside the VNet. `10.10.1.0/24` = 254 addresses. The VM will receive a private IP from this range.

### Public IP

```hcl
resource "azurerm_public_ip" "public_ip" {
  allocation_method = "Static"
  sku               = "Standard"
  ...
}
```

**Static Standard** — the IP is assigned immediately when the resource is created and does not change. The Basic SKU was replaced with Standard because Azure prohibited creating new Basic SKU public IPs (`IPv4BasicSkuPublicIpCountLimitReached`).

### Network Interface (NIC)

```hcl
resource "azurerm_network_interface" "network_interface" {
  ip_configuration {
    subnet_id            = azurerm_subnet.subnet.id
    public_ip_address_id = azurerm_public_ip.public_ip.id
    private_ip_address_allocation = "Dynamic"
  }
}
```

**NIC** — the VM's virtual network card. Connects the VM to the subnet and the public IP.

**Dependency chain:**
```
Resource Group → VNet → Subnet → NIC → VM
                              ↗
             Public IP ──────
```

Terraform automatically determines the creation order from these references.

---

## security.tf — Firewall

```hcl
resource "azurerm_network_security_group" "network_security_group" {
  security_rule {
    name                   = "Allow-SSH"
    priority               = 1001
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    destination_port_range = "22"
    source_address_prefix  = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "association" {
  network_interface_id      = azurerm_network_interface.network_interface.id
  network_security_group_id = azurerm_network_security_group.network_security_group.id
}
```

**What it does:**
- Creates an NSG (Network Security Group) — the equivalent of a firewall/iptables.
- Opens **only port 22 (SSH)** for inbound traffic from any source (`*`).
- Associates the NSG with the NIC — without this the rules are not applied.

**Rule parameters:**

| Parameter | Value | Meaning |
|---|---|---|
| `priority` | 1001 | Lower number = higher priority (100–4096) |
| `direction` | Inbound | Incoming traffic |
| `access` | Allow | Permit |
| `source_address_prefix` | `*` | From any IP (better to restrict for prod) |

---

## compute.tf — Virtual Machine

### Linux VM

```hcl
resource "azurerm_linux_virtual_machine" "virtual_machine" {
  size                            = var.virtual_machine_size
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}
```

**Key parameters:**

| Parameter | Value | Why |
|---|---|---|
| `disable_password_authentication` | true | SSH key only — more secure than a password |
| `storage_account_type` | Standard_LRS | HDD, cheaper than Premium_LRS (SSD) |
| `sku` | 22_04-lts | Ubuntu 22.04 LTS — stable, supported until 2027 |
| `version` | latest | Always the latest image patch |

**Image:** `Canonical / 0001-com-ubuntu-server-jammy / 22_04-lts` — this is the full identifier for the Ubuntu 22.04 image in the Azure Marketplace.

### Auto-shutdown schedule

```hcl
resource "azurerm_dev_test_global_vm_shutdown_schedule" "shutdown" {
  virtual_machine_id    = azurerm_linux_virtual_machine.virtual_machine.id
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone
  enabled               = true

  notification_settings {
    enabled = false
  }
}
```

**What it does:** shuts down the VM daily at a scheduled time.

- dev: shuts down at 22:00 (Israel Standard Time)
- prod: shuts down at 23:00 (Israel Standard Time)
- Not event-based (not on error, not on activity) — a strict **daily schedule**.
- Saves budget/free-tier quotas by preventing the VM from running around the clock.

---

## outputs.tf — Output After Apply

```hcl
output "public_ip"         { value = azurerm_public_ip.public_ip.ip_address }
output "virtual_machine_name" { value = azurerm_linux_virtual_machine.virtual_machine.name }
output "resource_group"    { value = azurerm_resource_group.resource_group.name }
output "ssh_command"        { value = "ssh ${var.admin_username}@${azurerm_public_ip.public_ip.ip_address}" }
```

After `terraform apply`, the terminal will show:

```
Outputs:
public_ip            = "20.50.123.45"
virtual_machine_name = "linux-vm-main"
resource_group       = "resource-group-terraform-azure-vm-dev"
ssh_command          = "ssh azureuser@20.50.123.45"
```

**Important:** `public_ip` is empty during `plan` (a Dynamic IP is only assigned at creation time).

---

## How Terraform Determines Resource Creation Order

Terraform reads the references between resources and builds a dependency graph automatically:

```
azurerm_resource_group
  ↓
azurerm_virtual_network  →  azurerm_subnet
                                  ↓
azurerm_public_ip  →  azurerm_network_interface
                              ↓
azurerm_network_security_group → azurerm_network_interface_security_group_association
                              ↓
                    azurerm_linux_virtual_machine
                              ↓
              azurerm_dev_test_global_vm_shutdown_schedule
```

Independent resources (e.g., VNet and Public IP) are created in parallel.

---

## Main Workflow

```bash
cd infra

# 1. Pass the SSH key (never in tfvars!)
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"

# 2. Initialize (download the provider)
terraform init

# 3. Check formatting
terraform fmt -check -recursive

# 4. Check syntax
terraform validate

# 5. Preview what will be created (no real changes)
terraform plan -var-file=vars/dev.tfvars

# 6. Create the infrastructure
terraform apply -var-file=vars/dev.tfvars

# 7. Delete everything (when no longer needed)
terraform destroy -var-file=vars/dev.tfvars
```

---

## Key Terraform Concepts

| Concept | Description |
|---|---|
| `resource` | Creates a real object in Azure |
| `variable` | Input parameter (declaration without a value) |
| `var.xxx` | Reference to a variable by name |
| `output` | What to display to the user after apply |
| `resource_type.name.attribute` | Reference to an attribute of another resource |
| `tfvars` | File with variable values for a specific environment |
| `terraform.tfstate` | State file: what Terraform knows about created resources |
| `sensitive = true` | Value is not shown in logs or the terminal |

---

## Fallback for SkuNotAvailable

If Azure returns `SkuNotAvailable`, this is a capacity issue in the region, not a Terraform error.

**Regions to try (in order of availability):**
```
eastus → westeurope → northeurope → uksouth → canadacentral
```

**VM sizes:**
```
Standard_D2s_v3  (2 vCPU, 8 GB)  ← current default, stably available
Standard_B2s     (2 vCPU, 4 GB)  ← cheaper, but often unavailable
Standard_B1s     (1 vCPU, 1 GB)  ← free-tier, often has capacity restrictions
```

Via GitHub Actions you can pass a different region/size without editing code — through `workflow_dispatch` inputs.
