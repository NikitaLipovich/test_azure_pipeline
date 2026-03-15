Let me answer point by point (and **correct the terminology**): in Azure "free tier" refers to a **VM**, not a "container". Containers are ACI/AKS, and that's a different assignment. Your task is: **a VM via Terraform + GitHub Actions**.

Below:

1. answers to all questions 1–17,
2. a plan for splitting the task and minimal verification (for point 7),
3. "not a capacity guarantee" in plain words,
4. what `vm_size` is and why it exists.

At the end I'll give **links to the docs** (I'll put them in a code block so the interface displays them correctly).

---

## 1) "type of container?" — this is not a container

This is a **Virtual Machine** (Linux VM). "Free tier B1s" is a **VM size** (SKU), for example `Standard_B1s`.

---

## 2) Workflow: fmt/validate/plan, merge → apply

The logic here is:

* On a **Pull Request**: run checks and **`terraform plan`** (to see what will be created/changed).
* On **merge to main**: run **`terraform apply`** (i.e., actually create the resources).

Technically this is done with GitHub Actions triggers:

* `on: pull_request` → fmt/validate/plan
* `on: push` (branches: main) → apply
  This is the standard pattern for IaC. GitHub writes about "events" here ([GitHub Docs][1]).

---

## 3) What is "SG network"? What are tags?

### SG network

In AWS: "Security Group". In Azure the equivalent is called an **NSG (Network Security Group)**.

* **VNet** = a virtual network (like a "virtual router/network")
* **Subnet** = a sub-network inside a VNet
* **NSG** = inbound/outbound firewall rules (e.g., allow SSH on port 22)

In my Terraform:

* `azurerm_virtual_network` — VNet
* `azurerm_subnet` — subnet
* `azurerm_network_security_group` — NSG
* `azurerm_network_interface_security_group_association` — "attach NSG to NIC"

### Tags

**Tags** = "key=value" labels on Azure resources (e.g., `project=...`, `owner=...`).
Why:

* filtering in the portal,
* cost reports,
* policies (Azure Policy),
* automation (e.g., shut down everything with tag=dev).

---

## 4) Auto shutdown — "when which event happened?"

Auto shutdown here is **not event-based**, it is **schedule-based** (for example, every day at 22:00).
This is needed so the VM doesn't run at night and burn through the budget/quotas.

---

## 5) Auth GitHub → Azure (OIDC) and "in which sequence"

OIDC = a way to give GitHub Actions a temporary token in Azure **without a password and without a client secret**.

Sequence of steps:

1. **In Azure**: create an App Registration (Microsoft Entra ID).
2. Create a **Federated credential** (trust for the GitHub repo/branch/environment).
3. Grant that app permissions (a role) on the subscription or resource group (usually **Contributor** on the RG).
4. **In the GitHub repo**: add non-password secrets:

   * `AZURE_CLIENT_ID`
   * `AZURE_TENANT_ID`
   * `AZURE_SUBSCRIPTION_ID`
     (these are just identifiers, not secret-passwords)
5. In the workflow, add an `azure/login@v2` step with these IDs.

Documentation for exactly this scenario: GitHub guide ([GitHub Docs][2]) and Microsoft Learn ([Microsoft Learn][3]). Also the `azure/login` README ([GitHub][4]).

**Where is "manual accept"?**
Manual approval is usually done via **GitHub Environments**:

* a job has `environment: azure-prod`
* in the environment settings you set "Required reviewers"
  Then the **apply job** will stop and wait for approval in the GitHub UI. This is a separate "security gate", not in Azure.

---

## 6) Why "Manual terraform destroy" to Save Money

Terraform creates resources. If you created a VM and forgot about it — it keeps running (and may cost money/consume limits).

**`terraform destroy`** deletes everything Terraform created (as recorded in state).
Why "manual":

* so you don't accidentally tear down prod,
* so you control the moment of deletion,
* in a learning assignment it's convenient: "created → verified → deleted".

---

## 7) "fallback by size and length" — this is not about containers, and not about length

I phrased that poorly: it's about **fallback by VM size and region**.

* **size** = the type/power of the VM (`Standard_B1s`, `Standard_B1ls`, …)
* **region** = where we're creating it (`eastus`, `northeurope`, …)

If Azure responds with `SkuNotAvailable`, it means **there is no capacity/availability for this size in this region right now** — then try a different region or a different size.

There is no "container length" here.

---

## 8) "check and handling" — what this is about

