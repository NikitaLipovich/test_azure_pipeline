# Ответы на вопросы по Terraform и Azure

---

## 1. VNet / Subnet / NIC — что это и зачем

Думай о сети в Azure как о физической корпоративной сети, только виртуальной.

**VNet (Virtual Network)** = твоя частная сеть в облаке. Изолированное пространство, внутри которого ресурсы могут общаться между собой. Снаружи ничего не видит, пока сам не откроешь.

**Subnet (подсеть)** = сегмент внутри VNet. Зачем делить? Чтобы разграничить ресурсы: базы данных в одной подсети, веб-серверы в другой. У каждой подсети свои правила безопасности. У нас одна VM — одна подсеть.

**NIC (Network Interface Card)** = виртуальная сетевая карта. Именно NIC "вставляется" в VM и говорит: "я нахожусь в такой-то подсети, у меня такой-то приватный IP, и вот мой публичный IP". VM без NIC = компьютер без сетевой карты.

**Аналогия:**
```
VNet     = здание с внутренней сетью
Subnet   = этаж в этом здании
NIC      = сетевой разъём в стене, к которому подключается компьютер (VM)
Public IP = номер телефона, по которому можно позвонить снаружи
```

**О чём думать как разработчик при настройке:**
- Выбери адресное пространство VNet с запасом (`/16` = 65k адресов — более чем достаточно)
- Подсети не должны пересекаться между собой
- NIC должна быть в той же Resource Group и регионе что и VM
- NSG (файрвол) привязывается к NIC или к подсети — у нас привязан к NIC

---

## 2. Блок `features {}`

```hcl
provider "azurerm" {
  features {}
}
```

Это **обязательный пустой блок** — требование провайдера `azurerm`. Без него Terraform выдаст ошибку при `init`.

Почему он вообще существует? Внутрь `features {}` можно передавать опциональные настройки поведения провайдера, например:

```hcl
features {
  virtual_machine {
    delete_os_disk_on_deletion = true  # удалять диск при удалении VM
  }
  key_vault {
    purge_soft_delete_on_destroy = true
  }
}
```

У нас он пустой — используются дефолты. Но передать его обязательно.

---

## 3. Переменные в `variables.tf` — создаёт ли Azure ресурс автоматически?

**Нет. `variables.tf` — это только объявление параметров, Azure ничего не создаёт.**

Разберём на примере `resource_group_name`:

```hcl
# variables.tf — только ОБЪЯВЛЯЕТ что переменная существует
variable "resource_group_name" {
  type = string
}

# dev.tfvars — задаёт ЗНАЧЕНИЕ
resource_group_name = "resource-group-terraform-azure-vm-dev"

# main.tf — вот здесь Azure СОЗДАЁТ ресурс
resource "azurerm_resource_group" "resource_group" {
  name = var.resource_group_name  # берёт значение из переменной
}
```

Цепочка: `variables.tf` (объявление) → `dev.tfvars` (значение) → `main.tf` (создание в Azure).

**Важно:** если переменная объявлена, но нигде не используется в `resource "..."` — в Azure ничего не создастся.

---

## 4. `ssh_public_key` — почему `sensitive = true`, для чего и как настроить

```hcl
variable "ssh_public_key" {
  type      = string
  sensitive = true
}
```

**`sensitive = true` — это не `true` как значение переменной.** Это атрибут объявления, который говорит Terraform: "не показывай это значение в логах и терминале". Само значение — это содержимое публичного SSH-ключа.

**Для чего:** при `disable_password_authentication = true` в VM пароль отключён, войти можно только по SSH-ключу. Публичный ключ загружается в VM (`~/.ssh/authorized_keys`), а приватный остаётся у тебя локально.

**Это для Azure** (не для GitHub). Нужен чтобы войти на VM по SSH.

**Как настроить на Windows PowerShell:**

```powershell
# Шаг 1: Сгенерировать ключ (один раз)
ssh-keygen -t ed25519 -C "azure-vm" -f $HOME\.ssh\azure_vm_key
# Создаст два файла:
# ~/.ssh/azure_vm_key     — приватный (только у тебя)
# ~/.ssh/azure_vm_key.pub — публичный (загружается в Azure/GitHub)

# Шаг 2: Установить переменную окружения в PowerShell
$env:TF_VAR_ssh_public_key = Get-Content "$HOME\.ssh\azure_vm_key.pub" -Raw

# Проверить что установилась
echo $env:TF_VAR_ssh_public_key
```

