#!/usr/bin/env bash
#
# AI Docs System — Скрипт установки / обновления
# https://github.com/Pixasso/ai-docs-system
#
set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Без цвета

usage() {
  echo "AI Docs System v${VERSION}"
  echo ""
  echo "Использование: ./install.sh [ЦЕЛЕВАЯ_ПАПКА] [РЕЖИМ]"
  echo ""
  echo "Аргументы:"
  echo "  ЦЕЛЕВАЯ_ПАПКА   Путь к проекту (по умолчанию: текущая папка)"
  echo "  РЕЖИМ           'install' (по умолчанию) или 'update'"
  echo ""
  echo "Примеры:"
  echo "  ./install.sh /path/to/project         # Установка"
  echo "  ./install.sh /path/to/project update  # Обновление только хуков и правил"
  echo "  ./install.sh .                        # Установка в текущую папку"
}

log_info() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

# Разбор аргументов
TARGET="${1:-.}"
MODE="${2:-install}"

# Преобразуем в абсолютный путь
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
  log_error "Папка не найдена: $1"
  exit 1
}

# Проверка
if [[ ! -d "$TARGET/.git" ]]; then
  log_error "Не git-репозиторий: $TARGET"
  echo "Инициализируйте командой: git init"
  exit 1
fi

if [[ "$MODE" != "install" && "$MODE" != "update" ]]; then
  log_error "Неверный режим: $MODE (используйте 'install' или 'update')"
  usage
  exit 1
fi

echo ""
echo "AI Docs System v${VERSION}"
echo "Цель: $TARGET"
echo "Режим: $MODE"
echo ""

# 1. Установка хуков
mkdir -p "$TARGET/.githooks"
cp -f "$SCRIPT_DIR/githooks/pre-commit" "$TARGET/.githooks/pre-commit"
chmod +x "$TARGET/.githooks/pre-commit"

# Windows хук (если существует)
if [[ -f "$SCRIPT_DIR/githooks/pre-commit.cmd" ]]; then
  cp -f "$SCRIPT_DIR/githooks/pre-commit.cmd" "$TARGET/.githooks/pre-commit.cmd"
fi

# Настраиваем git на использование .githooks
git -C "$TARGET" config core.hooksPath .githooks
log_info "Хуки установлены в .githooks/"

# 2. Обновление .cursorrules (управляемый блок)
BEGIN_MARKER="# BEGIN ai-docs-system"
END_MARKER="# END ai-docs-system"

BLOCK=$(cat <<'EOF'
# BEGIN ai-docs-system
# AI Docs System — https://github.com/Pixasso/ai-docs-system
# НЕ редактируйте этот блок вручную. Запустите install.sh update для обновления.

## Шорткаты

**"=="** — обнови документацию с учётом последних изменений в коде:
1. Найди изменённые файлы в `src/`, `services/`
2. Определи какие документы в `docs/` нужно обновить
3. Предложи конкретные изменения с diff
4. Примени после approval

---

## Doc-first (ОБЯЗАТЕЛЬНО)

Перед любым ответом или изменением кода:
1. Сначала прочитай `/docs/README.md` (точка входа)
2. Найди и прочитай релевантные документы в `/docs/**`
3. Если документация есть — следуй ей
4. Если документация устарела/противоречит коду — явно скажи и предложи diff на обновление

---

## Автоматические напоминания

- При изменении `src/`, `services/` — ВСЕГДА предлагай обновить `docs/`
- При архитектурных решениях — предлагай создать `docs/adr/NNNN-название.md`

---

## Метаданные документов

Каждый новый документ начинай с:
```markdown
> **Status:** current | draft | legacy
> **Last verified:** YYYY-MM-DD
> **Owner:** @Pixasso
```

# END ai-docs-system
EOF
)

RULES_FILE="$TARGET/.cursorrules"

if [[ -f "$RULES_FILE" ]]; then
  EXISTING=$(cat "$RULES_FILE")
  
  if grep -q "$BEGIN_MARKER" "$RULES_FILE" && grep -q "$END_MARKER" "$RULES_FILE"; then
    # Обновляем существующий блок
    # Используем awk для надёжной многострочной замены
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v block="$BLOCK" '
      $0 ~ begin { skip=1; print block; next }
      $0 ~ end { skip=0; next }
      !skip { print }
    ' "$RULES_FILE" > "$RULES_FILE.tmp" && mv "$RULES_FILE.tmp" "$RULES_FILE"
    log_info ".cursorrules обновлён (блок заменён)"
  else
    # Добавляем блок
    echo "" >> "$RULES_FILE"
    echo "$BLOCK" >> "$RULES_FILE"
    log_info ".cursorrules обновлён (блок добавлен)"
  fi
else
  # Создаём новый файл
  echo "$BLOCK" > "$RULES_FILE"
  log_info ".cursorrules создан"
fi

# 3. Установка шаблона docs (только при первой установке)
if [[ "$MODE" == "install" ]]; then
  DOCS_SRC="$SCRIPT_DIR/docs-template"
  DOCS_DST="$TARGET/docs"
  
  if [[ -d "$DOCS_SRC" ]]; then
    if [[ ! -d "$DOCS_DST" ]] || [[ -z "$(ls -A "$DOCS_DST" 2>/dev/null)" ]]; then
      mkdir -p "$DOCS_DST"
      cp -R "$DOCS_SRC/"* "$DOCS_DST/" 2>/dev/null || true
      log_info "Структура docs/ создана из шаблона"
    else
      log_warn "docs/ уже существует, пропускаем шаблон (используйте 'update' для обновления только хуков/правил)"
    fi
  fi
fi

echo ""
echo -e "${GREEN}Готово!${NC}"
echo ""
echo "Следующие шаги:"
echo "  1. Коммит: git add .githooks .cursorrules docs/ && git commit -m 'chore: добавить ai-docs-system'"
echo "  2. Тест: измените что-то в src/, закоммитьте, увидите напоминание"
echo "  3. Используйте Cursor Agent (Cmd+Shift+I) и введите '==' для автообновления документации"
echo ""