It's about the fact that the DevOps approach is not just "well, it failed, whatever", but:

* documenting the cause (`SkuNotAvailable`),
* adding the ability to change `location` and `vm_size` **without editing code** (for example via inputs in workflow_dispatch),
* adding a list of "recommended regions/sizes" to the README.

This looks like "engineering handling of an edge case".

---

## 9) How Spot Differs from Free Tier

* **Free tier**: about a **discount/credit** (e.g., "750 hours of B1s" may be free).
* **Spot VM**: about the fact that Azure can **reclaim the VM at any moment** if resources are needed by others (the VM is "preemptible"). Usually cheaper, but less reliable.

Spot sometimes solves the price/capacity problem, but adds the risk of "the VM being shut down".

---

## 10) Auto Shutdown — "by which event"

Again: **by schedule**, not by an event.
An event could be "push to repo" or "night has fallen", but in Azure the shutdown schedule is specifically a **daily recurrence**.

---

## 11) Why the Workflow Lives in `.github/workflows/*.yml` and What Terraform Has to Do with It

GitHub Actions works like this: a workflow is a YAML file in `.github/workflows/`. GitHub reads it and runs jobs/steps on a runner.

Terraform here is simply a command that the runner executes (`terraform init/plan/apply`).
Documentation on workflows: ([GitHub Docs][5]).

---

## 12) Documentation on OIDC

* GitHub: OIDC for Azure ([GitHub Docs][2])
* Microsoft Learn: Azure Login action with OIDC ([Microsoft Learn][3])
* `azure/login` README ([GitHub][4])

---

## 13) "plan on PR" — What Is This

This is the setting "run `terraform plan` on the pull_request event".

Why:

* to see changes before merging,
* to catch errors before apply,
* it's like a "preview of the infrastructure".

---

## 14) "apply" — What Is It and How Is It Configured

`terraform apply` is the command that **actually creates/changes resources in Azure**.

Usually:

* PR → plan only
* main → apply (after review + merge)
  And yes: you can set up "environment approval" so that apply waits for manual approval in the GitHub UI.

This is not a separate file, it is a **command** in a workflow step.

---

## 15) "destroy manual" — What Should It Destroy

Everything Terraform created and recorded in state:

* resource group,
* vnet/subnet,
* NSG,
* public ip,
* NIC,
* VM,
* schedule.

If state is stored correctly, destroy will be clean.

---

## 16) "tags on resources" — What Are "Resources" and Why Do They Need Tags

A resource = any object in Azure (VM, network, IP, disks, NSG, RG…).

Tags are needed for:

* organization,
* searching,
* billing/reports,
* policies/automation.

---

## 17) Auto-shutdown on a Schedule — Yes, That's Good Practice

Yes, worth it. In learning tasks — an absolute must.

---

# Now About Terraform: What "Every Line" Means and Why It's That Way

A full line-by-line breakdown of every file would be very long, so I'll go **block by block**: what each resource does + why those parameters, and where the docs are.

### `terraform { required_providers ... }`

Pins the AzureRM provider version → stable builds.
Docs for resources/provider: ([registry.terraform.io][6])

### `provider "azurerm" { features {} }`

