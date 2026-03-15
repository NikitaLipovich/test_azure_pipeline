# Answers to Questions about Terraform and Azure

---

## 1. VNet / Subnet / NIC — What They Are and Why They Exist

Think of the network in Azure like a physical corporate network, only virtual.

**VNet (Virtual Network)** = your private network in the cloud. An isolated space where resources can communicate with each other. Nothing from outside can see it until you open it yourself.

**Subnet** = a segment inside a VNet. Why divide it? To separate resources: databases in one subnet, web servers in another. Each subnet has its own security rules. We have one VM — one subnet.

**NIC (Network Interface Card)** = a virtual network card. The NIC is what "plugs into" the VM and says: "I am on this subnet, I have this private IP, and here is my public IP". A VM without a NIC = a computer without a network card.

**Analogy:**
```
VNet     = a building with an internal network
Subnet   = a floor in that building
NIC      = the network socket in the wall that a computer (VM) plugs into
Public IP = the phone number that can be called from outside
```

**What to think about as a developer when configuring:**
- Choose a VNet address space with room to grow (`/16` = 65k addresses — more than enough)
- Subnets must not overlap each other
- The NIC must be in the same Resource Group and region as the VM
- NSG (firewall) is attached to the NIC or to the subnet — in our case it is attached to the NIC

---

## 2. The `features {}` Block

```hcl
provider "azurerm" {
  features {}
}
```

This is a **required empty block** — it is a requirement of the `azurerm` provider. Without it, Terraform will throw an error at `init`.

Why does it exist at all? Inside `features {}` you can pass optional settings for the provider's behavior, for example:

```hcl
features {
  virtual_machine {
    delete_os_disk_on_deletion = true  # delete the disk when deleting the VM
  }
  key_vault {
    purge_soft_delete_on_destroy = true
  }
}
```

Ours is empty — defaults are used. But it must be present.

---

## 3. Variables in `variables.tf` — Does Azure Create a Resource Automatically?

**No. `variables.tf` only declares parameters; Azure creates nothing.**

Let's break it down using `resource_group_name` as an example:

```hcl
# variables.tf — only DECLARES that the variable exists
variable "resource_group_name" {
  type = string
}

# dev.tfvars — sets the VALUE
resource_group_name = "resource-group-terraform-azure-vm-dev"

# main.tf — this is where Azure CREATES the resource
resource "azurerm_resource_group" "resource_group" {
  name = var.resource_group_name  # takes the value from the variable
}
```

Chain: `variables.tf` (declaration) → `dev.tfvars` (value) → `main.tf` (creation in Azure).

**Important:** if a variable is declared but not used anywhere in a `resource "..."` block — nothing will be created in Azure.

---

## 4. `ssh_public_key` — Why `sensitive = true`, What It's For, and How to Configure It

```hcl
variable "ssh_public_key" {
  type      = string
  sensitive = true
}
```

**`sensitive = true` is not `true` as the variable's value.** It is a declaration attribute that tells Terraform: "do not show this value in logs or the terminal". The actual value is the contents of the public SSH key.

**What it's for:** with `disable_password_authentication = true` in the VM, password access is disabled; you can only log in with an SSH key. The public key is uploaded to the VM (`~/.ssh/authorized_keys`), while the private key stays with you locally.

**This is for Azure** (not for GitHub). It is needed to access the VM via SSH.

**How to configure on Windows PowerShell:**

```powershell
# Step 1: Generate the key (once)
ssh-keygen -t ed25519 -C "azure-vm" -f $HOME\.ssh\azure_vm_key
# Creates two files:
# ~/.ssh/azure_vm_key     — private (only with you)
# ~/.ssh/azure_vm_key.pub — public (uploaded to Azure/GitHub)

# Step 2: Set the environment variable in PowerShell
$env:TF_VAR_ssh_public_key = Get-Content "$HOME\.ssh\azure_vm_key.pub" -Raw

# Verify it was set
echo $env:TF_VAR_ssh_public_key
```

---

## 5. Environment Variables in Windows PowerShell

**For the current session** (temporary, lost when the window is closed):
```powershell
$env:TF_VAR_ssh_public_key = Get-Content "$HOME\.ssh\azure_vm_key.pub" -Raw
```

**Permanently for the current user:**
```powershell
[System.Environment]::SetEnvironmentVariable(
  "TF_VAR_ssh_public_key",
  (Get-Content "$HOME\.ssh\azure_vm_key.pub" -Raw),
  "User"
)
```

After this, restart PowerShell — the variable will always be available.

