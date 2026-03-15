# Setup Tutorial: Terraform + Azure VM via GitHub Actions (OIDC)

This is a step-by-step guide for setting up the environment to run a Terraform pipeline
that deploys a Linux VM in Azure via GitHub Actions with OIDC authorization
(no secrets/passwords stored).

---

## Table of Contents

1. [What to Install](#1-what-to-install)
2. [Azure Preparation](#2-azure-preparation)
3. [OIDC Setup — Federated Credential](#3-oidc-setup--federated-credential)
4. [SSH Key Generation](#4-ssh-key-generation)
5. [GitHub Repository Setup](#5-github-repository-setup)
6. [GitHub Environment with Required Reviewers](#6-github-environment-with-required-reviewers)
7. [First Pipeline Run](#7-first-pipeline-run)
8. [Connecting to VM via SSH](#8-connecting-to-vm-via-ssh)
9. [Destroying the Infrastructure](#9-destroying-the-infrastructure)
10. [Running Terraform Locally (optional)](#10-running-terraform-locally-optional)

---

## 1. What to Install

### Required (locally)

| Tool | Version | Purpose |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.6.0 | IaC — infrastructure description |
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) | latest | Creating Service Principal, OIDC |
| [Git](https://git-scm.com/downloads) | latest | Working with the repository |
| SSH (built into Windows 11) | — | Key generation and VM connection |

### Verifying the Installation

```bash
terraform -version   # >= 1.6.0
az version           # any current version
git --version
ssh -V
```

---

## 2. Azure Preparation

### 2.1. Log in to Azure CLI

```bash
az login
```

A browser will open — log in to your Microsoft/Azure account.

### 2.2. Select a Subscription

```bash
# View all available subscriptions
az account list --output table

# Set the desired one (replace <SUBSCRIPTION_ID>)
az account set --subscription "<SUBSCRIPTION_ID>"

# Verify the correct one is selected
az account show --output table
```

Save these values — you will need them later:
- `id` — this is `AZURE_SUBSCRIPTION_ID`
- `tenantId` — this is `AZURE_TENANT_ID`

### 2.3. Create a Service Principal (App Registration)

```bash
az ad sp create-for-rbac \
  --name "sp-github-terraform-azure-vm" \
  --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID> \
  --sdk-auth false
```

From the output, save:
- `appId` — this is `AZURE_CLIENT_ID`

> **Important:** the `--sdk-auth false` flag is intentional. We use OIDC,
> so `clientSecret` is not needed.

---

## 3. OIDC Setup — Federated Credential

OIDC allows GitHub Actions to authenticate in Azure **without a client secret**.
Instead, Azure trusts tokens that GitHub generates for a specific repository.

### 3.1. Add a Federated Credential for push to main

```bash
az ad app federated-credential create \
  --id "<AZURE_CLIENT_ID>" \
  --parameters '{
    "name": "github-push-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<GITHUB_USERNAME>/<REPO_NAME>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### 3.2. Add a Federated Credential for pull_request

```bash
az ad app federated-credential create \
  --id "<AZURE_CLIENT_ID>" \
  --parameters '{
    "name": "github-pull-request",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<GITHUB_USERNAME>/<REPO_NAME>:pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### 3.3. Add a Federated Credential for Environment (workflow_dispatch)

The workflow uses the GitHub Environment `azure-prod`. A separate credential is required for it:

```bash
az ad app federated-credential create \
  --id "<AZURE_CLIENT_ID>" \
  --parameters '{
    "name": "github-environment-azure-prod",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<GITHUB_USERNAME>/<REPO_NAME>:environment:azure-prod",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

> Replace `<GITHUB_USERNAME>/<REPO_NAME>` with the real values, for example:
> `myuser/my-infra-repo`

### 3.4. Verify the List of Federated Credentials

```bash
az ad app federated-credential list --id "<AZURE_CLIENT_ID>" --output table
```

There should be 3 entries.

---

## 4. SSH Key Generation

The VM is created with password authentication disabled. Access is via SSH key only.

```bash
# Generate an RSA 4096 key (Azure does not support ed25519)
ssh-keygen -t rsa -b 4096 -C "azure-vm-terraform" -f ~/.ssh/azure_vm_key_rsa
```

Two files will be created:
- `~/.ssh/azure_vm_key_rsa` — private key (never share with anyone)
- `~/.ssh/azure_vm_key_rsa.pub` — public key (uploaded to GitHub Secrets)

> **Important:** Azure only supports RSA keys. `ed25519` keys will cause an error during `terraform apply`.

```bash
# View the contents of the public key
cat ~/.ssh/azure_vm_key_rsa.pub
```

Copy the output — you will need it in the next step.

---

## 5. GitHub Repository Setup

### 5.1. Go to Settings > Secrets and variables > Actions

Path: `https://github.com/<GITHUB_USERNAME>/<REPO_NAME>/settings/secrets/actions`

### 5.2. Add Repository Secrets

Click **New repository secret** for each one:

| Secret Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | `appId` from step 2.3 |
| `AZURE_TENANT_ID` | `tenantId` from step 2.2 |
| `AZURE_SUBSCRIPTION_ID` | `id` from step 2.2 |
| `SSH_PUBLIC_KEY` | contents of `~/.ssh/azure_vm_key_rsa.pub` |

> 4 secrets total. No passwords or client secrets needed.

---

## 6. GitHub Environment with Required Reviewers

The workflow is tied to the `azure-prod` Environment. This prevents accidental apply without confirmation.

### 6.1. Create an Environment

1. Go to **Settings > Environments**
2. Click **New environment**
3. Name: `azure-prod`
4. Click **Configure environment**

### 6.2. Enable Required Reviewers

1. In the **Deployment protection rules** block, enable **Required reviewers**
2. Add yourself (or the appropriate person) as a reviewer
3. Click **Save protection rules**

Now every apply/destroy via workflow_dispatch will require manual confirmation.

---

## 7. First Pipeline Run

### 7.1. Via push to main (automatic apply)

```bash
git add .
git commit -m "feat: initial terraform infrastructure"
git push origin main
```

The workflow will start automatically on push to `main` with action `apply` and environment `dev`.

### 7.2. Via workflow_dispatch (manual run)

1. Go to **Actions** > **terraform-azure-vm**
2. Click **Run workflow**
3. Select parameters:
   - **action**: `apply` or `destroy`
   - **environment**: `dev` or `prod`
   - **location** (optional): e.g., `eastus` if B1s is unavailable in your region
   - **virtual_machine_size** (optional): e.g., `Standard_B1ls` if `Standard_B1s` is unavailable
4. Click **Run workflow**
5. Confirm the deployment in the **Review deployments** block (because Required Reviewers is enabled)

### 7.3. Via Pull Request (plan only)

When a PR is created that changes files in `infra/` or `.github/workflows/terraform-azure-vm.yml`,
`terraform plan` is automatically triggered. The result is posted as a comment on the PR.

---

## 8. Connecting to VM via SSH

After a successful apply, find the IP address in the workflow output:

In the **Terraform Apply** step under **Outputs** there will be a line:
```
ssh_command = "ssh azureuser@<PUBLIC_IP>"
```

Connect:
```bash
ssh -i ~/.ssh/azure_vm_key_rsa azureuser@<PUBLIC_IP>
```

---

## 9. Destroying the Infrastructure

Via **workflow_dispatch**:
1. **action**: `destroy`
2. **environment**: the desired environment
3. Confirm in **Review deployments**

Or locally (see section 10).

> **Warning:** after destroy, all VM data will be permanently deleted.

---

## 10. Running Terraform Locally (optional)

For debugging, Terraform can be run locally.

### 10.1. Log in to Azure CLI

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

### 10.2. Pass the SSH Key via Environment Variable

```bash
# Linux/macOS
export TF_VAR_ssh_public_key="$(cat ~/.ssh/azure_vm_key.pub)"

# Windows PowerShell
$env:TF_VAR_ssh_public_key = Get-Content ~/.ssh/azure_vm_key.pub -Raw
```

### 10.3. Run Terraform

```bash
cd infra

terraform init
terraform validate
terraform fmt -check -recursive

# Plan for the dev environment
terraform plan -var-file=vars/dev.tfvars

# Apply
terraform apply -var-file=vars/dev.tfvars

# Destroy
terraform destroy -var-file=vars/dev.tfvars
```

---

## Quick Checklist

- [ ] Installed: Terraform >= 1.6.0, Azure CLI, Git, SSH
- [ ] Ran `az login`, selected the correct subscription
- [ ] Created a Service Principal, saved `AZURE_CLIENT_ID`
- [ ] Added 3 Federated Credentials (push/main, pull_request, environment/azure-prod)
- [ ] Generated SSH key `~/.ssh/azure_vm_key`
- [ ] Added 4 Repository Secrets to GitHub
- [ ] Created GitHub Environment `azure-prod` with Required Reviewers
- [ ] Performed first push / workflow_dispatch
- [ ] Workflow completed successfully, VM is running
- [ ] Verified SSH connection

---

## Variable Reference

| Variable | Where to find it | Example |
|---|---|---|
| `AZURE_SUBSCRIPTION_ID` | `az account show --query id -o tsv` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_CLIENT_ID` | `az ad sp show --display-name sp-github-terraform-azure-vm --query appId -o tsv` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `SSH_PUBLIC_KEY` | `cat ~/.ssh/azure_vm_key.pub` | `ssh-ed25519 AAAA...` |