Enables the AzureRM provider; `features {}` is required (that's how the provider is designed).

### `azurerm_resource_group`

RG — a container for all resources. Convenient to delete in one go and assign permissions.

### `azurerm_virtual_network` + `azurerm_subnet`

A minimal network for the VM to connect to.

Why those addresses: just a private range so it doesn't conflict with home networks.

### `azurerm_network_security_group` + rule SSH 22

NSG allows SSH; otherwise you can't connect.

Why source `*` — this is "simplified for a demo". In a real project, it's better to restrict by IP.

### `azurerm_public_ip`

A public IP so the VM is accessible from the internet via SSH. Allocation Dynamic — simpler/cheaper.

### `azurerm_network_interface`

The NIC — the VM's network card. We assign it a subnet + public IP.

### `azurerm_network_interface_security_group_association`

Attaches the NSG to the NIC (so the firewall actually takes effect).

### `azurerm_linux_virtual_machine`

The VM itself:

* `size = var.vm_size` — so you can change the size without editing the resource.
* `admin_ssh_key` — SSH key login (better than a password).
* `os_disk` Standard_LRS — the most basic type.
* `source_image_reference` Ubuntu 22.04 LTS — a stable default.

Docs for this resource: ([registry.terraform.io][6])

### `azurerm_dev_test_global_vm_shutdown_schedule`

Shuts down the VM daily at a specified time/timezone.
Docs: ([registry.terraform.io][7])

---

# Point 7: Plan to "Minimally Verify That It Works" and Split the Task into Sub-tasks

Here is a "debugging" plan (follow the steps strictly):

## Step A — Terraform Locally Without GitHub Actions (Fastest Check)

1. Create `infra/` and put the Terraform files inside.
2. Locally:

   * `terraform fmt`
   * `terraform init`
   * `terraform validate`
   * `terraform plan -var location=northeurope -var vm_size=Standard_B1s -var ssh_public_key="..."`

Goal: verify that **the code is actually valid**.

## Step B — Apply Locally (to Separate Azure Problems from GitHub)

3. `terraform apply` (manually)

* If `SkuNotAvailable` occurs: change `location` and `vm_size` and try again.
* Write down 2–3 working combinations of "region + size" (if you find them).

Goal: confirm that **Azure actually lets you create a VM**.

## Step C — GitHub Actions With Only fmt/validate/plan

4. Add a workflow that only does `fmt/validate/plan` on PRs, but no apply.

Goal: confirm that the pipeline runs and can do `terraform plan`.

## Step D — OIDC

5. Set up OIDC and verify that the `azure/login` step passes and `terraform init/plan` works in Actions.

Goal: confirm that **authentication** is correct.

## Step E — Apply on Main with Environment Approval

6. Enable apply on `push main` + environment reviewers.
7. Create a PR → merge → approve environment → apply.

Goal: full end-to-end.

## Step F — Manual Destroy

8. `workflow_dispatch action=destroy` (or `terraform destroy` locally).

Goal: clean-up and demonstrating "cost control".

---

## 8.3 "not a capacity guarantee" — Explanation

"Free tier / eligible VM size" = **about pricing**, but **not a promise** that a specific region will have free capacity for it right now.

That is, Azure can say:

* "yes, B1s qualifies for free-tier billing"
* but at the same time:
* "there is no capacity for B1s in East US for your subscription" → `SkuNotAvailable`

---

## Why `vm_size` Is a Variable

So you can:

* quickly change the size without editing the VM resource,
* pass it from workflow inputs,
* implement fallback: "try B1s; if unavailable — try B1ls".

This is a normal engineering "knob" for debugging and real operations.

---

# Documentation Links

(as requested — here they are)

```text
GitHub Actions: About workflows
https://docs.github.com/actions/using-workflows/about-workflows

GitHub Actions: Workflow syntax
https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions

GitHub Actions: Events that trigger workflows
https://docs.github.com/actions/using-workflows/events-that-trigger-workflows

GitHub: Configure OIDC in Azure
https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure

Microsoft Learn: Use Azure Login action with OIDC
https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect

Azure/login action README
https://github.com/Azure/login

Terraform AzureRM: azurerm_linux_virtual_machine
https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine

Terraform AzureRM: azurerm_dev_test_global_vm_shutdown_schedule
https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_test_global_vm_shutdown_schedule.html

Microsoft Learn: Terraform Linux VM quickstart
https://learn.microsoft.com/azure/virtual-machines/linux/quick-create-terraform
```

---

If you want — in the next message I can:

* rewrite Terraform so that **the SSH rule** is restricted to your IP (more secure),
* add a **remote backend for state** (Azure Storage + state locking — also "DevOps"),
* and suggest a "minimal version" of Terraform (VM without auto-shutdown), so you can first bring up the VM and then add complexity.

[1]: https://docs.github.com/actions/using-workflows/events-that-trigger-workflows?utm_source=chatgpt.com "Events that trigger workflows"
[2]: https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure?utm_source=chatgpt.com "Configuring OpenID Connect in Azure"
[3]: https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect?utm_source=chatgpt.com "Use the Azure Login action with OpenID Connect"
[4]: https://github.com/Azure/login?utm_source=chatgpt.com "Azure/login: Connect to Azure"
[5]: https://docs.github.com/actions/using-workflows/about-workflows?utm_source=chatgpt.com "Workflows - GitHub Docs"
[6]: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine?utm_source=chatgpt.com "azurerm_linux_virtual_machine | hashicorp/azurerm | Terraform"
[7]: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_test_global_vm_shutdown_schedule.html?utm_source=chatgpt.com "azurerm_dev_test_global_vm_s..."