**Why `TF_VAR_`?** Terraform automatically reads any environment variable with the `TF_VAR_` prefix and maps it to the same-named variable in Terraform. `TF_VAR_ssh_public_key` → `var.ssh_public_key`.

---

## 6. `tags` — What They Are and Where They Are Used

```hcl
# variables.tf
variable "tags" {
  type = map(string)  # dictionary: key → value
}

# dev.tfvars
tags = {
  environment = "dev"
  project     = "azure-vm-terraform"
  managed_by  = "terraform"
}
```

**A tag is a label on an Azure resource.** It is the equivalent of a label in Kubernetes or a sticker on a box.

**Where it is used:** on all resources that have `tags = var.tags` — VNet, Public IP, NIC, VM, and Resource Group.

**What you'll see in the Azure Portal:** on any resource → the Tags tab → it will show:
```
environment = dev
project     = azure-vm-terraform
managed_by  = terraform
```

**Why they are needed:**
- Filtering: "show all resources with `environment=dev`"
- Billing: you can group costs by tag (`project=X costs $50/month`)
- Automation: scripts can search for resources by tags
- Auditing: immediately shows that this resource was created by Terraform

**This is for Azure only** (not for GitHub). GitHub does not know about Azure tags.

---

## 7. Do the Variables in `variables.tf`, `dev.tfvars`, `prod.tfvars` Overlap?

No, they **complement** each other — each file has its own role:

```
variables.tf   = SCHEMA (what kind of variable, its type, description)
dev.tfvars     = VALUES for the dev environment
prod.tfvars    = VALUES for the prod environment
```

There are no redundant files. When Terraform runs:
1. It reads `variables.tf` — learns which variables are expected
2. It reads the specified `-var-file` (dev or prod) — gets the concrete values
3. It substitutes values everywhere `var.xxx` appears

`dev.tfvars` and `prod.tfvars` are never read at the same time.

---

## 8. Why Separate dev and prod Environments?

So that **the same code** creates different infrastructures without editing files.

| | dev | prod |
|---|---|---|
| Region | northeurope | westeurope |
| Resource Group | ...-dev | ...-prod |
| Shutdown | 22:00 | 23:00 |

**Practical purpose:**
- dev: test a new config, break things — no big deal
- prod: stable environment, changes only after testing in dev
- Both exist simultaneously and independently (different Resource Groups in Azure)
- No risk of accidentally `destroy`-ing prod instead of dev

---

## 9. Address Calculation Rules in `network.tf`

```
VNet:   10.10.0.0/16   → 65534 addresses
Subnet: 10.10.1.0/24   → 254 addresses
```

**How to read CIDR notation:**
- `10.10.0.0/16` — first 16 bits are fixed (`10.10`), remaining 16 are free → 2^16 - 2 = 65534 addresses
- `10.10.1.0/24` — first 24 bits are fixed (`10.10.1`), last 8 are free → 2^8 - 2 = 254 addresses

**Why `10.10.x.x` specifically:** the `10.0.0.0/8` range is private (RFC 1918) and is not routed on the internet. You could use `10.0.0.0`, `172.16.0.0`, `192.168.0.0` — they all work. The choice of `10.10` is readable and does not conflict with typical home networks (`192.168.1.x`).

**Rules for manual configuration:**
1. The Subnet must be **inside** the VNet: `10.10.1.0/24` is within `10.10.0.0/16` ✓
2. Subnets within the same VNet must not **overlap**
3. Azure reserves 5 addresses in each subnet (first 4 + last) — only 249 out of 254 are actually available
4. Choose the VNet with plenty of room (`/16`); size the Subnet to actual needs
5. If you plan multiple subnets — carve them out upfront: `10.10.1.0/24`, `10.10.2.0/24`, `10.10.3.0/24`

---

## 10. Why Dynamic IP Instead of Static?

```hcl
allocation_method = "Dynamic"
private_ip_address_allocation = "Dynamic"
```

**A static public IP in Azure costs money** (~$3–4/month), even when the VM is off.

**Dynamic** — free, but the IP changes each time the VM starts.

**For our case (dev/learning project):**
- The VM shuts down every day on a schedule
- After starting, the IP will change — that's fine, the IP is always visible in outputs
- Saving money is more important than a stable IP

**For prod** where a stable IP is needed (DNS, certificate) — use `Static`.

---

## 11. The Dependency Chain — Why It's Needed

Terraform cannot create a NIC without a Subnet, or a Subnet without a VNet. It understands this through **references between resources**:

```hcl
# NIC references the Subnet
subnet_id = azurerm_subnet.subnet.id
            ↑ Terraform sees the dependency here
```

**Why it is needed:** so Terraform knows the order of creation and deletion.

