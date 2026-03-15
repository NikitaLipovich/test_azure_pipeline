# Setup Tutorial: Terraform + Azure VM via GitHub Actions (OIDC)

Это пошаговое руководство по настройке окружения для запуска Terraform-пайплайна,
который разворачивает Linux VM в Azure через GitHub Actions с авторизацией по OIDC
(без хранения секретов/паролей).

---

## Содержание

1. [Что нужно установить](#1-что-нужно-установить)
2. [Подготовка Azure](#2-подготовка-azure)
3. [Настройка OIDC — Federated Credential](#3-настройка-oidc--federated-credential)
4. [Генерация SSH-ключа](#4-генерация-ssh-ключа)
5. [Настройка GitHub репозитория](#5-настройка-github-репозитория)
6. [Настройка GitHub Environment с Required Reviewers](#6-настройка-github-environment-с-required-reviewers)
7. [Первый запуск пайплайна](#7-первый-запуск-пайплайна)
8. [Подключение к VM по SSH](#8-подключение-к-vm-по-ssh)
9. [Уничтожение инфраструктуры](#9-уничтожение-инфраструктуры)
10. [Локальный запуск Terraform (опционально)](#10-локальный-запуск-terraform-опционально)

---

## 1. Что нужно установить

### Обязательно (локально)

| Инструмент | Версия | Назначение |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.6.0 | IaC — описание инфраструктуры |
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) | последняя | Создание Service Principal, OIDC |
| [Git](https://git-scm.com/downloads) | последняя | Работа с репозиторием |
| SSH (встроен в Windows 11) | — | Генерация ключей и подключение к VM |

### Проверка установки

```bash
terraform -version   # >= 1.6.0
az version           # любая актуальная
git --version
ssh -V
```

---

## 2. Подготовка Azure

### 2.1. Войти в Azure CLI

```bash
az login
```

Откроется браузер — войдите в свой аккаунт Microsoft/Azure.

### 2.2. Выбрать подписку

```bash
# Посмотреть все доступные подписки
az account list --output table

# Установить нужную (замените <SUBSCRIPTION_ID>)
az account set --subscription "<SUBSCRIPTION_ID>"

# Убедиться что выбрана правильная
az account show --output table
```

Запишите значения — они понадобятся позже:
- `id` — это `AZURE_SUBSCRIPTION_ID`
- `tenantId` — это `AZURE_TENANT_ID`

### 2.3. Создать Service Principal (App Registration)

```bash
az ad sp create-for-rbac \
  --name "sp-github-terraform-azure-vm" \
  --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID> \
  --sdk-auth false
```

Из вывода запишите:
- `appId` — это `AZURE_CLIENT_ID`

> **Важно:** флаг `--sdk-auth false` намеренно. Мы используем OIDC,
> поэтому `clientSecret` нам не нужен.

---

## 3. Настройка OIDC — Federated Credential

OIDC позволяет GitHub Actions авторизоваться в Azure **без client secret**.
Вместо этого Azure доверяет токенам, которые GitHub генерирует для конкретного репозитория.

### 3.1. Добавить Federated Credential для push в main

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

### 3.2. Добавить Federated Credential для pull_request

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

### 3.3. Добавить Federated Credential для Environment (workflow_dispatch)

Workflow использует GitHub Environment `azure-prod`. Для него нужен отдельный credential:

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

> Замените `<GITHUB_USERNAME>/<REPO_NAME>` на реальные значения, например:
> `myuser/my-infra-repo`

### 3.4. Проверить список Federated Credentials

```bash
az ad app federated-credential list --id "<AZURE_CLIENT_ID>" --output table
```

Должно быть 3 записи.

---

## 4. Генерация SSH-ключа

VM создаётся с отключённой парольной аутентификацией. Доступ только по SSH-ключу.

```bash
# Генерация ключа ed25519 (рекомендуется)
ssh-keygen -t ed25519 -C "azure-vm-terraform" -f ~/.ssh/azure_vm_key
```

Будет создано два файла:
- `~/.ssh/azure_vm_key` — приватный ключ (никому не передавать)
- `~/.ssh/azure_vm_key.pub` — публичный ключ (загружается в GitHub Secrets)

```bash
# Посмотреть содержимое публичного ключа
cat ~/.ssh/azure_vm_key.pub
```

Скопируйте вывод — он понадобится в следующем шаге.

---

## 5. Настройка GitHub репозитория

### 5.1. Перейти в Settings > Secrets and variables > Actions

Путь: `https://github.com/<GITHUB_USERNAME>/<REPO_NAME>/settings/secrets/actions`

### 5.2. Добавить Repository Secrets

Нажать **New repository secret** для каждого:

| Secret Name | Значение |
|---|---|
| `AZURE_CLIENT_ID` | `appId` из шага 2.3 |
| `AZURE_TENANT_ID` | `tenantId` из шага 2.2 |
| `AZURE_SUBSCRIPTION_ID` | `id` из шага 2.2 |
| `SSH_PUBLIC_KEY` | содержимое `~/.ssh/azure_vm_key.pub` |

> Итого 4 секрета. Никаких паролей и client secret не нужно.

---

## 6. Настройка GitHub Environment с Required Reviewers

Workflow привязан к Environment `azure-prod`. Это предотвращает случайный apply без подтверждения.

### 6.1. Создать Environment

1. Перейти в **Settings > Environments**
2. Нажать **New environment**
3. Имя: `azure-prod`
4. Нажать **Configure environment**

### 6.2. Включить Required Reviewers

1. В блоке **Deployment protection rules** включить **Required reviewers**
2. Добавить себя (или нужного человека) как reviewer
3. Нажать **Save protection rules**

Теперь при каждом apply/destroy через workflow_dispatch — потребуется ручное подтверждение.

---

## 7. Первый запуск пайплайна

### 7.1. Через push в main (автоматический apply)

```bash
git add .
git commit -m "feat: initial terraform infrastructure"
git push origin main
```

Workflow запустится автоматически на push в `main` с action `apply` и environment `dev`.

### 7.2. Через workflow_dispatch (ручной запуск)

1. Перейти в **Actions** > **terraform-azure-vm**
2. Нажать **Run workflow**
3. Выбрать параметры:
   - **action**: `apply` или `destroy`
   - **environment**: `dev` или `prod`
   - **location** (опционально): например, `eastus` если B1s недоступен в вашем регионе
   - **virtual_machine_size** (опционально): например, `Standard_B1ls` если `Standard_B1s` недоступен
4. Нажать **Run workflow**
5. Подтвердить деплой в блоке **Review deployments** (т.к. включены Required Reviewers)

### 7.3. Через Pull Request (только plan)

При создании PR, изменяющего файлы в `infra/` или `.github/workflows/terraform-azure-vm.yml`,
автоматически запускается `terraform plan`. Результат публикуется в комментарии к PR.

---

## 8. Подключение к VM по SSH

После успешного apply найдите IP-адрес в выводе workflow:

В шаге **Terraform Apply** в разделе **Outputs** будет строка:
```
ssh_command = "ssh azureuser@<PUBLIC_IP>"
```

Подключиться:
```bash
ssh -i ~/.ssh/azure_vm_key azureuser@<PUBLIC_IP>
```

---

## 9. Уничтожение инфраструктуры

Через **workflow_dispatch**:
1. **action**: `destroy`
2. **environment**: нужное окружение
3. Подтвердить в **Review deployments**

Или локально (см. раздел 10).

> **Внимание:** после destroy все данные VM будут безвозвратно удалены.

---

## 10. Локальный запуск Terraform (опционально)

Для отладки можно запускать Terraform локально.

### 10.1. Авторизоваться в Azure CLI

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

### 10.2. Передать SSH-ключ через переменную окружения

```bash
# Linux/macOS
export TF_VAR_ssh_public_key="$(cat ~/.ssh/azure_vm_key.pub)"

# Windows PowerShell
$env:TF_VAR_ssh_public_key = Get-Content ~/.ssh/azure_vm_key.pub -Raw
```

### 10.3. Запустить Terraform

```bash
cd infra

terraform init
terraform validate
terraform fmt -check -recursive

# Plan для dev окружения
terraform plan -var-file=vars/dev.tfvars

# Apply
terraform apply -var-file=vars/dev.tfvars

# Destroy
terraform destroy -var-file=vars/dev.tfvars
```

---

## Краткий чеклист

- [ ] Установлены: Terraform >= 1.6.0, Azure CLI, Git, SSH
- [ ] Выполнен `az login`, выбрана правильная подписка
- [ ] Создан Service Principal, записан `AZURE_CLIENT_ID`
- [ ] Добавлено 3 Federated Credential (push/main, pull_request, environment/azure-prod)
- [ ] Сгенерирован SSH-ключ `~/.ssh/azure_vm_key`
- [ ] В GitHub добавлено 4 Repository Secrets
- [ ] Создан GitHub Environment `azure-prod` с Required Reviewers
- [ ] Выполнен первый push / workflow_dispatch
- [ ] Workflow прошёл успешно, VM запущена
- [ ] Проверено подключение по SSH

---

## Справка по переменным

| Переменная | Где взять | Пример |
|---|---|---|
| `AZURE_SUBSCRIPTION_ID` | `az account show --query id -o tsv` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_CLIENT_ID` | `az ad sp show --display-name sp-github-terraform-azure-vm --query appId -o tsv` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `SSH_PUBLIC_KEY` | `cat ~/.ssh/azure_vm_key.pub` | `ssh-ed25519 AAAA...` |
