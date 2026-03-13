Отвечу по пунктам (и **поправлю терминологию**): в Azure “free tier” — это **VM**, а не “container”. Контейнеры — это ACI/AKS, и это другое задание. У тебя задача: **VM через Terraform + GitHub Actions**.

Ниже:

1. ответы на все вопросы 1–17,
2. план разбиения задачи и минимальной проверки (для п.7),
3. “не capacity guarantee” простыми словами,
4. что такое `vm_size` и зачем он.

В конце дам **ссылки на доки** (я положу их в code block, чтобы интерфейс корректно их показывал).

---

## 1) “type of container?” — это не контейнер

Это **Virtual Machine** (Linux VM). “Free tier B1s” — это **размер VM** (SKU), например `Standard_B1s`.

---

## 2) Workflow: fmt/validate/plan, merge → apply

Тут логика такая:

* На **Pull Request**: запускаем проверки и **`terraform plan`** (чтобы увидеть, что будет создано/изменено).
* На **merge в main**: запускаем **`terraform apply`** (то есть реально создаём ресурсы).

Технически это делается триггерами GitHub Actions:

* `on: pull_request` → fmt/validate/plan
* `on: push` (branches: main) → apply
  Это стандартный паттерн для IaC. GitHub про “events” пишет здесь ([GitHub Docs][1]).

---

## 3) Что такое “SG network”? Что такое tags?

### SG network

В AWS “Security Group”. В Azure аналог называется **NSG (Network Security Group)**.

* **VNet** = виртуальная сеть (как “виртуальный роутер/сеть”)
* **Subnet** = подсеть внутри VNet
* **NSG** = правила firewall на вход/выход (например разрешить SSH 22)

В моём Terraform:

* `azurerm_virtual_network` — VNet
* `azurerm_subnet` — subnet
* `azurerm_network_security_group` — NSG
* `azurerm_network_interface_security_group_association` — “привязать NSG к NIC”

### Tags

**Tags** = метки “ключ=значение” на Azure ресурсах (например `project=...`, `owner=...`).
Зачем:

* фильтрация в портале,
* отчёты по затратам (cost),
* политики (Azure Policy),
* автоматизация (например выключать всё с tag=dev).

---

## 4) Auto shutdown — “когда событие случилось?”

Auto shutdown тут **не по событию**, а **по расписанию** (например каждый день в 22:00).
Это нужно, чтобы VM не работала ночью и не жгла бюджет/квоты.

---

## 5) Auth GitHub → Azure (OIDC) и “в какой последовательности”

OIDC = способ дать GitHub Actions временный токен в Azure **без пароля и без client secret**.

Последовательность действий:

1. **В Azure**: создать App Registration (Microsoft Entra ID).
2. Создать **Federated credential** (доверие к GitHub repo/branch/environment).
3. Дать этой app права (роль) на subscription или resource group (обычно **Contributor** на RG).
4. **В GitHub repo**: добавить secrets **не-парольные**:

   * `AZURE_CLIENT_ID`
   * `AZURE_TENANT_ID`
   * `AZURE_SUBSCRIPTION_ID`
     (это просто идентификаторы, не секрет-пароль)
5. В workflow добавить шаг `azure/login@v2` с этими id.

Документация прямо по этому сценарию: GitHub guide ([GitHub Docs][2]) и Microsoft Learn ([Microsoft Learn][3]). Также у `azure/login` есть README ([GitHub][4]).

**Где “manual accept”?**
Manual approval чаще делают через **GitHub Environments**:

* job имеет `environment: azure-prod`
* в настройках environment ставишь “Required reviewers”
  Тогда **apply job** остановится и будет ждать одобрения в UI GitHub. Это отдельная “ступень безопасности”, не в Azure.

---

## 6) Зачем “ручной terraform destroy” для экономии

Terraform создаёт ресурсы. Если ты создал VM и забыл — она продолжает жить (и может стоить деньги/съедать лимиты).

**`terraform destroy`** удаляет всё, что Terraform создал (что записано в state).
Почему “ручной”:

* чтобы случайно не снести прод,
* чтобы ты контролировал момент удаления,
* в учебном задании удобно: “создал → проверил → удалил”.

---

## 7) “fallback by size and length” — это не про контейнер, и не про длину

Тут я криво выразился: речь про **fallback по VM size и region**.

* **size** = тип/мощность VM (`Standard_B1s`, `Standard_B1ls`, …)
* **region** = где создаём (`eastus`, `northeurope`, …)