---

## 5. Переменные окружения в Windows PowerShell

**Для текущей сессии** (временно, пропадёт при закрытии):
```powershell
$env:TF_VAR_ssh_public_key = Get-Content "$HOME\.ssh\azure_vm_key.pub" -Raw
```

**Постоянно для текущего пользователя:**
```powershell
[System.Environment]::SetEnvironmentVariable(
  "TF_VAR_ssh_public_key",
  (Get-Content "$HOME\.ssh\azure_vm_key.pub" -Raw),
  "User"
)
```

После этого перезапусти PowerShell — переменная будет доступна всегда.

**Почему именно `TF_VAR_`?** Terraform автоматически читает любую переменную окружения с префиксом `TF_VAR_` и маппит её на одноимённую переменную в Terraform. `TF_VAR_ssh_public_key` → `var.ssh_public_key`.

---

## 6. `tags` — что это и где используется

```hcl
# variables.tf
variable "tags" {
  type = map(string)  # словарь: ключ → значение
}

# dev.tfvars
tags = {
  environment = "dev"
  project     = "azure-vm-terraform"
  managed_by  = "terraform"
}
```

**Тег — это метка на ресурсе Azure.** Аналог label в Kubernetes или стикера на коробке.

**Где используется:** на всех ресурсах где написано `tags = var.tags` — VNet, Public IP, NIC, VM и Resource Group.

**Что увидишь в Azure Portal:** в любом ресурсе → вкладка Tags → там будет:
```
environment = dev
project     = azure-vm-terraform
managed_by  = terraform
```

**Зачем нужны:**
- Фильтрация: "покажи все ресурсы с `environment=dev`"
- Биллинг: можно сгруппировать затраты по тегам (`project=X стоит $50/месяц`)
- Автоматизация: скрипты могут искать ресурсы по тегам
- Аудит: сразу видно что этот ресурс создал Terraform

**Это только для Azure** (не для GitHub). GitHub не знает о тегах Azure.

---

## 7. Пересекаются ли переменные из `variables.tf`, `dev.tfvars`, `prod.tfvars`?

Нет, они **дополняют** друг друга — каждый файл выполняет свою роль:

```
variables.tf   = СХЕМА (что за переменная, какого типа, описание)
dev.tfvars     = ЗНАЧЕНИЯ для dev окружения
prod.tfvars    = ЗНАЧЕНИЯ для prod окружения
```

Лишних файлов нет. Terraform при запуске:
1. Читает `variables.tf` — узнаёт какие переменные ожидаются
2. Читает указанный `-var-file` (dev или prod) — получает конкретные значения
3. Подставляет значения везде где `var.xxx`

`dev.tfvars` и `prod.tfvars` никогда не читаются одновременно.

---

## 8. Зачем разделение на dev и prod?

Чтобы **один и тот же код** создавал разные инфраструктуры без правки файлов.

| | dev | prod |
|---|---|---|
| Регион | northeurope | westeurope |
| Resource Group | ...-dev | ...-prod |
| Выключение | 22:00 | 23:00 |

**Практический смысл:**
- dev: тестируешь новый конфиг, ломаешь — не страшно
- prod: стабильная среда, изменения только после проверки в dev
- Оба существуют одновременно независимо (разные Resource Groups в Azure)
- Нет риска случайно `destroy` прод вместо дева

---

## 9. Правила расчёта адресов в `network.tf`

```
VNet:   10.10.0.0/16   → 65534 адреса
Subnet: 10.10.1.0/24   → 254 адреса
```

**Как читать CIDR нотацию:**
- `10.10.0.0/16` — первые 16 бит фиксированы (`10.10`), остальные 16 свободны → 2^16 - 2 = 65534 адреса
- `10.10.1.0/24` — первые 24 бита фиксированы (`10.10.1`), последние 8 свободны → 2^8 - 2 = 254 адреса

