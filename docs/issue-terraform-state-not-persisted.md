# Issue: Terraform State Not Persisted Between GitHub Actions Runs

## Summary

Terraform state is not stored remotely. Each GitHub Actions runner starts with no state,
causing Terraform to lose track of previously created Azure resources. This leads to
failed `apply` runs when partially created infrastructure already exists in Azure.

---

## What Happened

During a `terraform apply` run triggered by a push to `main`, the pipeline failed midway
through resource creation:

1. `azurerm_resource_group` was successfully created in Azure
2. `azurerm_public_ip` failed with `IPv4BasicSkuPublicIpCountLimitReached`
3. The workflow exited with code 1

On the next run (after fixing the Public IP SKU issue), Terraform attempted to create
the resource group again. Since there was no remote state, Terraform had no knowledge
that the resource group already existed in Azure, resulting in:

```
Error: A resource with the ID "/subscriptions/***/resourceGroups/resource-group-terraform-azure-vm-dev"
already exists - to be managed via Terraform this resource needs to be imported into the State.
```

---

## Root Cause

`providers.tf` has no `backend` block configured. Terraform defaults to **local state**,
which is stored on the GitHub Actions runner filesystem. Since runners are ephemeral
(destroyed after each job), the state file is lost after every run.

```hcl
# Current providers.tf — no backend block
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}
```

---

## Impact

- Any failed `apply` that partially creates resources will break all subsequent runs
- Terraform cannot detect drift between its (empty) state and real Azure resources
- Manual cleanup of Azure resources is required after every failed apply
- `terraform destroy` in the workflow will not work correctly — it will find nothing
  to destroy since state is always empty

---

## Second Incident: Destroy Does Nothing

After a successful `apply` (resources exist in Azure), running `terraform destroy`
via `workflow_dispatch` produced:

```
No changes. No objects need to be destroyed.
Either you have not created any objects yet or the existing objects were
already deleted outside of Terraform.

Destroy complete! Resources: 0 destroyed.
```

The resource group `resource-group-terraform-azure-vm-dev` was confirmed to still
exist in Azure after the destroy workflow completed:

```bash
az group show --name resource-group-terraform-azure-vm-dev
# → provisioningState: Succeeded
```

**Root cause is identical** — the destroy job runs on a fresh runner with empty local
state. Terraform sees no resources in state, concludes there is nothing to destroy,
and exits successfully without touching Azure.

**SSH sessions established before destroy continued to work**, further confirming the
VM was never actually deleted.

### Workaround for Destroy

Manually delete the resource group:

```bash
az group delete --name resource-group-terraform-azure-vm-dev --yes
```

---

## Immediate Workaround

Manually delete the orphaned resource group from Azure before re-running the workflow:

```bash
az group delete --name resource-group-terraform-azure-vm-dev --yes --no-wait
```

Or via Azure Portal: **Resource groups → resource-group-terraform-azure-vm-dev → Delete**.

---

## Proper Fix: Azure Storage Backend

Store the Terraform state file in an Azure Blob Storage container so it persists
between workflow runs.

### Step 1 — Create Storage Account (one-time, manual)

```bash
RESOURCE_GROUP="rg-terraform-state"
STORAGE_ACCOUNT="stterraformstate$RANDOM"
CONTAINER="tfstate"
LOCATION="northeurope"

az group create --name $RESOURCE_GROUP --location $LOCATION

az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --sku Standard_LRS \
  --encryption-services blob

az storage container create \
  --name $CONTAINER \
  --account-name $STORAGE_ACCOUNT
```

### Step 2 — Grant Service Principal Access to Storage

```bash
STORAGE_ID=$(az storage account show \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee <AZURE_CLIENT_ID> \
  --scope $STORAGE_ID
```

### Step 3 — Add Backend Block to `providers.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "<STORAGE_ACCOUNT_NAME>"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
    use_oidc             = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}
```

### Step 4 — Re-initialize Terraform

After adding the backend block, run locally to migrate state:

```bash
cd infra
terraform init -migrate-state
```

---

## Why This Fixes the Problem

With a remote backend:

- State is stored in Azure Blob Storage and survives across workflow runs
- On every `terraform plan` / `apply`, Terraform reads the current state from Azure
  and compares it to real infrastructure — it will never try to recreate existing resources
- If an `apply` fails midway, the next run will pick up from where it left off
- `terraform destroy` will correctly know what resources to tear down

---

## References

- [Store Terraform state in Azure Storage — Microsoft Learn](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage)
- [Backend Type: azurerm — HashiCorp Developer](https://developer.hashicorp.com/terraform/language/backend/azurerm)