Если Azure отвечает `SkuNotAvailable`, значит **в этом регионе сейчас нет capacity/доступности для этого размера** — тогда пробуем другой регион или другой размер.

Никакой “длины” контейнера тут нет.

---

## 8) “проверка и обработка” — о чём это

О том, что DevOps-подход — не просто “ну упало и ладно”, а:

* документируешь причину (`SkuNotAvailable`),
* добавляешь возможность менять `location` и `vm_size` **без правки кода** (например через inputs в workflow_dispatch),
* добавляешь список “рекомендованных регионов/размеров” в README.

Это выглядит как “инженерная обработка edge-case”.

---

## 9) Чем Spot отличается от free tier

* **Free tier**: про **скидку/кредит** (например “750 часов B1s” может быть бесплатно).
* **Spot VM**: про то, что Azure может **в любой момент забрать VM обратно**, если ресурсы понадобились другим (VM “preemptible”). Обычно дешевле, но менее надёжно.

Spot решает иногда проблему цены/иногда capacity, но добавляет риск “VM отключат”.

---

## 10) Auto shutdown “по какому событию”

Ещё раз: **по расписанию**, не по событию.
Событие могло бы быть “push в repo” или “ночь наступила”, но в Azure shutdown schedule — это именно **daily recurrence**.

---

## 11) Почему workflow лежит в `.github/workflows/*.yml` и при чём тут Terraform

GitHub Actions устроен так: workflow — это YAML файл в `.github/workflows/`. GitHub читает его и запускает jobs/steps на runner.

Terraform тут просто команда, которую runner выполняет (`terraform init/plan/apply`).
Документация про workflows: ([GitHub Docs][5]).

---

## 12) Документация по OIDC

* GitHub: OIDC для Azure ([GitHub Docs][2])
* Microsoft Learn: Azure Login action с OIDC ([Microsoft Learn][3])
* `azure/login` README ([GitHub][4])

---

## 13) “plan на PR” — что это

Это настройка “запускать `terraform plan` на событие pull_request”.

Зачем:

* видеть изменения до мерджа,
* поймать ошибки до apply,
* это как “preview инфраструктуры”.

---

## 14) “apply” — что это и как настраивается

`terraform apply` — команда, которая **реально создаёт/меняет ресурсы в Azure**.

Обычно:

* PR → только plan
* main → apply (после review + merge)
  И да: можно сделать “environment approval”, чтобы apply ждал ручного approve в GitHub UI.

Это не отдельный файл, это **команда** в workflow step.

---

## 15) “destroy manual” — что он должен уничтожить

Всё, что Terraform создал и записал в state:

* resource group,
* vnet/subnet,
* NSG,
* public ip,
* NIC,
* VM,
* schedule.

Если state хранится правильно, destroy будет чистый.

---

## 16) “теги на ресурсы” — что такое “ресурсы” и зачем теги

Ресурс = любой объект в Azure (VM, сеть, IP, диски, NSG, RG…).

Теги нужны для:

* порядка,
* поиска,
* биллинга/отчётов,
* политик/автоматизации.

---

## 17) Автошатдаун по расписанию — да, это хорошая практика

Да, стоит. В учебных задачах — прям мастхэв.

---

# Теперь про Terraform: что значит “каждую строчку” и почему так

Полный построчный разбор всего файла будет очень длинный, поэтому дам **“блок за блоком”**: что делает каждый ресурс + почему такие параметры, и где доки.

### `terraform { required_providers ... }`

Фиксируешь версию провайдера AzureRM → стабильные сборки.
Док по ресурсам/провайдеру: ([registry.terraform.io][6])

### `provider "azurerm" { features {} }`

Включает провайдер AzureRM, `features {}` обязателен (так устроен провайдер).

### `azurerm_resource_group`

RG — контейнер для всех ресурсов. Удобно удалять одним махом и давать права.

### `azurerm_virtual_network` + `azurerm_subnet`

Минимальная сеть, куда подключится VM.

Почему адреса такие: просто приватный диапазон, чтобы не конфликтовал с домашними сетями.

### `azurerm_network_security_group` + rule SSH 22

NSG разрешает SSH, иначе ты не подключишься.

Почему source `*` — это “упрощённо для демо”. В реальном проекте лучше ограничить по IP.

### `azurerm_public_ip`

Публичный IP, чтобы VM была доступна из интернета по SSH. Allocation Dynamic — проще/дешевле.

### `azurerm_network_interface`