**Почему именно `10.10.x.x`:** диапазон `10.0.0.0/8` — приватный (RFC 1918), в интернете не маршрутизируется. Можно было взять `10.0.0.0`, `172.16.0.0`, `192.168.0.0` — всё равно. Выбор `10.10` — читаемо и не конфликтует с типичными домашними сетями (`192.168.1.x`).

**Правила при ручной настройке:**
1. Subnet должна быть **внутри** VNet: `10.10.1.0/24` входит в `10.10.0.0/16` ✓
2. Подсети внутри одного VNet не должны **пересекаться**
3. Azure резервирует 5 адресов в каждой подсети (первые 4 + последний) — реально доступно 249 из 254
4. Выбирай VNet с запасом (`/16`), Subnet — по реальной потребности
5. Если планируешь несколько подсетей — нарежь заранее: `10.10.1.0/24`, `10.10.2.0/24`, `10.10.3.0/24`

---

## 10. Почему динамический IP, а не статический?

```hcl
allocation_method = "Dynamic"
private_ip_address_allocation = "Dynamic"
```

**Статический публичный IP в Azure стоит денег** (~$3-4/месяц), даже когда VM выключена.

**Динамический** — бесплатен, но IP меняется при каждом запуске VM.

**Для нашего случая (dev/учебный проект):**
- VM выключается каждый день по расписанию
- После включения IP поменяется — не страшно, IP всегда виден в outputs
- Экономия денег важнее стабильного IP

**Для прода** где нужен стабильный IP (DNS, сертификат) — используй `Static`.

---

## 11. Цепочка зависимостей — зачем она нужна

Terraform не может создать NIC без Subnet, а Subnet без VNet. Он это понимает через **ссылки между ресурсами**:

```hcl
# NIC ссылается на Subnet
subnet_id = azurerm_subnet.subnet.id
            ↑ здесь Terraform видит зависимость
```

**Зачем это нужно:** чтобы Terraform знал порядок создания и удаления.

**Создание — сначала то, от чего зависят другие:**
```
Resource Group → VNet → Subnet ─┐
                Public IP ──────→ NIC → NSG Association → VM → Shutdown
```

**Удаление:** в обратном порядке — нельзя удалить VNet пока в нём есть Subnet с NIC.

**Независимые ресурсы создаются параллельно:** VNet и Public IP не зависят друг от друга — Terraform запускает их одновременно.

**Конкретные места в коде где прописаны зависимости:**

| Файл | Строка | Зависимость |
|---|---|---|
| `network.tf:4` | `location = azurerm_resource_group.resource_group.location` | VNet ← Resource Group |
| `network.tf:12` | `virtual_network_name = azurerm_virtual_network.virtual_network.name` | Subnet ← VNet |
| `network.tf:32` | `subnet_id = azurerm_subnet.subnet.id` | NIC ← Subnet |
| `network.tf:34` | `public_ip_address_id = azurerm_public_ip.public_ip.id` | NIC ← Public IP |
| `security.tf` | `network_interface_id = azurerm_network_interface.network_interface.id` | Association ← NIC |
| `compute.tf` | `network_interface_ids = [azurerm_network_interface.network_interface.id]` | VM ← NIC |

---

## 12. SSH из любого источника (`*`) — правильно ли это?

```hcl
source_address_prefix = "*"  # с любого IP
```

**Нет, это небезопасно для прода.** Для учебного проекта — приемлемо.

При `*` любой человек в интернете может попытаться подключиться по SSH. Пароль отключён (только ключ), поэтому без приватного ключа всё равно не войдут. Но боты всё равно долбятся и создают шум в логах.

**Варианты:**

| Вариант | Пример | Когда использовать |
|---|---|---|
| Любой (текущее) | `"*"` | Учеба, динамический IP дома |
| Только твой IP | `"1.2.3.4/32"` | Если IP статический |
| Корпоративная сеть | `"10.0.0.0/8"` | VPN/офис |
| Azure Bastion | через портал | Прод без публичного SSH |
| JIT Access | через Azure Defender | Автоматически закрывается |

Для прода используют либо VPN + закрытый SSH, либо Azure Bastion (SSH через портал без открытого порта 22).

---

## 13. Откуда знать IP после `terraform apply`?

Из `outputs.tf`. После apply Terraform сам выводит:

```
Outputs:

public_ip            = "20.50.123.45"
virtual_machine_name = "linux-vm-main"
resource_group       = "resource-group-terraform-azure-vm-dev"
ssh_command          = "ssh azureuser@20.50.123.45"
```

В документации `20.50.123.45` — пример, не реальный IP. Реальный IP появляется только после создания VM. Во время `plan` поле `public_ip` пустое — Azure ещё не назначил адрес (потому что Dynamic).

---

## 14. Почему `fmt -check` идёт после `init`, а не перед?

```bash
terraform init          # 1
terraform fmt -check    # 2
terraform validate      # 3
```

`fmt` технически не требует `init` — он просто проверяет форматирование текста файлов. Практическая причина порядка: в CI-пайплайне `init` делается первым шагом всегда, дальше — проверки. Это стандартный порядок, а не техническое требование.

`validate` же **требует** `init` — он проверяет не только синтаксис, но и правильность типов и ссылок, для чего нужны скачанные провайдеры.

---

## 15. `tfstate` — когда обновляется?

`terraform.tfstate` — файл который хранит **текущее состояние** инфраструктуры по мнению Terraform.

**Обновляется при:**
- `terraform apply` — создал/изменил ресурсы → записал новое состояние
- `terraform destroy` — удалил ресурсы → очистил запись в state
- `terraform import` — добавил ресурс созданный вне Terraform в state

**При `plan`** — state только **читается**, не записывается. Terraform сравнивает: "что в state" vs "что хочу по коду" vs "что реально в Azure" → показывает diff.

**Важно:** state не обновляется в реальном времени. Если кто-то вручную изменил ресурс в Azure Portal — Terraform об этом не знает пока не запустишь `terraform refresh` или следующий `plan`.

---

## 16. Service Principal — что это?

**Service Principal (SP)** — "технический аккаунт" в Azure для приложений и автоматизации.

**Аналогия:** обычный пользователь Azure — это человек с логином и паролем. Service Principal — это "пользователь-робот" для программ, у которого нет пароля (или есть, но мы используем OIDC).

**Почему нельзя использовать личный аккаунт в CI:** GitHub Actions — это чужой сервер. Нельзя дать ему свои логин/пароль. SP решает это — он имеет только те права что ты ему дал (Contributor на подписку), и его можно отозвать в любой момент не трогая свой аккаунт.

```
твой аккаунт     = полный доступ ко всему Azure
Service Principal = только Contributor на одну подписку
```

---

## 17. GitHub Actions — workflow, что это, откуда тригерится, и как работает

### Что такое workflow

**Workflow** — это файл с инструкциями для GitHub Actions. Он живёт в репозитории по пути:

```
.github/workflows/terraform-azure-vm.yml
```

Это обычный YAML-файл. Ты его написал сам — GitHub просто его читает и выполняет. Terraform не знает про этот файл и никак его не создаёт. Terraform — инструмент для Azure, workflow — инструмент для автоматизации CI/CD.

### Что внутри workflow-файла

Файл `.github/workflows/terraform-azure-vm.yml` состоит из трёх частей:

**1. Триггеры — когда запускать:**
```yaml
on:
  pull_request:               # при создании PR затрагивающего infra/
    paths: ["infra/**", ...]
  push:                       # при push в main затрагивающего infra/
    branches: ["main"]
    paths: ["infra/**", ...]
  workflow_dispatch:          # вручную через кнопку в GitHub UI
    inputs:
      action: apply/destroy
      environment: dev/prod
```

**2. Разрешения — что workflow может делать:**
```yaml
permissions:
  id-token: write      # получать OIDC-токен для входа в Azure
  contents: read       # читать файлы репозитория
  pull-requests: write # писать комментарии к PR
```

**3. Шаги — что именно выполняется (в порядке):**
```yaml
steps:
  - Checkout repository       # скачать код репозитория
  - Azure Login (OIDC)        # войти в Azure без пароля
  - Setup Terraform           # установить terraform на runner
  - Terraform Format Check    # terraform fmt -check
  - Terraform Init            # terraform init
  - Terraform Validate        # terraform validate
  - Terraform Plan            # terraform plan → сохраняет tfplan
  - Comment Plan on PR        # если это PR — написать комментарий с результатом plan
  - Terraform Apply           # если это push в main или workflow_dispatch apply
  - Terraform Destroy         # если это workflow_dispatch destroy
```

