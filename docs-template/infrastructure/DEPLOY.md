# Развёртывание

> **Status:** draft  
> **Last verified:** 2026-02-03  
> **Owner:** @Pixasso

Руководство по развёртыванию AI Docs System.

## Требования

### Для bash-скриптов (macOS/Linux)
- Git 2.x+
- Bash 4.0+
- curl
- tar

### Для Windows
- Git 2.x+
- PowerShell 5.1+

### Для npm-пакета
- Node.js 14+
- npm 7+

## Установка через npm (рекомендуется)

```bash
cd /path/to/your/project
npx ai-docs-system install .
```

## Установка через bash

```bash
git clone https://github.com/Pixasso/ai-docs-system.git
cd ai-docs-system
bash install.sh /path/to/your/project
```

## Конфигурация

После установки отредактируйте `.ai-docs-system/config.env`:

```bash
# Папки с кодом
CODE_DIRS=src,services

# Папки с документацией
DOC_DIRS=docs

# Расширения файлов кода
CODE_EXTS=.ts,.js,.py

# Включённые правила
RULES_ENABLED=pending-write,context,rules-config,rules-testing

# Адаптеры AI
ADAPTERS=cursor,copilot,claude
```

## Обновление

```bash
# Через npm
npx ai-docs-system update .

# Через bash
.ai-docs-system/update.sh
```

## Аудит

```bash
# Через npm
npx ai-docs-system audit .

# Через bash
bash install.sh . audit
```

## Удаление

```bash
# Через npm
npx ai-docs-system uninstall .

# Через bash
bash install.sh . uninstall
```

## Troubleshooting

### Ошибка "curl не найден"
Установите curl:
```bash
# macOS
brew install curl

# Ubuntu/Debian
apt-get install curl
```

### Ошибка "git не найден"
Установите Git:
```bash
# macOS
brew install git

# Ubuntu/Debian
apt-get install git
```

### Ошибка "Не git-репозиторий"
Инициализируйте git:
```bash
cd /path/to/project
git init
```

## Связанное

- [Архитектура](/docs/architecture/OVERVIEW.md)
- [Конфигурация](/docs/features/config.md)