NIC — сетевая карта VM. Ей назначаем subnet + public ip.

### `azurerm_network_interface_security_group_association`

Привязка NSG к NIC (чтобы firewall реально применился).

### `azurerm_linux_virtual_machine`

Сама VM:

* `size = var.vm_size` — чтобы можно было менять размер без правки ресурса.
* `admin_ssh_key` — логин по SSH ключу (лучше чем пароль).
* `os_disk` Standard_LRS — самый базовый тип.
* `source_image_reference` Ubuntu 22.04 LTS — стабильный дефолт.

Док по этому ресурсу: ([registry.terraform.io][6])

### `azurerm_dev_test_global_vm_shutdown_schedule`

Ежедневно выключает VM в заданное время/таймзоне.
Док: ([registry.terraform.io][7])

---

# Пункт 7: план “минимально проверить, что работает”, и разбить задачу на подзадачи

Вот “дебажный” план (делай строго по шагам):

## Шаг A — Terraform локально без GitHub Actions (самая быстрая проверка)

1. Создай `infra/` и туда Terraform файлы.
2. Локально:

   * `terraform fmt`
   * `terraform init`
   * `terraform validate`
   * `terraform plan -var location=northeurope -var vm_size=Standard_B1s -var ssh_public_key="..."`

Цель: убедиться, что **код вообще валидный**.

## Шаг B — Apply локально (чтобы отделить проблемы Azure от GitHub)

3. `terraform apply` (вручную)

* Если упало `SkuNotAvailable`: меняй `location` и `vm_size` и пробуй снова.
* Запиши 2–3 рабочие комбинации “region + size” (если найдёшь).

Цель: понять, что **Azure реально даёт создать VM**.

## Шаг C — GitHub Actions только fmt/validate/plan

4. Добавь workflow так, чтобы на PR делал только `fmt/validate/plan`, но без apply.

Цель: убедиться, что pipeline запускается и умеет `terraform plan`.

## Шаг D — OIDC

5. Настрой OIDC, и проверь, что step `azure/login` проходит, и дальше `terraform init/plan` работает в Actions.

Цель: убедиться, что **аутентификация** верная.

## Шаг E — Apply на main с Environment approval

6. Включи apply на `push main` + environment reviewers.
7. Сделай PR → merge → approve environment → apply.

Цель: полный end-to-end.

## Шаг F — Destroy manual

8. `workflow_dispatch action=destroy` (или локально `terraform destroy`).

Цель: clean-up и демонстрация “cost control”.

---

## 8.3 “не capacity guarantee” — объяснение

“Free tier / eligible VM size” = **про цену**, но **не обещание**, что в конкретном регионе будет свободная мощность именно сейчас.

Т.е. Azure может сказать:

* “да, B1s входит в free-tier по биллингу”
* но одновременно:
* “в East US нет capacity для B1s для твоей подписки” → `SkuNotAvailable`

---

## Зачем `vm_size` переменная

Чтобы ты мог:

* быстро менять размер, не редактируя ресурс VM,
* передавать его из workflow inputs,
* делать fallback: “попробуй B1s, если нет — B1ls”.

Это нормальная инженерная “ручка” для отладки и реальной эксплуатации.

---

# Ссылки на документацию

(как просил — даю)

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

Если хочешь — в следующем сообщении я:

* перепишу Terraform так, чтобы **SSH rule** была ограничена твоим IP (безопаснее),
* добавлю **remote backend для state** (Azure Storage + state locking — тоже “DevOps”),
* и предложу “минимальный вариант” Terraform (VM без auto-shutdown), чтобы сначала поднять VM, а потом усложнять.

[1]: https://docs.github.com/actions/using-workflows/events-that-trigger-workflows?utm_source=chatgpt.com "Events that trigger workflows"
[2]: https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure?utm_source=chatgpt.com "Configuring OpenID Connect in Azure"
[3]: https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect?utm_source=chatgpt.com "Use the Azure Login action with OpenID Connect"
[4]: https://github.com/Azure/login?utm_source=chatgpt.com "Azure/login: Connect to Azure"
[5]: https://docs.github.com/actions/using-workflows/about-workflows?utm_source=chatgpt.com "Workflows - GitHub Docs"
[6]: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine?utm_source=chatgpt.com "azurerm_linux_virtual_machine | hashicorp/azurerm | Terraform"
[7]: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_test_global_vm_shutdown_schedule.html?utm_source=chatgpt.com "azurerm_dev_test_global_vm_s..."
