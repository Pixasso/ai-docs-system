# Архитектура AI Docs System

> **Status:** current  
> **Last verified:** 2026-02-03  
> **Owner:** @Pixasso

Обзор архитектуры системы автоматизации документации.

## Компоненты

### 1. Скрипты установки (`install.sh`, `install.ps1`)

**Назначение:** Полная установка, обновление, удаление системы.

**Режимы:**
- `install` — Создание структуры `.ai-docs-system/`, `docs/`, установка хуков
- `update` — Обновление хуков, пересборка AI-адаптеров
- `uninstall` — Удаление системы (docs/ сохраняется)
- `audit` — Проверка состояния документации

**Технологии:** Bash (macOS/Linux), PowerShell (Windows)

### 2. Git Pre-commit Hook (`githooks/pre-commit`)

**Назначение:** Напоминание о документации при изменении кода.

**Логика:**
1. Получить измененные файлы через `git diff --cached --name-only -z`
2. Классифицировать по `DOCS_RE` и `CODE_DIRS` из `config.env`
3. Если изменён код без документации → показать напоминание
4. Записать в `pending-updates.queue` (если `PENDING_UPDATES_WRITE=local`)

**Технологии:** Bash, Windows `.cmd` wrapper

### 3. Конфигурация (`.ai-docs-system/config.env`)

**Назначение:** Централизованные настройки проекта.

**Ключевые параметры:**
- `CODE_DIRS` — папки с кодом
- `DOC_DIRS` — папки с документацией
- `CODE_EXTS` — расширения файлов кода
- `RULES_ENABLED` — включённые правила
- `ADAPTERS` — AI-адаптеры (cursor, copilot, claude, cline)
- `PENDING_UPDATES_WRITE` — режим записи очереди (local/shared/disabled)
- `HOOKS_MODE` — режим установки хуков (managed/integrate)

### 4. AI-адаптеры

**Назначение:** Интеграция с различными AI-инструментами.

**Форматы:**
- **Cursor:** `.cursorrules` (BEGIN/END блок)
- **GitHub Copilot:** `.github/copilot-instructions.md`
- **Claude:** `CLAUDE.md`
- **Cline:** `.clinerules`

**Генерация:** Через `install.sh` → `generate_cursor_rules`, `generate_copilot_rules`, etc.

### 5. Очередь обновлений (`state/pending-updates.queue`)

**Назначение:** Межсессионная коммуникация для отслеживания изменений без коммита.

**Формат записи:**
```
timestamp|kind|source|files|doc_hint|note
```

**Примеры:**
```
1735689600|code|cursor|src/auth.ts|docs/features/|Added OAuth
1735689700|schema|hook|supabase/migrations/001.sql|docs/architecture/|New table: users
```

**Fallback:** `.queue0` для NUL-разделённых записей (если основная очередь повреждена)

### 6. Update Script (`.ai-docs-system/update.sh`)

**Назначение:** Самообновление системы из GitHub.

**Механизм:**
1. Скачивание tarball с GitHub (`$UPDATE_REF`, по умолчанию `main`)
2. Распаковка в temp
3. Merge конфига через `merge_config` (сохранение пользовательских настроек)
4. Замена скриптов и хуков
5. Пересборка AI-адаптеров

**Безопасность:**
- `UPDATE_SHA256` для верификации (опционально)
- `set -euo pipefail` для остановки при ошибках
- Self-copy механизм (exec) для безопасной замены running script

### 7. npm CLI Wrapper (`bin/cli.js`)

**Назначение:** Node.js обёртка для вызова bash/PowerShell скриптов из npm.

**Команды:**
- `npx ai-docs-system install <dir>`
- `npx ai-docs-system update <dir>`
- `npx ai-docs-system uninstall <dir>`
- `npx ai-docs-system audit <dir>`

**Технологии:** Node.js `child_process.spawn`

## Поток данных

```
┌─────────────────┐
│  User edits     │
│  src/auth.ts    │
└────────┬────────┘
         │
         ↓
┌─────────────────┐     ┌──────────────────┐
│  git commit     │────→│  pre-commit hook │
└─────────────────┘     └────────┬─────────┘
                                 │
                    ┌────────────┴─────────────┐
                    │                          │
                    ↓                          ↓
         ┌──────────────────┐      ┌─────────────────────┐
         │  Show reminder   │      │  Write to queue     │
         │  (не блокирует)  │      │  (if enabled)       │
         └──────────────────┘      └──────────┬──────────┘
                                              │
                                              ↓
                                   ┌────────────────────┐
                                   │  Cursor Agent      │
                                   │  reads queue via   │
                                   │  instructions.md   │
                                   └────────────────────┘
```

## Зависимости

### Runtime
- Git 2.x+
- Bash 4.0+ (macOS/Linux) или PowerShell 5.1+ (Windows)
- curl (для update)
- tar (для update)

### Опциональные
- Node.js 14+ (для npm-пакета)
- GitHub CLI (`gh`) — fallback для update если GitHub заблокирован

## Конфигурация Git Hooks

**Режимы установки:**

1. **managed** (по умолчанию)
   - Создаёт `.githooks/`
   - Устанавливает `git config core.hooksPath .githooks`
   - Полный контроль системы над папкой

2. **integrate**
   - Обнаружен существующий менеджер хуков
   - Копирует pre-commit в `.ai-docs-system/hooks/`
   - Пользователь должен добавить в свой менеджер:
     ```bash
     .ai-docs-system/hooks/pre-commit
     ```

## Безопасность

### RCE Prevention
- ❌ `eval` не используется
- ✅ Регулярные выражения экранируются через `csv_to_re`
- ✅ sed replacements через `escape_sed_replacement`
- ✅ git diff `-z` для безопасной обработки имён файлов

### Supply Chain
- `UPDATE_REF` для версионирования (pinning к тегу)
- `UPDATE_SHA256` для верификации целостности (опционально)

### Secrets
- Никогда не записываются в git
- Документируются паттерны доступа, а не сами пароли

## Связанное

- [Развёртывание](/docs/infrastructure/DEPLOY.md)
- [Конфигурация](/docs/features/config.md)
- [Спецификации](/docs/spec/README.md)
