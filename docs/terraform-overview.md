# Terraform Infrastructure — Разбор по файлам

Эта документация объясняет, что делает каждый `.tf` файл в папке `infra/`, как они связаны между собой и какие ресурсы создаются в Azure.

---

## Что создаётся в итоге

```
Azure Resource Group
└── Virtual Network (10.10.0.0/16)
    └── Subnet (10.10.1.0/24)
         └── Network Interface (NIC)
              ├── Dynamic Private IP
              ├── Dynamic Public IP
              └── Network Security Group (NSG)
                   └── Rule: Allow SSH (port 22)
└── Linux VM (Ubuntu 22.04 LTS)
     └── Auto-shutdown schedule (ежедневно по расписанию)
```

---

## Структура файлов

```
infra/
├── providers.tf      # Версия Terraform и провайдер Azure
├── variables.tf      # Объявление всех входных переменных
├── main.tf           # Resource Group
├── network.tf        # Сеть: VNet, Subnet, Public IP, NIC
├── security.tf       # Файрвол: NSG + правила
├── compute.tf        # VM + расписание автовыключения
├── outputs.tf        # Что вывести после apply
└── vars/
    ├── dev.tfvars    # Значения переменных для dev
    └── prod.tfvars   # Значения переменных для prod
```

---

## providers.tf — провайдер Azure

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

**Что делает:**
- Фиксирует минимальную версию Terraform (>= 1.6.0) — защита от несовместимостей.
- Подключает провайдер `azurerm` версии ~3.100 (обновления патчей разрешены, мажорный апгрейд — нет).
- `features {}` — обязательный блок для azurerm, без него провайдер не инициализируется.

**Аналогия:** это как `import` в коде — без него Terraform не знает, с каким облаком работать.

---

## variables.tf — входные параметры

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

**Что делает:** объявляет параметры конфигурации без значений — только типы и описания.

| Переменная | Тип | Назначение |
|---|---|---|
| `location` | string | Регион Azure (northeurope, westeurope) |
| `resource_group_name` | string | Имя Resource Group |
| `virtual_machine_size` | string | Тип VM (Standard_B1s, Standard_B1ls) |
| `admin_username` | string | Имя пользователя в VM |
| `ssh_public_key` | string | Публичный SSH-ключ для доступа |
| `tags` | map(string) | Теги на все ресурсы |
| `auto_shutdown_time` | string | Время выключения в формате HHmm (2200 = 22:00) |
| `auto_shutdown_timezone` | string | Таймзона для расписания (Windows timezone name) |

**Важно про `ssh_public_key`:** помечена `sensitive = true`. Значение передаётся только через переменную окружения и **никогда не хранится в tfvars-файле**:
```bash
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
```

---

## vars/dev.tfvars и vars/prod.tfvars — значения по окружениям

**dev.tfvars:**
```hcl
location             = "northeurope"
resource_group_name  = "resource-group-terraform-azure-vm-dev"
virtual_machine_size = "Standard_B1s"
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
```

**Разница между окружениями:**

| Параметр | dev | prod |
|---|---|---|
| location | northeurope | westeurope |
| resource_group_name | ...-dev | ...-prod |
| auto_shutdown_time | 22:00 | 23:00 |

Запуск с нужным окружением:
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

**Что делает:** создаёт **контейнер** для всех ресурсов в Azure.

Resource Group — это логическое объединение ресурсов. Удалив группу, ты удаляешь всё внутри неё разом. Все остальные ресурсы ссылаются на эту группу через `azurerm_resource_group.resource_group.name`.

---

## network.tf — сетевая инфраструктура

### Virtual Network

```hcl
resource "azurerm_virtual_network" "virtual_network" {
  name          = "virtual-network-main"
  address_space = ["10.10.0.0/16"]
  ...
}
```

**VNet** — виртуальная приватная сеть в Azure. `10.10.0.0/16` даёт 65 534 IP-адреса для внутренних ресурсов.

### Subnet

```hcl
resource "azurerm_subnet" "subnet" {
  name             = "subnet-main"
  address_prefixes = ["10.10.1.0/24"]
  ...
}
```

**Subnet** — подсеть внутри VNet. `10.10.1.0/24` = 254 адреса. VM получит приватный IP из этого диапазона.

### Public IP

```hcl
resource "azurerm_public_ip" "public_ip" {
  allocation_method = "Dynamic"
  ...
}
```

**Dynamic** — Azure назначает IP при запуске VM. IP известен только после `apply` (именно поэтому `output "public_ip"` пуст во время `plan`).

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

**NIC** — виртуальная сетевая карта VM. Связывает VM с подсетью и публичным IP.

**Цепочка зависимостей:**
```
Resource Group → VNet → Subnet → NIC → VM
                              ↗
             Public IP ──────
```