**Creation — dependencies first:**
```
Resource Group → VNet → Subnet ─┐
                Public IP ──────→ NIC → NSG Association → VM → Shutdown
```

**Deletion:** in reverse order — you can't delete a VNet while it still has a Subnet with a NIC.

**Independent resources are created in parallel:** VNet and Public IP don't depend on each other — Terraform launches them simultaneously.

**Specific places in the code where dependencies are defined:**

| File | Line | Dependency |
|---|---|---|
| `network.tf:4` | `location = azurerm_resource_group.resource_group.location` | VNet ← Resource Group |
| `network.tf:12` | `virtual_network_name = azurerm_virtual_network.virtual_network.name` | Subnet ← VNet |
| `network.tf:32` | `subnet_id = azurerm_subnet.subnet.id` | NIC ← Subnet |
| `network.tf:34` | `public_ip_address_id = azurerm_public_ip.public_ip.id` | NIC ← Public IP |
| `security.tf` | `network_interface_id = azurerm_network_interface.network_interface.id` | Association ← NIC |
| `compute.tf` | `network_interface_ids = [azurerm_network_interface.network_interface.id]` | VM ← NIC |

---

## 12. SSH From Any Source (`*`) — Is This Correct?

```hcl
source_address_prefix = "*"  # from any IP
```

**No, this is not secure for prod.** For a learning project — it is acceptable.

With `*`, anyone on the internet can attempt to connect via SSH. The password is disabled (key only), so without the private key they still won't get in. But bots will still hammer the port and create noise in the logs.

**Options:**

| Option | Example | When to use |
|---|---|---|
| Any (current) | `"*"` | Learning, dynamic home IP |
| Your IP only | `"1.2.3.4/32"` | If your IP is static |
| Corporate network | `"10.0.0.0/8"` | VPN/office |
| Azure Bastion | via portal | Prod without public SSH |
| JIT Access | via Azure Defender | Closes automatically |

For prod, either VPN + closed SSH, or Azure Bastion (SSH through the portal without opening port 22) is used.

---

## 13. How to Find the IP After `terraform apply`

From `outputs.tf`. After apply, Terraform outputs it automatically:

```
Outputs:

public_ip            = "20.50.123.45"
virtual_machine_name = "linux-vm-main"
resource_group       = "resource-group-terraform-azure-vm-dev"
ssh_command          = "ssh azureuser@20.50.123.45"
```

