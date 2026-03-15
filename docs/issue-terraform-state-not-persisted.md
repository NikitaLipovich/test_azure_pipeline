# Issue: Terraform State Not Persisted Between GitHub Actions Runs

## Summary

Terraform state is not stored remotely. Each GitHub Actions runner starts with no state,
causing Terraform to lose track of previously created Azure resources. This breaks both
`apply` (tries to recreate existing resources) and `destroy` (does nothing because state
is empty).

---

## Root Cause

`providers.tf` has no `backend` block configured. Terraform defaults to **local state**,
stored on the GitHub Actions runner filesystem. Since runners are ephemeral and destroyed
after each job, the state file is lost after every run.

---

## Incidents

### Incident 1: Apply Fails on Retry

A `terraform apply` run failed midway through resource creation:

1. `azurerm_resource_group` was successfully created in Azure
2. `azurerm_public_ip` failed with `IPv4BasicSkuPublicIpCountLimitReached`
3. The workflow exited with code 1

On the next run, Terraform tried to create the resource group again — but it already
existed in Azure. Since there was no remote state, Terraform had no knowledge of it:

```
Error: A resource with the ID "/subscriptions/***/resourceGroups/resource-group-terraform-azure-vm-dev"
already exists - to be managed via Terraform this resource needs to be imported into the State.
```

### Incident 2: Destroy Does Nothing

After a successful `apply`, running `terraform destroy` via `workflow_dispatch` produced:

```
No changes. No objects need to be destroyed.
Destroy complete! Resources: 0 destroyed.
```

The resource group was confirmed to still exist in Azure after the destroy completed:

```bash
az group show --name resource-group-terraform-azure-vm-dev
# → provisioningState: Succeeded
```

The destroy job ran on a fresh runner with empty local state. Terraform saw no resources,
concluded there was nothing to destroy, and exited successfully without touching Azure.
SSH sessions established before destroy continued to work, confirming the VM was never deleted.

---

## Impact

| Operation | Without remote state |
|-----------|----------------------|
| `apply` after partial failure | Fails — resource already exists |
| `apply` after successful run | Creates duplicates or fails |
| `destroy` | Does nothing — state is empty |
| Drift detection | Impossible — state never matches reality |

Every failed apply requires manual cleanup of Azure resources before the next run.

---

## Workaround (Manual Cleanup)

Delete the orphaned resource group from Azure:

```bash
az group delete --name resource-group-terraform-azure-vm-dev --yes
```

Or via Azure Portal: **Resource groups → resource-group-terraform-azure-vm-dev → Delete**.

---

## Proper Fix: Azure Storage Backend

Store the Terraform state file in an Azure Blob Storage container so it persists
between workflow runs.

### Cost

Essentially free — typically **$0.01–$0.05/month**:

| Component | Price |
|-----------|-------|
| Storage (1 MB state file) | ~$0.000018/month |
| Operations (~1000/month) | ~$0.0004/month |
| **Total** | **< $0.05/month** |

State files are tiny (50–200 KB for small projects). Even at 1 MB the storage cost is
negligible. Azure Blob also provides built-in state locking via lease mechanism at no
extra charge.

### Step 1 — Create Storage Account (one-time, manual)

```bash
RESOURCE_GROUP="rg-terraform-state"
STORAGE_ACCOUNT="stterraformstate$RANDOM"
CONTAINER="tfstate"
LOCATION="eastus"

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
      version = "~> 4.0"
    }
  }
}
```

### Step 4 — Re-initialize Terraform

```bash
cd infra
terraform init -migrate-state
```

---

## Why This Fixes the Problem

With a remote backend:

- State survives across workflow runs — stored in Azure Blob Storage
- `apply` reads current state before creating anything — never tries to recreate existing resources
- Failed `apply` mid-run: next run picks up from where it left off
- `destroy` correctly knows what resources exist and tears them all down
- Azure Blob lease provides automatic state locking — prevents concurrent runs from corrupting state

---

## References

- [Store Terraform state in Azure Storage — Microsoft Learn](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage)
- [Backend Type: azurerm — HashiCorp Developer](https://developer.hashicorp.com/terraform/language/backend/azurerm)
