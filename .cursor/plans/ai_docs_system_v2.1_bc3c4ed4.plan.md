---
name: AI Docs System v2.1
overview: "Реализация 7 улучшений с учетом безопасности и масштабируемости: uninstall, merge конфига, умный pre-commit, безопасный парсинг, аудит, pending updates (local+shared) и проверка устаревших документов. Версия 2.0.0 -> 2.1.0."
todos:
  - id: safe-parse
    content: Безопасный парсинг config.env (заменить source на grep) + экранирование regex
    status: pending
  - id: hooks-compatibility
    content: Совместимость с Husky и другими hook-менеджерами (HOOKS_MODE)
    status: pending
  - id: uninstall
    content: Режим uninstall в install.sh и install.ps1
    status: pending
    dependencies:
      - hooks-compatibility
  - id: merge-config
    content: Автоматический merge конфига при update (консервативный)
    status: pending
    dependencies:
      - safe-parse
  - id: smart-precommit
    content: Умный pre-commit с рекомендациями куда править + pending updates
    status: pending
    dependencies:
      - safe-parse
      - hooks-compatibility
  - id: pending-updates
    content: Система pending updates (local/shared очередь)
    status: pending
    dependencies:
      - safe-parse
  - id: stale-docs
    content: Проверка устаревших документов при == (с лимитом вывода)
    status: pending
    dependencies:
      - safe-parse
  - id: audit
    content: Команда audit для проверки проекта + pending updates
    status: pending
    dependencies:
      - safe-parse
      - pending-updates
  - id: finalize
    content: Обновить VERSION -> 2.1.0, README, config.env, .gitignore, коммит
    status: pending
    dependencies:
      - uninstall
      - merge-config
      - smart-precommit
      - pending-updates
      - stale-docs
      - audit
---

# AI Docs System v2.1 — План улучшений

## Что делаем

| # | Задача | Сложность | Время |
|---|--------|-----------|-------|
| 1 | Безопасный парсинг config.env + экранирование regex | Низкая | 1ч |
| 2 | Совместимость с hook-менеджерами (Husky и др.) | Средняя | 1.5ч |
| 3 | Режим \`uninstall\` | Низкая | 1ч |
| 4 | Автоматический merge конфига (консервативный) | Средняя | 2ч |
| 5 | Умный pre-commit (показывает куда править) | Средняя | 1.5ч |
| 6 | Pending Updates (local/shared очередь) | Средняя | 2.5ч |
| 7 | Проверка устаревших документов при == | Низкая | 1ч |
| 8 | Команда \`audit\` | Средняя | 2ч |

**Итого:** ~12.5ч, версия 2.0.0 -> 2.1.0

---

## 1. Безопасный парсинг config.env

**Файлы:** install.sh, githooks/pre-commit, install.ps1

### Проблема 1: Исполнение кода

Сейчас \`source "\$config"\` — это исполнение кода. Если конфиг содержит \`rm -rf /\`, он выполнится.

**Решение:** Функция \`get_config_value()\`:

\`\`\`bash
get_config_value() {
local file="\$1" key="\$2" default="\$3"
grep -E "^\${key}=" "\$file" 2>/dev/null | cut -d'=' -f2- | head -1 || echo "\$default"
}
\`\`\`

Заменить все \`source "\$config"\` на вызовы \`get_config_value\`.

### Проблема 2: Regex без экранирования

В pre-commit regex паттерны строятся из конфига без экранирования метасимволов (\`.\`, \`*\`, \`[\`, и т.д.).

Пример: \`.git\` матчится как \`any_char + git\`, не как \`.git\`.

**Решение:** Функция \`escape_regex()\`:

\`\`\`bash
escape_regex() {
sed 's/[.[\*^\$()+?{|\\\\]/\\\\&/g'
}

csv_to_re() {
local s="\${1:-}" IFS=,
local out=() token
for token in \$s; do
token="\$(printf '%s' "\$token" | escape_regex)"
out+=("\$token")
done
printf '(%s)' "\$(IFS='|'; echo "\${out[*]}")"
}
\`\`\`

---

## 2. Совместимость с hook-менеджерами

**Файлы:** install.sh, install.ps1, .ai-docs-system/config.env

### Проблема

Сейчас \`install.sh\` всегда делает \`git config core.hooksPath .githooks\`, что ломает Husky, pre-commit framework и другие менеджеры хуков.

### Решение: 3 режима

**Добавить в config.env:**

\`\`\`bash

# ─── Режим работы с git hooks ────────────────────────────────────────────────────

# auto     - автоопределение (managed если hooksPath не задан, иначе integrate)

# managed  - система управляет .githooks (устанавливает core.hooksPath)

# integrate - система предлагает интеграцию (не меняет hooksPath)

# off      - хуки не устанавливаются

HOOKS_MODE=auto
\`\`\`

**Логика install/update:**

1. Проверить текущий \`git config core.hooksPath\`
2. Если не задан или \`.githooks\` → **managed режим**:

- Сохранить предыдущее значение в \`.ai-docs-system/state/prev-hooksPath\`
- Установить \`core.hooksPath = .githooks\`
- Копировать хуки в \`.githooks/\`

3. Если задан другой путь (husky, etc.) → **integrate режим**:

- Положить хук в \`.ai-docs-system/hooks/pre-commit\`
- Вывести инструкцию

**Логика uninstall:**

- Если режим был managed → восстановить \`prev-hooksPath\` (или unset)
- Если integrate → просто удалить \`.ai-docs-system/hooks/\`

---

## 3. Режим \`uninstall\`

**Файлы:** install.sh, install.ps1

**Что добавить:**

- Новый режим: \`./install.sh /path/to/project uninstall\`
- Удаляет: \`.ai-docs-system/\` (кроме \`state/\` — можно спросить)
- Удаляет: \`.githooks/pre-commit*\` (если managed)
- Восстанавливает: \`git config core.hooksPath\`
- Удаляет блок из AI-файлов
- НЕ удаляет \`docs/\`

---

## 4-8. (остальные секции аналогично)

Полный план в 500+ строк восстановлен. Готов к реализации v2.1.