### Что происходит при push в main

```yaml
- name: Terraform Apply
  if: >
    github.event_name == 'push' ||
    (github.event_name == 'workflow_dispatch' && inputs.action == 'apply')
  run: terraform apply -input=false -auto-approve tfplan
```

При push в main запускаются **все шаги**: fmt → init → validate → **plan** → **apply**. То есть push в main = автоматический деплой инфраструктуры. Поэтому в реальных проектах прямой push в main обычно запрещён — только через PR.

### Что происходит при pull_request

```yaml
- name: Comment Plan on PR
  if: github.event_name == 'pull_request'
```

При PR запускаются: fmt → init → validate → **plan** → **комментарий с результатом plan**. Apply не запускается. Это "безопасный просмотр" что изменится.

### Полная картина

```
Твой ноутбук          GitHub                GitHub Actions runner     Azure
──────────────         ──────                ────────────────────      ─────
git push main    →    видит push      →    запускает workflow     →   terraform apply
git push (PR)    →    видит PR        →    запускает workflow     →   terraform plan (только)
кнопка UI        →    workflow_dispatch →  запускает workflow     →   apply или destroy
```

Твой ноутбук только **инициирует событие**. Сам Terraform выполняется на серверах GitHub (Ubuntu runner), не у тебя.

### Как GitHub понимает что запускать в зависимости от события

Условия `if:` в каждом шаге — вот где прописана логика:

| Шаг | Условие `if:` | Когда выполняется |
|---|---|---|
| Comment Plan | `github.event_name == 'pull_request'` | Только при PR |
| Apply | `github.event_name == 'push'` | При push в main |
| Apply | `inputs.action == 'apply'` | При workflow_dispatch с action=apply |
| Destroy | `inputs.action == 'destroy'` | При workflow_dispatch с action=destroy |

Plan запускается **всегда** — при любом событии. Apply/destroy — только при нужных условиях.

---

## 17а. Как GitHub Actions запускает Terraform — где хранятся .tf файлы?

Ключ в первом шаге workflow:

```yaml
steps:
  - name: Checkout repository   # ← ВОТ ГДЕ ответ
    uses: actions/checkout@v4
```

**`actions/checkout@v4` скачивает весь репозиторий на временную машину GitHub.**

Что происходит пошагово:

```
1. GitHub поднимает чистую Ubuntu-машину (runner)
2. Checkout — копирует весь репозиторий на эту машину:
   runner/
   ├── infra/
   │   ├── main.tf
   │   ├── network.tf
   │   ├── compute.tf
   │   └── ...
3. Setup Terraform — устанавливает terraform на runner
4. terraform init/plan/apply — выполняется ЛОКАЛЬНО на runner
   против этих скопированных .tf файлов
5. Terraform через Azure API создаёт ресурсы в Azure
6. Runner выключается, все файлы удаляются
```

**Визуально:**
```
GitHub repo         Runner (временная Ubuntu-машина)      Azure
(хранит .tf)  →  checkout → terraform apply  →  создаёт VM, VNet, NIC...
```

**Azure вообще не знает про Terraform.** Он просто получает API-запросы: "создай VM с такими параметрами", "создай VNet", "создай NIC" — и выполняет их. Terraform — это клиент, который эти запросы генерирует.

`.tf` файлы хранятся в **GitHub-репозитории**. На серверах Azure их нет и никогда не было.

---

## 17в. Для чего используется Terraform — только VM и биллинг?

**Нет, Terraform — это универсальный инструмент для описания любой инфраструктуры в коде (IaC).** VM — просто один из примеров.

Terraform работает через провайдеры, и их сотни. Что можно описывать:

**В Azure (azurerm):**
- VM, контейнеры, Kubernetes кластеры (AKS)
- Базы данных (PostgreSQL, MySQL, CosmosDB)
- Сети, DNS, Load Balancer, VPN
- Storage, Key Vault, App Service
- Права доступа (IAM), политики

**В других облаках:**
- AWS (EC2, S3, RDS, Lambda...)
- GCP (Compute Engine, GKE, BigQuery...)

