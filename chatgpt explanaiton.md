Ок, разложу “по-человечески”: что именно от тебя хотят, почему у подруги упало, и что делать дальше (и дам готовые **terraform + GitHub Actions** шаблоны).

---

## 1) Что вообще значит задание

**“Build a GH actions workflow to provision a free tier VM in azure using terraform”** = в репозитории должен быть:

1. **Terraform код**, который создаёт *минимальную Linux VM* в Azure (желательно free tier B1s), плюс базовая сеть/SG/публичный IP, теги, (опционально) авто-выключение.
2. **GitHub Actions workflow**, который по push/PR делает:

   * `terraform fmt/validate`
   * `terraform plan`
   * и по ручному подтверждению (или по merge в main) делает `terraform apply`
3. **Аутентификация GitHub → Azure** (лучше через **OIDC**, без паролей/секретов).
4. Желательно: `terraform destroy` (ручной), чтобы не тратить лимиты/деньги.

**Смысл для DevOps**: показать, что ты умеешь сделать “Infrastructure as Code” + CI/CD pipeline + безопасный доступ к облаку.

---

## 2) Почему у подруги `SkuNotAvailable` на Standard_B1s

Это не “ошибка терраформа”. Это ответ Azure: **в выбранном регионе сейчас нет мощности/квоты/доступности для этого размера VM** для твоей подписки.

Основные причины:

* **Capacity**: B-series супер популярные → в регионе “нет свободных слотов” прямо сейчас.
* **SKU restricted per subscription/region**: иногда подписке “Free/Trial/Student” не дают конкретный SKU в конкретном регионе (или дают с ограничениями).
* **Quota = 0 / очень низкая**: бывает, что лимит по vCPU в регионе не выдан/исчерпан (особенно на новых/триальных аккаунтах).

Важно: “Free tier 750 hours B1s” **не означает “B1s всегда доступен в East US”**. Это только про стоимость, а не про наличие capacity.

---

## 3) Что делать, если B1s недоступен (реальные варианты)

### Вариант A (самый практичный для задания): сделать fallback по размерам + выбрать “тихий” регион

1. Пробовать регионы, где чаще есть capacity: `northeurope`, `westeurope`, `uksouth`, `canadacentral`, иногда `swedencentral` и т.п.
2. Пробовать альтернативные размеры, которые часто проходят:

   * `Standard_B1ls` (иногда доступнее)
   * `Standard_B1ms`
   * `Standard_A1_v2` / `Standard_A1m_v2` (иногда “старые” доступны, но не всегда free-tier)

👉 Для задания обычно достаточно показать pipeline + terraform. Даже если B1s не поднялся, **но ты показал fallback/проверку/обработку — это выглядит очень по-DevOps**.

### Вариант B: проверить квоты и попросить quota increase

* Проверить vCPU usage/quota в регионе и запросить увеличение (через Azure Portal → Quotas).
  Минус: может занять время/не одобрят сразу.

### Вариант C: использовать Spot (не всегда подходит)

Spot может быть доступнее по capacity, но:

* VM может быть выбита
* free-tier “идея” теряется
  Обычно для простого задания не надо.

### Вариант D: согласовать с проверяющим “любая дешёвая VM” вместо strict free-tier

Если они хотят именно “VM вообще”, а free-tier — желаемо, то можно взять минимальный размер, который доступен (например B2s) и **сразу включить auto-shutdown**, чтобы не сжечь бюджет.

---

## 4) Что именно требуется от тебя как deliverables (чеклист)

Минимум, который выглядит “правильно”:

* ✅ `infra/` (или корень репо) с terraform файлами
* ✅ `.github/workflows/terraform.yml`
* ✅ OIDC настроен: GitHub → Azure login без client secret
* ✅ `plan` работает на PR
* ✅ `apply` либо ручной (workflow_dispatch), либо только на main + environment approval
* ✅ `destroy` manual
* ✅ теги на ресурсы
* ✅ (опционально) auto-shutdown schedule

---

## 5) Готовый пример: Terraform (VM + сеть + авто-shutdown)

Структура:

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

## 6) GitHub Actions workflow (OIDC + plan/apply/destroy)

Файл: `.github/workflows/terraform-azure-vm.yml`

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

**Что важно:**

* `permissions: id-token: write` обязательно для OIDC.
* Секреты нужны **без пароля**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, и `SSH_PUBLIC_KEY`.
* `environment: azure-prod` — удобно поставить “Required reviewers” в GitHub Environments, чтобы apply был “с подтверждением” (очень devops-но).

---

## 7) Как настроить OIDC (коротко, что тебе реально сделать)

Тебе нужен **App Registration / Service Principal** в Azure AD + “Federated credential” для GitHub.

Высокоуровнево:

1. Создаёшь App Registration
2. Даёшь ему роль на subscription/resource group: например **Contributor** на нужный RG/Subscription
3. В App → Federated credentials добавляешь доверие к GitHub repo (issuer `https://token.actions.githubusercontent.com`, subject вида `repo:ORG/REPO:environment:azure-prod` или `repo:ORG/REPO:ref:refs/heads/main`)
4. В GitHub repo settings → Secrets and variables:

   * `AZURE_CLIENT_ID`
   * `AZURE_TENANT_ID`
   * `AZURE_SUBSCRIPTION_ID`
   * `SSH_PUBLIC_KEY` (обычный публичный ключ `ssh-ed25519 ...`)

---

## 8) Как “красиво” закрыть проблему `SkuNotAvailable` в твоём решении

Чтобы выглядело профессионально, сделай так:

1. В workflow `workflow_dispatch` inputs уже есть `location` и `vm_size` → ты можешь **перезапускать apply** с другими значениями без правки кода.
2. В README напиши:

   * “Если Standard_B1s недоступен в регионе, попробуйте `Standard_B1ls` или другой регион (northeurope/westeurope).”
3. (Опционально) Добавь список “fallback sizes” и объяснение, что free-tier = billing benefit, не capacity guarantee.

Если хочешь прям “вау”: можно сделать `vm_size` как список и пробовать по очереди через matrix, но для задания это уже перебор.

---

## 9) Что сказать/написать проверяющему (по сути)

Текст смыслом:

* “Я настроил OIDC GitHub→Azure, pipeline plan/apply/destroy, VM с тэгами и auto-shutdown.”
* “Apply иногда падает на `SkuNotAvailable` из-за региональной capacity для B1s на free subscription.”
* “Я добавил возможность выбирать region/size через workflow_dispatch и описал fallback варианты.”

---

Если ты скинешь **требования задания word-в-word** (или скрин) и скажешь **репо private/public + как называется environment**, я подгоню YAML под их ожидания (например: apply только после manual approval, отдельные jobs, backend state, naming conventions).
