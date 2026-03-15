Let me break it down "in plain language": exactly what the assignment wants from you, why your friend's run failed, and what to do next (with ready-made **terraform + GitHub Actions** templates).

---

## 1) What the Assignment Actually Means

**"Build a GH actions workflow to provision a free tier VM in azure using terraform"** = the repository must contain:

1. **Terraform code** that creates a *minimal Linux VM* in Azure (preferably free-tier B1s), plus basic network/SG/public IP, tags, and (optionally) auto-shutdown.
2. **A GitHub Actions workflow** that on push/PR does:

   * `terraform fmt/validate`
   * `terraform plan`
   * and on manual approval (or on merge to main) does `terraform apply`
3. **GitHub → Azure authentication** (preferably via **OIDC**, without passwords/secrets).
4. Optionally: `terraform destroy` (manual), so as not to use up limits/money.

**The DevOps point**: to show that you can do "Infrastructure as Code" + CI/CD pipeline + secure cloud access.

---

## 2) Why Your Friend Got `SkuNotAvailable` on Standard_B1s

This is not a "terraform error". This is Azure's response: **the selected region currently has no capacity/quota/availability for this VM size** for your subscription.

Main causes:

* **Capacity**: B-series VMs are super popular → the region has "no free slots" right now.
* **SKU restricted per subscription/region**: sometimes a "Free/Trial/Student" subscription is not allowed a specific SKU in a specific region (or is given it with restrictions).
* **Quota = 0 / very low**: sometimes the vCPU limit in a region is not granted/has been exhausted (especially on new/trial accounts).

Important: "Free tier 750 hours B1s" **does not mean "B1s is always available in East US"**. It's only about the cost, not about capacity availability.

---

## 3) What to Do if B1s Is Unavailable (Real Options)

### Option A (most practical for the assignment): make a size fallback + choose a "quiet" region

1. Try regions where capacity is more often available: `northeurope`, `westeurope`, `uksouth`, `canadacentral`, sometimes `swedencentral`, etc.
2. Try alternative sizes that often work:

   * `Standard_B1ls` (sometimes more available)
   * `Standard_B1ms`
   * `Standard_A1_v2` / `Standard_A1m_v2` (sometimes "older" ones are available, but not always free-tier)

For the assignment it is usually enough to show the pipeline + terraform. Even if B1s didn't come up, **but you showed a fallback/check/handling — that looks very DevOps**.

### Option B: check quotas and request a quota increase

* Check vCPU usage/quota in the region and request an increase (via Azure Portal → Quotas).
  Downside: may take time / won't be approved immediately.

### Option C: use Spot (not always suitable)

Spot may be more available capacity-wise, but:

* The VM can be evicted
* The free-tier "idea" is lost
  Usually not needed for a simple assignment.

### Option D: agree with the reviewer on "any cheap VM" instead of strict free-tier

If they want "a VM at all" and free-tier is just preferred, you can take the minimum available size (e.g., B2s) and **immediately enable auto-shutdown** to avoid burning through the budget.

---

## 4) What Exactly Is Required from You as Deliverables (Checklist)

The minimum that looks "correct":

* ✅ `infra/` (or repo root) with terraform files
* ✅ `.github/workflows/terraform.yml`
* ✅ OIDC configured: GitHub → Azure login without client secret
* ✅ `plan` works on PR
* ✅ `apply` either manual (workflow_dispatch), or only on main + environment approval
* ✅ `destroy` manual
* ✅ tags on resources
* ✅ (optional) auto-shutdown schedule

---

## 5) Ready Example: Terraform (VM + network + auto-shutdown)

Structure:

```
infra/
  providers.tf
  variables.tf
  main.tf
  outputs.tf
```

### `infra/providers.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}
```

### `infra/variables.tf`

```hcl
variable "location" {
  type    = string
  default = "northeurope"
}

variable "resource_group_name" {
  type    = string
  default = "rg-gha-tf-freevm"
}

variable "vm_size" {
  type    = string
  default = "Standard_B1s"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "ssh_public_key" {
  type = string
}

variable "tags" {
  type = map(string)
  default = {
    project = "gha-terraform-azure-vm"
    owner   = "devops-assignment"
  }
}

variable "auto_shutdown_time" {
  type    = string
  default = "2200" # HHmm in VM local time (approx)
}

variable "auto_shutdown_timezone" {
  type    = string
  default = "Israel Standard Time"
}
```

### `infra/main.tf`

```hcl
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-freevm"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-freevm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-freevm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "pip" {
  name                = "pip-freevm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  tags                = var.tags
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-freevm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-freevm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size

  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_username = var.admin_username

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

  tags = var.tags
}

# Auto-shutdown schedule (DevTest Labs feature)
resource "azurerm_dev_test_global_vm_shutdown_schedule" "shutdown" {
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  location           = azurerm_resource_group.rg.location
  enabled            = true

  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled = false
  }

  tags = var.tags
}
```

### `infra/outputs.tf`

```hcl
output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}
```

---

## 6) GitHub Actions Workflow (OIDC + plan/apply/destroy)

File: `.github/workflows/terraform-azure-vm.yml`

```yaml
name: terraform-azure-vm

