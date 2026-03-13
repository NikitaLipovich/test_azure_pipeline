# GHA Terraform Azure VM

GitHub Actions pipeline that provisions a free-tier Linux VM in Azure using Terraform, with OIDC authentication (no stored passwords/secrets).

---

## Repository structure

```
.
├── infra/
│   ├── providers.tf       # Terraform + azurerm provider config
│   ├── variables.tf       # All input variables with defaults
│   ├── main.tf            # Resources: RG, VNet, NSG, NIC, VM, auto-shutdown
│   └── outputs.tf         # Public IP, VM name, SSH command
└── .github/
    └── workflows/
        └── terraform-azure-vm.yml   # CI/CD pipeline
```

---

## Prerequisites

### 1. Azure Service Principal with OIDC (no client secret)

```bash
# Create App Registration
az ad app create --display-name "gha-terraform-azure-vm"

# Note the appId from output, then create SP
az ad sp create --id <appId>

# Assign Contributor on subscription (or scope to a specific RG)
az role assignment create \
  --assignee <appId> \
  --role Contributor \
  --scope /subscriptions/<subscriptionId>
```

Then add a **Federated Credential** in Azure Portal:
- App Registration → Certificates & Secrets → Federated credentials → Add
- Issuer: `https://token.actions.githubusercontent.com`
- Subject: `repo:<ORG>/<REPO>:environment:azure-prod`

### 2. GitHub Secrets (repo Settings → Secrets and variables → Actions)

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | App Registration Application (client) ID |
| `AZURE_TENANT_ID` | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID |
| `SSH_PUBLIC_KEY` | Content of your public key, e.g. `ssh-ed25519 AAAA...` |

### 3. GitHub Environment

Create an environment named **`azure-prod`** (Settings → Environments) and optionally add **Required reviewers** — this forces a manual approval before `apply` runs.

---

## Pipeline behaviour

| Trigger | What runs |
|---|---|
| PR touching `infra/**` | `fmt`, `init`, `validate`, `plan` → comment on PR |
| Push to `main` | `plan` + `apply` (gated by environment approval) |
| `workflow_dispatch` → `apply` | Manual provision with custom region/size |
| `workflow_dispatch` → `destroy` | Manual teardown of all resources |

---

## Running manually (workflow_dispatch)

1. GitHub → Actions → **terraform-azure-vm** → **Run workflow**
2. Choose:
   - `action`: `apply` or `destroy`
   - `location`: Azure region (see fallbacks below)
   - `vm_size`: VM size (see fallbacks below)

---

## SkuNotAvailable — troubleshooting

`SkuNotAvailable` means Azure has no capacity for that VM size **in that region right now** for your subscription. This is a capacity/quota issue, not a Terraform bug.

**Free tier** = billing benefit (750 h/month free). It does **not** guarantee capacity.

### Fallback regions (try in order)

```
northeurope   ← default, usually good
westeurope
uksouth
canadacentral
swedencentral
```

### Fallback VM sizes (all qualify for free-tier billing)

```
Standard_B1s    ← default (1 vCPU, 1 GB RAM)
Standard_B1ls   ← smaller, often more available
Standard_B1ms   ← 1 vCPU, 2 GB RAM
Standard_B2s    ← 2 vCPU, 4 GB RAM (not always free)
```

Re-run the workflow with a different `location`/`vm_size` combination without touching any code.

---

## Local development

```bash
cd infra
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"

az login
terraform init
terraform plan -var="location=northeurope"
terraform apply
terraform destroy
```