`20.50.123.45` in the documentation is an example, not a real IP. The real IP only appears after the VM is created. During `plan`, the `public_ip` field is empty — Azure has not yet assigned an address (because it's Dynamic).

---

## 14. Why Does `fmt -check` Come After `init` and Not Before?

```bash
terraform init          # 1
terraform fmt -check    # 2
terraform validate      # 3
```

`fmt` technically doesn't require `init` — it simply checks the formatting of text files. The practical reason for the order: in a CI pipeline, `init` is always the first step; checks follow. This is a standard convention, not a technical requirement.

`validate`, however, **requires** `init` — it checks not only syntax, but also the correctness of types and references, for which the downloaded providers are needed.

---

## 15. `tfstate` — When Is It Updated?

`terraform.tfstate` — a file that stores the **current state** of the infrastructure as Terraform knows it.

**Updated during:**
- `terraform apply` — created/changed resources → writes new state
- `terraform destroy` — deleted resources → clears the entry in state
- `terraform import` — adds a resource created outside of Terraform into state

**During `plan`** — state is only **read**, not written. Terraform compares: "what is in state" vs "what the code wants" vs "what is actually in Azure" → shows a diff.

**Important:** state is not updated in real time. If someone manually changed a resource in the Azure Portal — Terraform won't know about it until you run `terraform refresh` or the next `plan`.

---

## 16. Service Principal — What Is It?

**Service Principal (SP)** — a "technical account" in Azure for applications and automation.

**Analogy:** a regular Azure user is a person with a login and password. A Service Principal is a "robot user" for programs, which has no password (or has one, but we use OIDC).

**Why you can't use a personal account in CI:** GitHub Actions runs on someone else's server. You can't give it your login/password. An SP solves this — it has only the permissions you granted it (Contributor on the subscription), and it can be revoked at any time without affecting your account.

```
your account     = full access to all of Azure
Service Principal = only Contributor on one subscription
```

---

## 17. GitHub Actions — Workflow, What It Is, What Triggers It, and How It Works

### What a Workflow Is

**A workflow** is a file with instructions for GitHub Actions. It lives in the repository at the path:

```
.github/workflows/terraform-azure-vm.yml
```

This is a plain YAML file. You wrote it yourself — GitHub simply reads and executes it. Terraform doesn't know about this file and doesn't create it in any way. Terraform is a tool for Azure; the workflow is a tool for CI/CD automation.

### What's Inside a Workflow File

The file `.github/workflows/terraform-azure-vm.yml` consists of three parts:

**1. Triggers — when to run:**
```yaml
on:
  pull_request:               # when a PR touching infra/ is created
    paths: ["infra/**", ...]
  push:                       # when pushing to main touching infra/
    branches: ["main"]
    paths: ["infra/**", ...]
  workflow_dispatch:          # manually via a button in the GitHub UI
    inputs:
      action: apply/destroy
      environment: dev/prod
```

**2. Permissions — what the workflow can do:**
```yaml
permissions:
  id-token: write      # obtain an OIDC token for logging into Azure
  contents: read       # read repository files
  pull-requests: write # write comments on PRs
```

**3. Steps — what exactly is executed (in order):**
```yaml
steps:
  - Checkout repository       # download the repository code
  - Azure Login (OIDC)        # log into Azure without a password
  - Setup Terraform           # install terraform on the runner
  - Terraform Format Check    # terraform fmt -check
  - Terraform Init            # terraform init
  - Terraform Validate        # terraform validate
  - Terraform Plan            # terraform plan → saves tfplan
  - Comment Plan on PR        # if this is a PR — post a comment with the plan result
  - Terraform Apply           # if this is a push to main or workflow_dispatch apply
  - Terraform Destroy         # if this is workflow_dispatch destroy
```

### What Happens on Push to Main

```yaml
- name: Terraform Apply
  if: >
    github.event_name == 'push' ||
    (github.event_name == 'workflow_dispatch' && inputs.action == 'apply')
  run: terraform apply -input=false -auto-approve tfplan
```

On push to main, **all steps** run: fmt → init → validate → **plan** → **apply**. That means push to main = automatic infrastructure deployment. This is why in real projects, direct pushes to main are usually prohibited — only through a PR.

### What Happens on Pull Request

```yaml
- name: Comment Plan on PR
  if: github.event_name == 'pull_request'
```

On a PR, these steps run: fmt → init → validate → **plan** → **comment with the plan result**. Apply does not run. This is a "safe preview" of what will change.

### The Full Picture

```
Your laptop          GitHub                GitHub Actions runner     Azure
──────────────         ──────                ────────────────────      ─────
git push main    →    sees push      →    runs workflow          →   terraform apply
git push (PR)    →    sees PR        →    runs workflow          →   terraform plan (only)
UI button        →    workflow_dispatch →  runs workflow          →   apply or destroy
```

Your laptop only **initiates the event**. Terraform itself runs on GitHub's servers (Ubuntu runner), not on your machine.

### How GitHub Knows What to Run Depending on the Event

The `if:` conditions in each step are where the logic is defined:

| Step | `if:` condition | When it runs |
|---|---|---|
| Comment Plan | `github.event_name == 'pull_request'` | Only on PR |
| Apply | `github.event_name == 'push'` | On push to main |
| Apply | `inputs.action == 'apply'` | On workflow_dispatch with action=apply |
| Destroy | `inputs.action == 'destroy'` | On workflow_dispatch with action=destroy |

Plan runs **always** — on any event. Apply/destroy — only under the right conditions.

---

## 17a. How GitHub Actions Runs Terraform — Where Are the .tf Files Stored?

The key is in the first step of the workflow:

```yaml
steps:
  - name: Checkout repository   # ← THIS is the answer
    uses: actions/checkout@v4
```

**`actions/checkout@v4` downloads the entire repository to a temporary GitHub machine.**

What happens step by step:

```
1. GitHub spins up a clean Ubuntu machine (runner)
2. Checkout — copies the entire repository to that machine:
   runner/
   ├── infra/
   │   ├── main.tf
   │   ├── network.tf
   │   ├── compute.tf
   │   └── ...
3. Setup Terraform — installs terraform on the runner
4. terraform init/plan/apply — runs LOCALLY on the runner
   against these copied .tf files
5. Terraform creates resources in Azure via the Azure API
6. The runner shuts down, all files are deleted
```

**Visually:**
```
GitHub repo         Runner (temporary Ubuntu machine)      Azure
(stores .tf)  →  checkout → terraform apply  →  creates VM, VNet, NIC...
```

**Azure doesn't know about Terraform at all.** It simply receives API requests: "create a VM with these parameters", "create a VNet", "create a NIC" — and executes them. Terraform is the client that generates those requests.

`.tf` files are stored in the **GitHub repository**. They are never on Azure's servers.

---

## 17b. What Is Terraform Used For — Just VMs and Billing?

**No, Terraform is a universal tool for describing any infrastructure as code (IaC).** A VM is just one example.

Terraform works through providers, and there are hundreds of them. What can be described:

**In Azure (azurerm):**
- VMs, containers, Kubernetes clusters (AKS)
- Databases (PostgreSQL, MySQL, CosmosDB)
- Networks, DNS, Load Balancer, VPN
- Storage, Key Vault, App Service
- Access rights (IAM), policies

**In other clouds:**
- AWS (EC2, S3, RDS, Lambda...)
- GCP (Compute Engine, GKE, BigQuery...)

**Outside of clouds:**
- GitHub (repositories, secrets, teams)
- Cloudflare (DNS records)
- Kubernetes (deployments, services)
- Databases (creating tables, users)
- Datadog, PagerDuty (monitoring)

**The main idea:** if something has an API — there is most likely a Terraform provider for it. Everything is described in one language (HCL), stored in git, and has plan/apply/destroy.

---

## 18. Why Are Azure Parameters Configured in the GitHub Repository?

```
GitHub Secrets:
  AZURE_CLIENT_ID       ← ID of the Service Principal in Azure
  AZURE_TENANT_ID       ← ID of your Azure tenant
  AZURE_SUBSCRIPTION_ID ← ID of the subscription
```

The GitHub Actions workflow contains `az login` and `terraform apply` steps. To execute them, Azure credentials are needed. These credentials are stored in GitHub Secrets (encrypted) and passed into the workflow as environment variables.

**The alternative** — storing them directly in the workflow file — is never acceptable, as the file is public.

**The connection:** Azure is configured to "trust tokens from this GitHub repository" (Federated Credential). GitHub stores the application ID (not a password). When the workflow runs, GitHub generates a token → Azure accepts it → access is granted.

---

## 19. Pull Request — How Does It Trigger Terraform Plan?

**A PR can be created in two ways:**
1. Through the GitHub interface: the "New pull request" button on github.com
2. Through the `gh` CLI: `gh pr create --base main` from the terminal
3. Through `git push` + GitHub offers to create a PR

**How Terraform plan is triggered automatically:**

```yaml
# .github/workflows/terraform-azure-vm.yml
on:
  pull_request:
    paths:
      - 'infra/**'
```

When a PR touching files in `infra/` is created → GitHub sees a `pull_request` event → runs the workflow → the workflow runs `terraform plan` → the result is posted as a comment on the PR.

**Important:** Terraform runs on GitHub's servers, not locally. Your local Terraform is not involved.

---

## 20. Options for Running Terraform Non-Locally

Section 10 in setup-tutorial.md — "Local run (optional)" — the primary method is GitHub Actions.

| Where it runs | How |
|---|---|
| GitHub Actions (primary) | push / PR / workflow_dispatch |
| Locally (optional) | `terraform apply` from the terminal |
| Azure DevOps Pipelines | alternative to GitHub Actions |
| Terraform Cloud | SaaS from HashiCorp, stores state in the cloud |
| GitLab CI | if you use GitLab |

In our project, the primary method is GitHub Actions. Local runs are only for debugging, when you don't want to push just to run a check.

---

## 21. `outputs.tf` — What It's For and How It Works

`outputs.tf` is a **separate file**, not part of `apply`. Terraform doesn't execute it as a command — it simply describes what to show after apply.

```hcl
# outputs.tf
output "public_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.public_ip.ip_address}"
}
```

**How it works — three points:**

**1. After `terraform apply`** Terraform automatically reads all `output` blocks and prints them to the terminal:
```
Outputs:

public_ip            = "20.50.123.45"
virtual_machine_name = "linux-vm-main"
resource_group       = "resource-group-terraform-azure-vm-dev"
ssh_command          = "ssh azureuser@20.50.123.45"
```
No separate command is needed — this happens automatically.

**2. Values are taken from the real created resources** — not from variables or tfvars. `azurerm_public_ip.public_ip.ip_address` is an attribute of an already-created resource that Azure returned after creation. That is why this field is empty during `plan` (the resource hasn't been created yet).

**3. Saved in tfstate** — can be retrieved later without running apply again:
```bash
# Show all outputs
terraform output

# Get a specific one (useful in scripts)
terraform output -raw public_ip
# → 20.50.123.45
```

**In GitHub Actions**, the workflow prints these values in the logs after apply — you see the ready-to-use `ssh_command` string directly in the GitHub interface.

**Can you do without outputs.tf?** Yes. The infrastructure will be created without it. Outputs are a convenience, not a requirement. But without them you'll have to manually look up the IP in the Azure Portal.