on:
  pull_request:
    paths:
      - "infra/**"
      - ".github/workflows/terraform-azure-vm.yml"
  push:
    branches: ["main"]
    paths:
      - "infra/**"
      - ".github/workflows/terraform-azure-vm.yml"
  workflow_dispatch:
    inputs:
      action:
        description: "apply or destroy"
        required: true
        default: "apply"
        type: choice
        options:
          - apply
          - destroy
      location:
        description: "Azure region (e.g., northeurope, westeurope)"
        required: false
        default: "northeurope"
      vm_size:
        description: "VM size (e.g., Standard_B1s, Standard_B1ls, Standard_B1ms)"
        required: false
        default: "Standard_B1s"

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: azure-prod

    defaults:
      run:
        working-directory: infra

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7.5"

      - name: Terraform fmt
        run: terraform fmt -check -recursive

      - name: Terraform init
        run: terraform init

      - name: Terraform validate
        run: terraform validate

      - name: Terraform plan
        id: plan
        env:
          TF_VAR_ssh_public_key: ${{ secrets.SSH_PUBLIC_KEY }}
        run: |
          terraform plan \
            -input=false \
            -out=tfplan \
            -var="location=${{ inputs.location || 'northeurope' }}" \
            -var="vm_size=${{ inputs.vm_size || 'Standard_B1s' }}"

      - name: Comment plan on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const body = `Terraform plan completed for \`${context.repo.owner}/${context.repo.repo}\`.\n\nCommit: ${context.sha}\n`;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body
            });

      - name: Terraform apply
        if: github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && inputs.action == 'apply')
        env:
          TF_VAR_ssh_public_key: ${{ secrets.SSH_PUBLIC_KEY }}
        run: |
          terraform apply -input=false -auto-approve tfplan

      - name: Terraform destroy
        if: github.event_name == 'workflow_dispatch' && inputs.action == 'destroy'
        env:
          TF_VAR_ssh_public_key: ${{ secrets.SSH_PUBLIC_KEY }}
        run: |
          terraform destroy -input=false -auto-approve \
            -var="location=${{ inputs.location }}" \
            -var="vm_size=${{ inputs.vm_size }}"
```

**What's important:**

* `permissions: id-token: write` is required for OIDC.
* Secrets are needed **without a password**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and `SSH_PUBLIC_KEY`.
* `environment: azure-prod` — it's convenient to set "Required reviewers" in GitHub Environments so that apply requires "confirmation" (very DevOps).

---

## 7) How to Set Up OIDC (briefly, what you actually need to do)

You need an **App Registration / Service Principal** in Azure AD + a "Federated credential" for GitHub.

High-level:

1. Create an App Registration
2. Grant it a role on the subscription/resource group: e.g., **Contributor** on the required RG/Subscription
3. In App → Federated credentials, add trust for the GitHub repo (issuer `https://token.actions.githubusercontent.com`, subject like `repo:ORG/REPO:environment:azure-prod` or `repo:ORG/REPO:ref:refs/heads/main`)
4. In GitHub repo settings → Secrets and variables:

   * `AZURE_CLIENT_ID`
   * `AZURE_TENANT_ID`
   * `AZURE_SUBSCRIPTION_ID`
   * `SSH_PUBLIC_KEY` (a regular public key `ssh-ed25519 ...`)

---

## 8) How to "Cleanly" Handle the `SkuNotAvailable` Problem in Your Solution

To look professional, do this:

1. In the workflow, `workflow_dispatch` inputs already have `location` and `vm_size` → you can **re-run apply** with different values without editing code.
2. In the README, write:

   * "If Standard_B1s is unavailable in the region, try `Standard_B1ls` or a different region (northeurope/westeurope)."
3. (Optional) Add a list of "fallback sizes" and an explanation that free-tier = billing benefit, not capacity guarantee.

If you want a real "wow" effect: you could make `vm_size` a list and try each one in turn via a matrix, but for an assignment that's overkill.

---

## 9) What to Tell / Write the Reviewer (in essence)

Text along these lines:

* "I set up OIDC GitHub→Azure, a plan/apply/destroy pipeline, a VM with tags and auto-shutdown."
* "Apply sometimes fails with `SkuNotAvailable` due to regional capacity for B1s on a free subscription."
* "I added the ability to choose region/size via workflow_dispatch and described fallback options."

---

If you share the **assignment requirements word-for-word** (or a screenshot) and tell me **whether the repo is private/public + what the environment is called**, I'll tailor the YAML to their expectations (for example: apply only after manual approval, separate jobs, backend state, naming conventions).

[1]: https://docs.github.com/actions/using-workflows/events-that-trigger-workflows?utm_source=chatgpt.com "Events that trigger workflows"
[2]: https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure?utm_source=chatgpt.com "Configuring OpenID Connect in Azure"
[3]: https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect?utm_source=chatgpt.com "Use the Azure Login action with OpenID Connect"
[4]: https://github.com/Azure/login?utm_source=chatgpt.com "Azure/login: Connect to Azure"
[5]: https://docs.github.com/actions/using-workflows/about-workflows?utm_source=chatgpt.com "Workflows - GitHub Docs"
[6]: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine?utm_source=chatgpt.com "azurerm_linux_virtual_machine | hashicorp/azurerm | Terraform"
[7]: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_test_global_vm_shutdown_schedule.html?utm_source=chatgpt.com "azurerm_dev_test_global_vm_s..."
