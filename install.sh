#!/usr/bin/env bash
#
# AI Docs System — Скрипт установки / обновления
# https://github.com/Pixasso/ai-docs-system
#
set -euo pipefail

VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ═══════════════════════════════════════════════════════════════════════════════
# Цвета
# ═══════════════════════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════════════════════
# Функции логирования
# ═══════════════════════════════════════════════════════════════════════════════
log_info()  { echo -e "${GREEN}✓${NC} $1"; }
log_warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step()  { echo -e "${BLUE}→${NC} $1"; }

# ═══════════════════════════════════════════════════════════════════════════════
# Справка
# ═══════════════════════════════════════════════════════════════════════════════
usage() {
  cat <<EOF
AI Docs System v${VERSION}

Использование: ./install.sh [ЦЕЛЕВАЯ_ПАПКА] [РЕЖИМ]

Аргументы:
  ЦЕЛЕВАЯ_ПАПКА   Путь к проекту (по умолчанию: текущая папка)
  РЕЖИМ           'install' (по умолчанию) или 'update'

Режимы:
  install   Полная установка (конфиг, хуки, шаблоны docs/, адаптеры)
  update    Обновление хуков и пересборка адаптеров (без перезаписи конфига)

Примеры:
  ./install.sh /path/to/project         # Установка
  ./install.sh /path/to/project update  # Обновление
  ./install.sh .                        # Установка в текущую папку

Конфигурация: .ai-docs-system/config.env
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# Сборка instructions.md из включённых правил
# ═══════════════════════════════════════════════════════════════════════════════
build_instructions() {
  local target="$1"
  local config_file="$target/.ai-docs-system/config.env"
  local rules_dir="$target/.ai-docs-system/rules"
  local output_file="$target/.ai-docs-system/instructions.md"
  
  # Загружаем конфиг
  local rules_enabled="doc-first,update-docs,adr,shortcuts"
  if [[ -f "$config_file" ]]; then
    # shellcheck disable=SC1090
    source "$config_file"
    rules_enabled="${RULES_ENABLED:-$rules_enabled}"
  fi
  
  # Создаём заголовок
  cat > "$output_file" <<'HEADER'
# AI Docs System — Инструкции

> **Конфигурация:** `.ai-docs-system/config.env`  
> **Шаблоны:** `.ai-docs-system/templates/`

---

<!-- АВТОМАТИЧЕСКИ СОБРАНО ИЗ rules/ -->
<!-- Редактируйте rules/*.md и запустите install.sh update для пересборки -->

HEADER

  # Добавляем включённые правила
  IFS=',' read -ra rules <<< "$rules_enabled"
  for rule in "${rules[@]}"; do
    rule=$(echo "$rule" | xargs)  # trim
    local rule_file="$rules_dir/${rule}.md"
    if [[ -f "$rule_file" ]]; then
      cat "$rule_file" >> "$output_file"
      echo -e "\n---\n" >> "$output_file"
    fi
  done
  
  log_info "instructions.md собран (правила: $rules_enabled)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Генерация адаптеров для разных AI
# ═══════════════════════════════════════════════════════════════════════════════
generate_adapters() {
  local target="$1"
  local config_file="$target/.ai-docs-system/config.env"
  
  # Загружаем конфиг
  local adapters="cursor"
  if [[ -f "$config_file" ]]; then
    # shellcheck disable=SC1090
    source "$config_file"
    adapters="${ADAPTERS:-$adapters}"
  fi
  
  IFS=',' read -ra adapter_list <<< "$adapters"
  for adapter in "${adapter_list[@]}"; do
    adapter=$(echo "$adapter" | xargs)  # trim
    case "$adapter" in
      cursor)
        generate_cursor_rules "$target"
        ;;
      copilot)
        generate_copilot_rules "$target"
        ;;
      claude)
        generate_claude_rules "$target"
        ;;
      cline)
        generate_cline_rules "$target"
        ;;
      *)
        log_warn "Неизвестный адаптер: $adapter"
        ;;
    esac
  done
}

# ─── Cursor ─────────────────────────────────────────────────────────────────────
generate_cursor_rules() {
  local target="$1"
  local rules_file="$target/.cursorrules"
  local begin_marker="# BEGIN ai-docs-system"
  local end_marker="# END ai-docs-system"
  
  local block
  block=$(cat <<'EOF'
# BEGIN ai-docs-system
# AI Docs System v2.0 — https://github.com/Pixasso/ai-docs-system
# НЕ редактируйте этот блок. Запустите install.sh update для обновления.

Прочитай и следуй инструкциям из `.ai-docs-system/instructions.md`
Конфигурация проекта: `.ai-docs-system/config.env`

# END ai-docs-system
EOF
)
  
  if [[ -f "$rules_file" ]]; then
    if grep -q "$begin_marker" "$rules_file" && grep -q "$end_marker" "$rules_file"; then
      # Обновляем существующий блок
      awk -v begin="$begin_marker" -v end="$end_marker" -v block="$block" '
        $0 ~ begin { skip=1; print block; next }
        $0 ~ end { skip=0; next }
        !skip { print }
      ' "$rules_file" > "$rules_file.tmp" && mv "$rules_file.tmp" "$rules_file"
      log_info ".cursorrules обновлён"
    else
      # Добавляем блок
      echo "" >> "$rules_file"
      echo "$block" >> "$rules_file"
      log_info ".cursorrules дополнен"
    fi
  else
    echo "$block" > "$rules_file"
    log_info ".cursorrules создан"
  fi
}

# ─── GitHub Copilot ─────────────────────────────────────────────────────────────
generate_copilot_rules() {
  local target="$1"
  mkdir -p "$target/.github"
  cat > "$target/.github/copilot-instructions.md" <<'EOF'
# AI Docs System

Прочитай и следуй инструкциям из `.ai-docs-system/instructions.md`
Конфигурация проекта: `.ai-docs-system/config.env`
EOF
  log_info ".github/copilot-instructions.md создан"
}

# ─── Claude Code ────────────────────────────────────────────────────────────────
generate_claude_rules() {
  local target="$1"
  cat > "$target/CLAUDE.md" <<'EOF'
# AI Docs System

Прочитай и следуй инструкциям из `.ai-docs-system/instructions.md`
Конфигурация проекта: `.ai-docs-system/config.env`
EOF
  log_info "CLAUDE.md создан"
}

# ─── Cline ──────────────────────────────────────────────────────────────────────
generate_cline_rules() {
  local target="$1"
  cat > "$target/.clinerules" <<'EOF'
# AI Docs System

Прочитай и следуй инструкциям из `.ai-docs-system/instructions.md`
Конфигурация проекта: `.ai-docs-system/config.env`
EOF
  log_info ".clinerules создан"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Основная логика
# ═══════════════════════════════════════════════════════════════════════════════

# Разбор аргументов
TARGET="${1:-.}"
MODE="${2:-install}"

# Показать справку
if [[ "$TARGET" == "-h" || "$TARGET" == "--help" ]]; then
  usage
  exit 0
fi

# Преобразуем в абсолютный путь
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
  log_error "Папка не найдена: $1"
  exit 1
}

# Проверка git
if [[ ! -d "$TARGET/.git" ]]; then
  log_error "Не git-репозиторий: $TARGET"
  echo "Инициализируйте командой: git init"
  exit 1
fi

# Проверка режима
if [[ "$MODE" != "install" && "$MODE" != "update" ]]; then
  log_error "Неверный режим: $MODE (используйте 'install' или 'update')"
  usage
  exit 1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  AI Docs System v${VERSION}                                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Цель: $TARGET"
echo "Режим: $MODE"
echo ""

# ─── 1. Установка .ai-docs-system/ ──────────────────────────────────────────────
log_step "Настройка .ai-docs-system/..."

mkdir -p "$TARGET/.ai-docs-system/rules"
mkdir -p "$TARGET/.ai-docs-system/templates"

if [[ "$MODE" == "install" ]]; then
  # При install — копируем всё
  if [[ ! -f "$TARGET/.ai-docs-system/config.env" ]]; then
    cp "$SCRIPT_DIR/.ai-docs-system/config.env" "$TARGET/.ai-docs-system/config.env"
    
    # Подставляем владельца из git config
    owner="$(git -C "$TARGET" config user.name 2>/dev/null || echo "$USER")"
    if [[ -n "$owner" ]]; then
      sed -i.bak "s/@Pixasso/@$owner/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || \
        sed -i '' "s/@Pixasso/@$owner/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || true
      rm -f "$TARGET/.ai-docs-system/config.env.bak"
      log_info "config.env создан (owner: @$owner)"
    else
      log_info "config.env создан"
    fi
  else
    log_warn "config.env уже существует, пропускаем"
  fi
  
  # Копируем правила (при install — все)
  cp -f "$SCRIPT_DIR/.ai-docs-system/rules/"*.md "$TARGET/.ai-docs-system/rules/" 2>/dev/null || true
  log_info "Правила скопированы в rules/"
  
  # Копируем шаблоны
  cp -f "$SCRIPT_DIR/.ai-docs-system/templates/"*.md "$TARGET/.ai-docs-system/templates/" 2>/dev/null || true
  log_info "Шаблоны скопированы в templates/"
else
  # При update — обновляем правила и шаблоны (не перезаписываем существующий конфиг)
  
  # Но если конфига нет вообще (миграция с v1) — создаём
  if [[ ! -f "$TARGET/.ai-docs-system/config.env" ]]; then
    cp "$SCRIPT_DIR/.ai-docs-system/config.env" "$TARGET/.ai-docs-system/config.env"
    owner="$(git -C "$TARGET" config user.name 2>/dev/null || echo "$USER")"
    if [[ -n "$owner" ]]; then
      sed -i.bak "s/@Pixasso/@$owner/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || \
        sed -i '' "s/@Pixasso/@$owner/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || true
      rm -f "$TARGET/.ai-docs-system/config.env.bak"
    fi
    log_info "config.env создан (миграция с v1, owner: @${owner:-unknown})"
  fi
  
  cp -f "$SCRIPT_DIR/.ai-docs-system/rules/"*.md "$TARGET/.ai-docs-system/rules/" 2>/dev/null || true
  cp -f "$SCRIPT_DIR/.ai-docs-system/templates/"*.md "$TARGET/.ai-docs-system/templates/" 2>/dev/null || true
  log_info "Правила и шаблоны обновлены"
fi

# ─── 2. Сборка instructions.md ──────────────────────────────────────────────────
log_step "Сборка instructions.md..."
build_instructions "$TARGET"

# ─── 3. Установка хуков ─────────────────────────────────────────────────────────
log_step "Установка git-хуков..."

mkdir -p "$TARGET/.githooks"
cp -f "$SCRIPT_DIR/githooks/pre-commit" "$TARGET/.githooks/pre-commit"
chmod +x "$TARGET/.githooks/pre-commit"

if [[ -f "$SCRIPT_DIR/githooks/pre-commit.cmd" ]]; then
  cp -f "$SCRIPT_DIR/githooks/pre-commit.cmd" "$TARGET/.githooks/pre-commit.cmd"
fi

git -C "$TARGET" config core.hooksPath .githooks
log_info "Хуки установлены в .githooks/"

# ─── 4. Генерация адаптеров ─────────────────────────────────────────────────────
log_step "Генерация адаптеров для AI..."
generate_adapters "$TARGET"

# ─── 5. Установка шаблона docs/ (только при install) ────────────────────────────
if [[ "$MODE" == "install" ]]; then
  log_step "Установка шаблона документации..."
  
  DOCS_SRC="$SCRIPT_DIR/docs-template"
  DOCS_DST="$TARGET/docs"
  
  if [[ -d "$DOCS_SRC" ]]; then
    if [[ ! -d "$DOCS_DST" ]] || [[ -z "$(ls -A "$DOCS_DST" 2>/dev/null)" ]]; then
      mkdir -p "$DOCS_DST"
      cp -R "$DOCS_SRC/"* "$DOCS_DST/" 2>/dev/null || true
      log_info "Структура docs/ создана из шаблона"
    else
      log_warn "docs/ уже существует, пропускаем"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Готово
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Готово!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Следующие шаги:"
echo ""
echo "  1. Проверьте конфигурацию:"
echo "     ${BLUE}.ai-docs-system/config.env${NC}"
echo ""
echo "  2. Закоммитьте изменения:"
echo "     git add .ai-docs-system .githooks .cursorrules docs/"
echo "     git commit -m 'chore: добавить ai-docs-system'"
echo ""
echo "  3. Используйте:"
echo "     • Измените код → при коммите увидите напоминание"
echo "     • Cursor Agent: введите '==' для автообновления доки"
echo ""