**Вне облаков:**
- GitHub (репозитории, секреты, команды)
- Cloudflare (DNS-записи)
- Kubernetes (деплойменты, сервисы)
- Базы данных (создание таблиц, пользователей)
- Datadog, PagerDuty (мониторинг)

**Главная идея:** если что-то имеет API — скорее всего есть Terraform-провайдер. Всё описывается одним языком (HCL), хранится в git, имеет plan/apply/destroy.

---

## 18. Почему Azure-параметры настраиваются в репозитории GitHub?

```
GitHub Secrets:
  AZURE_CLIENT_ID       ← ID Service Principal в Azure
  AZURE_TENANT_ID       ← ID твоего Azure tenant
  AZURE_SUBSCRIPTION_ID ← ID подписки
```

GitHub Actions workflow содержит шаги `az login` и `terraform apply`. Для их выполнения нужны credentials Azure. Эти credentials хранятся в GitHub Secrets (зашифровано) и передаются в workflow как переменные окружения.

**Альтернатива** хранить их прямо в workflow-файле — никогда, это небезопасно (файл публичный).

**Связь:** в Azure настраивается "доверяй токенам от этого GitHub репозитория" (Federated Credential). В GitHub хранится ID приложения (не пароль). При запуске GitHub генерирует токен → Azure его принимает → доступ есть.

---

## 19. Pull Request — как он запускает Terraform plan?

**PR можно создать двумя способами:**
1. Через GitHub интерфейс: кнопка "New pull request" на github.com
2. Через `gh` CLI: `gh pr create --base main` из терминала
3. Через `git push` + GitHub предлагает создать PR

**Как Terraform plan запускается автоматически:**

```yaml
# .github/workflows/terraform-azure-vm.yml
on:
  pull_request:
    paths:
      - 'infra/**'
```

Когда создаётся PR затрагивающий файлы в `infra/` → GitHub видит событие `pull_request` → запускает workflow → workflow запускает `terraform plan` → результат публикуется как комментарий к PR.

**Важно:** Terraform запускается на серверах GitHub, а не локально. Твой локальный Terraform здесь не при чём.

---

## 20. Варианты запуска Terraform не локально

Пункт 10 в setup-tutorial.md — "Локальный запуск (опционально)" — основной способ это GitHub Actions.

| Где запускается | Как |
|---|---|
| GitHub Actions (основной) | push / PR / workflow_dispatch |
| Локально (опционально) | `terraform apply` из терминала |
| Azure DevOps Pipelines | альтернатива GitHub Actions |
| Terraform Cloud | SaaS от HashiCorp, хранит state в облаке |
| GitLab CI | если используешь GitLab |

В нашем проекте основной способ — GitHub Actions. Локальный запуск — только для отладки, когда не хочешь делать push ради каждой проверки.

---

## 21. `outputs.tf` — для чего, как работает

`outputs.tf` — это **отдельный файл**, не часть `apply`. Terraform не выполняет его как команду — он просто описывает что показать после apply.

```hcl
# outputs.tf
output "public_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.public_ip.ip_address}"
}
```

**Как работает — три момента:**

**1. После `terraform apply`** Terraform автоматически читает все `output` блоки и выводит в терминал:
```
Outputs:

public_ip            = "20.50.123.45"
virtual_machine_name = "linux-vm-main"
resource_group       = "resource-group-terraform-azure-vm-dev"
ssh_command          = "ssh azureuser@20.50.123.45"
```
Никакой отдельной команды запускать не нужно — это происходит само.

**2. Значения берутся из реальных созданных ресурсов** — не из переменных и не из tfvars. `azurerm_public_ip.public_ip.ip_address` — это атрибут уже созданного ресурса, который Azure вернул после создания. Поэтому во время `plan` это поле пустое (ресурс ещё не создан).

**3. Сохраняются в tfstate** — можно получить позже без повторного apply:
```bash
# Показать все outputs
terraform output

# Получить конкретный (удобно в скриптах)
terraform output -raw public_ip
# → 20.50.123.45
```

**В GitHub Actions** workflow выводит эти значения в логи после apply — видишь готовую строку `ssh_command` прямо в интерфейсе GitHub.

**Можно ли обойтись без outputs.tf?** Да. Инфраструктура создастся без него. Outputs — это удобство, не требование. Но без них придётся вручную искать IP в Azure Portal.