Terraform автоматически определяет порядок создания по этим ссылкам.

---

## security.tf — файрвол

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

**Что делает:**
- Создаёт NSG (Network Security Group) — аналог файрвола/iptables.
- Открывает **только порт 22 (SSH)** для входящего трафика из любого источника (`*`).
- Привязывает NSG к NIC — без этого правила не применяются.

**Параметры правила:**

| Параметр | Значение | Смысл |
|---|---|---|
| `priority` | 1001 | Чем меньше число, тем выше приоритет (100–4096) |
| `direction` | Inbound | Входящий трафик |
| `access` | Allow | Разрешить |
| `source_address_prefix` | `*` | С любого IP (для прода лучше ограничить) |

---

## compute.tf — виртуальная машина

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

**Ключевые параметры:**

| Параметр | Значение | Почему |
|---|---|---|
| `disable_password_authentication` | true | Только SSH-ключ — безопаснее пароля |
| `storage_account_type` | Standard_LRS | HDD, дешевле чем Premium_LRS (SSD) |
| `sku` | 22_04-lts | Ubuntu 22.04 LTS — стабильный, поддерживается до 2027 |
| `version` | latest | Всегда последний патч образа |

**Образ:** `Canonical / 0001-com-ubuntu-server-jammy / 22_04-lts` — это полный идентификатор образа Ubuntu 22.04 в Azure Marketplace.

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

**Что делает:** ежедневно выключает VM в заданное время по расписанию.

- dev: выключение в 22:00 (Israel Standard Time)
- prod: выключение в 23:00 (Israel Standard Time)
- Не по событию (не по ошибке, не по активности) — именно **ежедневное расписание**.
- Экономит бюджет/квоты free-tier, не давая VM работать круглосуточно.

---

## outputs.tf — вывод после apply

```hcl
output "public_ip"         { value = azurerm_public_ip.public_ip.ip_address }
output "virtual_machine_name" { value = azurerm_linux_virtual_machine.virtual_machine.name }
output "resource_group"    { value = azurerm_resource_group.resource_group.name }
output "ssh_command"        { value = "ssh ${var.admin_username}@${azurerm_public_ip.public_ip.ip_address}" }
```

После `terraform apply` в терминале появится:

```
Outputs:
public_ip            = "20.50.123.45"
virtual_machine_name = "linux-vm-main"
resource_group       = "resource-group-terraform-azure-vm-dev"
ssh_command          = "ssh azureuser@20.50.123.45"
```

**Важно:** `public_ip` пуст во время `plan` (Dynamic IP назначается только при создании).

---

## Как Terraform понимает порядок создания ресурсов

Terraform читает ссылки между ресурсами и строит граф зависимостей автоматически:

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

Независимые ресурсы (например VNet и Public IP) создаются параллельно.

---

## Основной workflow

```bash
cd infra

# 1. Передать SSH-ключ (никогда не в tfvars!)
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"

# 2. Инициализировать (скачать провайдер)
terraform init

# 3. Проверить форматирование
terraform fmt -check -recursive

# 4. Проверить синтаксис
terraform validate

# 5. Посмотреть что создастся (без реальных изменений)
terraform plan -var-file=vars/dev.tfvars

# 6. Создать инфраструктуру
terraform apply -var-file=vars/dev.tfvars

# 7. Удалить всё (когда не нужно)
terraform destroy -var-file=vars/dev.tfvars
```

---

## Ключевые концепции Terraform

| Концепция | Описание |
|---|---|
| `resource` | Создаёт реальный объект в Azure |
| `variable` | Входной параметр (объявление без значения) |
| `var.xxx` | Обращение к переменной по имени |
| `output` | Что вывести пользователю после apply |
| `resource_type.name.attribute` | Ссылка на атрибут другого ресурса |
| `tfvars` | Файл со значениями переменных для конкретного окружения |
| `terraform.tfstate` | State-файл: что Terraform знает о созданных ресурсах |
| `sensitive = true` | Значение не отображается в логах и терминале |

---

## Fallback при SkuNotAvailable

Если Azure возвращает `SkuNotAvailable`, это проблема capacity в регионе, не ошибка Terraform.

**Регионы для попытки (по убыванию доступности):**
```
northeurope → westeurope → uksouth → canadacentral → swedencentral
```

**Размеры VM (free-tier eligible):**
```
Standard_B1s   (1 vCPU, 1 GB)   ← default
Standard_B1ls  (1 vCPU, 0.5 GB) ← часто доступнее
Standard_B1ms  (1 vCPU, 2 GB)
```

Через GitHub Actions можно передать другой регион/размер без правки кода — через `workflow_dispatch` inputs.
