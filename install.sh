#!/usr/bin/env bash
#
# AI Docs System — Скрипт установки / обновления
# https://github.com/Pixasso/ai-docs-system
#
set -euo pipefail

VERSION="2.4.1"
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
# Безопасное чтение конфигурации
# ═══════════════════════════════════════════════════════════════════════════════
get_config_value() {
  local file="$1" key="$2" default="$3"
  grep -E "^${key}=" "$file" 2>/dev/null | cut -d'=' -f2- | head -1 || echo "$default"
}

set_config_value() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    # Обновляем существующий ключ
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$file" 2>/dev/null || \
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$file" 2>/dev/null || true
    rm -f "${file}.bak"
  else
    # Добавляем новый ключ
    echo "${key}=${value}" >> "$file"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Экранирование для sed replacement (безопасная подстановка)
# ═══════════════════════════════════════════════════════════════════════════════
escape_sed_replacement() {
  local str="$1"
  # Экранируем \ → \\, затем & → \&, затем / → \/
  printf '%s' "$str" | sed 's/\\/\\\\/g; s/&/\\&/g; s/\//\\\//g'
}

# ═══════════════════════════════════════════════════════════════════════════════
# Справка
# ═══════════════════════════════════════════════════════════════════════════════
usage() {
  cat <<EOF
AI Docs System v${VERSION}

Использование: ./install.sh [ЦЕЛЕВАЯ_ПАПКА] [РЕЖИМ]

Аргументы:
  ЦЕЛЕВАЯ_ПАПКА   Путь к проекту (по умолчанию: текущая папка)
  РЕЖИМ           'install' (по умолчанию), 'update', 'uninstall' или 'audit'

Режимы:
  install    Полная установка (конфиг, хуки, шаблоны docs/, адаптеры)
  update     Обновление хуков и пересборка адаптеров (merge конфига)
  uninstall  Удаление модуля (docs/ сохраняется)
  audit      Проверка состояния документации

Примеры:
  ./install.sh /path/to/project           # Установка
  ./install.sh /path/to/project update    # Обновление
  ./install.sh /path/to/project uninstall # Удаление
  ./install.sh /path/to/project audit     # Аудит
  ./install.sh .                          # Установка в текущую папку

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
  
  # Загружаем конфиг безопасно (дефолт включает все стандартные правила)
  local rules_enabled="doc-first,update-docs,adr,shortcuts,structure,pending-write"
  if [[ -f "$config_file" ]]; then
    rules_enabled="$(get_config_value "$config_file" "RULES_ENABLED" "$rules_enabled")"
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
  
  # Загружаем конфиг безопасно
  local adapters="cursor"
  if [[ -f "$config_file" ]]; then
    adapters="$(get_config_value "$config_file" "ADAPTERS" "$adapters")"
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

# ═══════════════════════════════════════════════════════════════════════════════
# Установка git-хуков с поддержкой разных менеджеров
# ═══════════════════════════════════════════════════════════════════════════════
setup_hooks() {
  local target="$1"
  local config_file="$target/.ai-docs-system/config.env"
  local state_dir="$target/.ai-docs-system/state"
  
  # Получаем режим из конфига
  local hooks_mode="auto"
  if [[ -f "$config_file" ]]; then
    hooks_mode="$(get_config_value "$config_file" "HOOKS_MODE" "$hooks_mode")"
  fi
  
  # Проверяем текущий hooksPath
  local current_hooks_path="$(git -C "$target" config core.hooksPath 2>/dev/null || echo "")"
  
  # Режим off — пропускаем установку хуков
  if [[ "$hooks_mode" == "off" ]]; then
    log_warn "HOOKS_MODE=off — хуки не устанавливаются"
    return 0
  fi
  
  # Определяем режим: managed или integrate
  local actual_mode="$hooks_mode"
  if [[ "$hooks_mode" == "auto" ]]; then
    # Проверяем существующие хуки ПЕРЕД автоматическим переключением
    local has_existing_hooks=false
    
    # 1. Проверка .githooks/ на наличие файлов
    if [[ -d "$target/.githooks" ]] && ls "$target/.githooks/"* >/dev/null 2>&1; then
      has_existing_hooks=true
      log_warn "⚠ Обнаружены существующие хуки в .githooks/"
    fi
    
    # 2. Проверка .git/hooks/ (если core.hooksPath пуст → активна .git/hooks/)
    if [[ -z "$current_hooks_path" ]]; then
      if ls "$target/.git/hooks/"pre-* "$target/.git/hooks/"post-* "$target/.git/hooks/"commit-msg 2>/dev/null | grep -v ".sample" >/dev/null; then
        has_existing_hooks=true
        log_warn "⚠ Обнаружены существующие хуки в .git/hooks/"
      fi
    fi
    
    if [[ "$has_existing_hooks" == true ]]; then
      # Автоматически переключаемся на integrate (безопасный режим)
      actual_mode="integrate"
      log_warn "→ Автоматический режим: integrate (безопасная интеграция)"
    elif [[ -z "$current_hooks_path" || "$current_hooks_path" == ".githooks" ]]; then
      actual_mode="managed"
    else
      actual_mode="integrate"
    fi
  fi
  
  # Режим managed: полный контроль над хуками
  if [[ "$actual_mode" == "managed" ]]; then
    # Сохраняем предыдущий hooksPath (если был)
    mkdir -p "$state_dir"
    if [[ -n "$current_hooks_path" && "$current_hooks_path" != ".githooks" ]]; then
      echo "$current_hooks_path" > "$state_dir/prev-hooksPath"
    fi
    
    # Устанавливаем хуки
    mkdir -p "$target/.githooks"
    
    # Проверка на существующий pre-commit (бэкап если не наш)
    if [[ -f "$target/.githooks/pre-commit" ]]; then
      if ! grep -q "# AI Docs System" "$target/.githooks/pre-commit" 2>/dev/null; then
        # Не наш хук → создаём бэкап
        mv "$target/.githooks/pre-commit" "$target/.githooks/pre-commit.bak.$(date +%s)"
        log_warn "⚠ Существующий pre-commit переименован в .bak"
      fi
    fi
    
    cp -f "$SCRIPT_DIR/githooks/pre-commit" "$target/.githooks/pre-commit"
    chmod +x "$target/.githooks/pre-commit"
    
    if [[ -f "$SCRIPT_DIR/githooks/pre-commit.cmd" ]]; then
      cp -f "$SCRIPT_DIR/githooks/pre-commit.cmd" "$target/.githooks/pre-commit.cmd"
    fi
    
    # Создаём маркер-файл (для безопасного удаления при uninstall)
    touch "$target/.githooks/.ai-docs-system-managed"
    
    git -C "$target" config core.hooksPath .githooks
    log_info "Хуки установлены в .githooks/ (managed режим)"
    
  # Режим integrate: не трогаем hooksPath, предлагаем интеграцию
  else
    mkdir -p "$target/.ai-docs-system/hooks"
    cp -f "$SCRIPT_DIR/githooks/pre-commit" "$target/.ai-docs-system/hooks/pre-commit"
    chmod +x "$target/.ai-docs-system/hooks/pre-commit"
    
    log_warn "Обнаружен другой менеджер хуков (core.hooksPath = $current_hooks_path)"
    echo ""
    echo "Добавьте в ваш pre-commit хук одну строку:"
    echo ""
    echo "  .ai-docs-system/hooks/pre-commit || true"
    echo ""
    echo "Или смените режим на managed: HOOKS_MODE=managed в config.env"
    echo ""
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Кроссплатформенный парсинг дат
# ═══════════════════════════════════════════════════════════════════════════════
date_to_epoch() {
  local date_str="$1"  # YYYY-MM-DD
  
  # macOS (BSD date)
  if date -j -f "%Y-%m-%d" "$date_str" "+%s" 2>/dev/null; then
    return 0
  fi
  
  # Linux (GNU date)
  if date -d "$date_str" "+%s" 2>/dev/null; then
    return 0
  fi
  
  # Fallback: python3
  python3 -c "from datetime import datetime; print(int(datetime.strptime('$date_str', '%Y-%m-%d').timestamp()))" 2>/dev/null || echo "0"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Консервативный merge конфига (при update)
# ═══════════════════════════════════════════════════════════════════════════════
merge_config() {
  local target="$1"
  local default_config="$SCRIPT_DIR/.ai-docs-system/config.env"
  local user_config="$target/.ai-docs-system/config.env"
  local temp_config="$user_config.merge.tmp"
  
  [[ ! -f "$default_config" ]] && { log_warn "Дефолтный конфиг не найден"; return 1; }
  [[ ! -f "$user_config" ]] && { log_warn "Конфиг юзера не найден"; return 1; }
  
  log_step "Merge конфига (консервативный режим)..."
  
  # Читаем версионированные дефолты
  local defaults_v2_0="doc-first,update-docs,adr,shortcuts"
  local defaults_v2_1="doc-first,update-docs,adr,shortcuts,structure"
  local defaults_v2_2="$defaults_v2_1"
  local defaults_v2_3="doc-first,update-docs,adr,shortcuts,structure,pending-write"
  
  # Список всех ключей из дефолтного конфига (кроме комментариев)
  local keys
  keys=$(grep -E "^[A-Z_]+=" "$default_config" | cut -d'=' -f1 | sort -u)
  
  # Начинаем с существующего конфига юзера
  cp "$user_config" "$temp_config"
  
  local added=0
  local skipped=0
  
  # Добавляем отсутствующие ключи
  for key in $keys; do
    if ! grep -q "^${key}=" "$user_config"; then
      # Ключа нет у юзера — добавляем
      local default_value
      default_value=$(get_config_value "$default_config" "$key" "")
      
      # Находим комментарий перед ключом в дефолтном конфиге
      local comment_block
      comment_block=$(awk -v key="^${key}=" '
        /^# ─── / { header=$0; comments=""; next }
        /^# / { comments = comments $0 "\n"; next }
        $0 ~ key { 
          if (header) print header;
          if (comments) printf "%s", comments;
          exit
        }
        /^[A-Z_]+/ { comments="" }
      ' "$default_config")
      
      # Собираем новые ключи во временный файл
      {
        if [[ -n "$comment_block" ]]; then
          echo ""
          echo "$comment_block"
        fi
        echo "${key}=${default_value}"
      } >> "$temp_config.additions"
      
      ((added++))
      log_info "+ $key=${default_value}"
    else
      ((skipped++))
    fi
  done
  
  # ВАЖНО: Вставляем ВСЕ новые ключи ПЕРЕД блоком "Примеры кастомизации" (один раз)
  if [[ -f "$temp_config.additions" && -s "$temp_config.additions" ]]; then
    local insert_marker="# Примеры кастомизации под специфичные проекты"
    
    if grep -q "$insert_marker" "$temp_config"; then
      # Вставляем ПЕРЕД маркером (без awk — безопасно для UTF-8 и спецсимволов)
      {
        while IFS= read -r line || [[ -n "$line" ]]; do
          if [[ "$line" == "$insert_marker"* ]]; then
            cat "$temp_config.additions"
            echo ""
          fi
          printf '%s\n' "$line"
        done < "$temp_config"
      } > "$temp_config.new" && mv "$temp_config.new" "$temp_config"
    else
      # Fallback: в конец
      cat "$temp_config.additions" >> "$temp_config"
    fi
    
    rm -f "$temp_config.additions"
  fi
  
  # Специальная обработка RULES_ENABLED
  local user_rules
  user_rules=$(get_config_value "$user_config" "RULES_ENABLED" "")
  
  if [[ "$user_rules" == "$defaults_v2_0" || "$user_rules" == "$defaults_v2_1" || "$user_rules" == "$defaults_v2_2" ]]; then
    # Юзер на старом дефолте → безопасно обновить до v2_3
    sed -i.bak "s/^RULES_ENABLED=.*/RULES_ENABLED=$defaults_v2_3/" "$temp_config" 2>/dev/null || \
      sed -i '' "s/^RULES_ENABLED=.*/RULES_ENABLED=$defaults_v2_3/" "$temp_config" 2>/dev/null
    rm -f "$temp_config.bak"
    log_info "✓ RULES_ENABLED обновлён: $defaults_v2_3"
  elif [[ -z "$user_rules" ]]; then
    # Ключа нет вообще (добавлен выше из дефолта)
    :
  else
    # Юзер кастомизировал — показываем какие правила отсутствуют
    local default_rules_sorted user_rules_sorted missing_rules
    default_rules_sorted=$(echo "$defaults_v2_3" | tr ',' '\n' | sort)
    user_rules_sorted=$(echo "$user_rules" | tr ',' '\n' | sort)
    missing_rules=$(comm -23 <(echo "$default_rules_sorted") <(echo "$user_rules_sorted") | tr '\n' ',' | sed 's/,$//')
    
    if [[ -n "$missing_rules" ]]; then
      log_warn "⚠ RULES_ENABLED не обновлён (кастомизирован: $user_rules)"
      log_warn "  Новые правила доступны: $missing_rules"
      log_warn "  Добавьте вручную: RULES_ENABLED=$user_rules,$missing_rules"
    fi
  fi
  
  # Обновляем комментарий "# Доступные правила:" с актуальным списком
  local available_rules
  available_rules=$(ls "$target/.ai-docs-system/rules/"*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/.md$//' | tr '\n' ',' | sed 's/,$//')
  
  if [[ -n "$available_rules" ]]; then
    sed -i.bak "s|^# Доступные правила:.*|# Доступные правила: $available_rules|" "$temp_config" 2>/dev/null || \
      sed -i '' "s|^# Доступные правила:.*|# Доступные правила: $available_rules|" "$temp_config" 2>/dev/null
    rm -f "$temp_config.bak"
    log_info "✓ Комментарий 'Доступные правила' обновлён"
  fi
  
  # Обновляем комментарий "# Доступные адаптеры:" (фиксированный список)
  local available_adapters="cursor,copilot,claude,cline"
  sed -i.bak "s|^# Доступные адаптеры:.*|# Доступные адаптеры: $available_adapters|" "$temp_config" 2>/dev/null || \
    sed -i '' "s|^# Доступные адаптеры:.*|# Доступные адаптеры: $available_adapters|" "$temp_config" 2>/dev/null
  rm -f "$temp_config.bak"
  
  # Применяем изменения
  mv "$temp_config" "$user_config"
  
  echo ""
  log_info "Merge завершён: +$added новых, ~$skipped существующих"
  echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# Аудит проекта  
# ═══════════════════════════════════════════════════════════════════════════════
audit_project() {
  local target="$1"
  local config_file="$target/.ai-docs-system/config.env"
  
  [[ ! -f "$config_file" ]] && { log_error "Конфиг не найден: $config_file"; exit 1; }
  
  # Загружаем конфиг
  local code_dirs doc_dirs doc_exts ignore_dirs
  local pending_local pending_shared doc_stale_days doc_stale_max
  
  code_dirs=$(get_config_value "$config_file" "CODE_DIRS" "src,app,lib")
  doc_dirs=$(get_config_value "$config_file" "DOC_DIRS" "docs")
  doc_exts=$(get_config_value "$config_file" "DOC_EXTS" "md,mdx")
  ignore_dirs=$(get_config_value "$config_file" "IGNORE_DIRS" "node_modules,vendor,dist")
  pending_local=$(get_config_value "$config_file" "PENDING_UPDATES_LOCAL" ".ai-docs-system/state/pending-updates.queue")
  pending_shared=$(get_config_value "$config_file" "PENDING_UPDATES_SHARED" "")
  doc_stale_days=$(get_config_value "$config_file" "DOC_STALE_DAYS" "30")
  doc_stale_max=$(get_config_value "$config_file" "DOC_STALE_MAX" "5")
  
  echo ""
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║  AI Docs System — Аудит проекта                              ║"
  echo "╚═══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Проект: $target"
  echo "Конфиг: $config_file"
  echo ""
  
  local total_issues=0
  local pending_count=0
  local readme_count=0
  
  # ─── 1. Pending Updates ─────────────────────────────────────────────────────
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📋 Pending Updates"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Определяем абсолютный путь для local queue
  local queue_path
  if [[ "$pending_local" == /* ]]; then
    # Абсолютный путь → используем как есть
    queue_path="$pending_local"
  else
    # Относительный путь → добавляем $target
    queue_path="$target/$pending_local"
  fi
  
  # Local queue
  if [[ -f "$queue_path" ]]; then
    pending_count=$(wc -l < "$queue_path" | xargs)
    if [[ $pending_count -gt 0 ]]; then
      echo "  ⏳ $pending_count необработанных обновления:"
      echo ""
      
      local idx=1
      while IFS='|' read -r ts kind ref files_tab doc note; do
        local ts_human
        ts_human=$(date -r "$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || date -d "@$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
        
        local now_ts
        now_ts=$(date +%s)
        local age_sec=$((now_ts - ts))
        local age_human
        if [[ $age_sec -lt 3600 ]]; then
          age_human="$((age_sec / 60)) мин назад"
        elif [[ $age_sec -lt 86400 ]]; then
          age_human="$((age_sec / 3600)) ч назад"
        else
          age_human="$((age_sec / 86400)) дней назад"
        fi
        
        echo "  $idx. [local] $ts_human ($age_human)"
        
        IFS=$'\t' read -ra files_arr <<< "$files_tab"
        for f in "${files_arr[@]}"; do
          [[ -n "$f" ]] && echo "     • $f"
        done
        
        [[ -n "$doc" ]] && echo "     → $doc"
        
        echo ""
        ((idx++))
      done < "$queue_path"
      
      echo "  💡 Запустите: Cursor Agent → \"==\""
      echo ""
    else
      echo "  ✓ Нет необработанных обновлений"
      echo ""
    fi
  else
    echo "  ✓ Очередь не существует (нет обновлений)"
    echo ""
  fi
  
  # Shared queue (если есть)
  if [[ -n "$pending_shared" ]]; then
    # Определяем абсолютный путь для shared queue
    local shared_path
    if [[ "$pending_shared" == /* ]]; then
      shared_path="$pending_shared"
    else
      shared_path="$target/$pending_shared"
    fi
    
    if [[ -f "$shared_path" ]]; then
      local shared_count
      shared_count=$(wc -l < "$shared_path" | xargs)
      if [[ $shared_count -gt 0 ]]; then
      echo "  ⏳ $shared_count в shared очереди"
      ((pending_count += shared_count))
    fi
    fi
  fi
  
  # .queue0 (fallback) — ищем рядом с queue-файлами, а не через общий find
  local queue0_count=0
  
  # Проверяем .queue0 рядом с локальной очередью
  if [[ "$queue_path" == *.queue ]]; then
    local queue0_local="${queue_path%.queue}.queue0"
    [[ -f "$queue0_local" ]] && ((queue0_count++))
  fi
  
  # Проверяем .queue0 рядом с shared очередью
  if [[ -n "$pending_shared" ]]; then
    local shared_queue_path
    [[ "$pending_shared" == /* ]] && shared_queue_path="$pending_shared" || shared_queue_path="$target/$pending_shared"
    if [[ "$shared_queue_path" == *.queue ]]; then
      local queue0_shared="${shared_queue_path%.queue}.queue0"
      [[ -f "$queue0_shared" ]] && ((queue0_count++))
    fi
  fi
  
  if [[ $queue0_count -gt 0 ]]; then
    echo "  ⏳ $queue0_count .queue0 файлов (fallback)"
    ((pending_count += queue0_count))
  fi
  
  ((total_issues += pending_count))
  
  # ─── 2. Документы в коде ───────────────────────────────────────────────────────
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📁 Документы в коде"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Строим список корней кода (быстрый find — только по CODE_DIRS)
  local code_roots=()
  IFS=',' read -ra code_arr <<< "$code_dirs"
  for dir in "${code_arr[@]}"; do
    dir=$(echo "$dir" | xargs)
    [[ -n "$dir" && -d "$target/$dir" ]] && code_roots+=("$target/$dir")
  done
  
  # Строим prune для ignore_dirs (через массив для безопасности)
  local prune_args=()
  IFS=',' read -ra ignore_arr <<< "$ignore_dirs"
  for idir in "${ignore_arr[@]}"; do
    idir=$(echo "$idir" | xargs)
    [[ -n "$idir" ]] && prune_args+=("-name" "$idir" "-o")
  done
  [[ ${#prune_args[@]} -gt 0 ]] && unset 'prune_args[-1]'  # Убираем последний "-o"
  
  if [[ ${#code_roots[@]} -gt 0 ]]; then
    # Строим ext_args через массив
    local ext_args=()
    IFS=',' read -ra ext_arr <<< "$doc_exts"
    for ext in "${ext_arr[@]}"; do
      ext=$(echo "$ext" | xargs)
      [[ -n "$ext" ]] && ext_args+=("-name" "*.${ext}" "-o")
    done
    [[ ${#ext_args[@]} -gt 0 ]] && unset 'ext_args[-1]'  # Убираем последний "-o"
    
    # Строим find команду — ищем только в code_roots (быстрее чем весь репо)
    local find_args=("${code_roots[@]}")
    
    # Добавляем prune
    if [[ ${#prune_args[@]} -gt 0 ]]; then
      find_args+=("(" "${prune_args[@]}" ")" "-prune" "-o")
    fi
    
    # code_roots уже ограничивают область поиска
    find_args+=("-type" "f")
    
    # Добавляем ext_args
    if [[ ${#ext_args[@]} -gt 0 ]]; then
      find_args+=("(" "${ext_args[@]}" ")")
    fi
    
    find_args+=("-print0")
    
    readme_count=0
    while IFS= read -r -d '' f; do
      ((readme_count++))
      local rel_path="${f#$target/}"
      echo "  ⚠ $rel_path"
      echo "     → Переместить в: docs/"
      echo ""
    done < <(find "${find_args[@]}" 2>/dev/null)
    
    if [[ $readme_count -eq 0 ]]; then
      echo "  ✓ Документы в коде не найдены"
      echo ""
    fi
  else
    echo "  ⚠ CODE_DIRS не настроены (или папки не существуют)"
    echo ""
  fi
  
  ((total_issues += readme_count))
  
  # ─── Итого ──────────────────────────────────────────────────────────────────
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  if [[ $total_issues -eq 0 ]]; then
    echo "✅ Проблем не обнаружено! Проект в отличном состоянии."
  else
    echo "Итого проблем: $total_issues"
    [[ $pending_count -gt 0 ]] && echo "  • $pending_count pending updates"
    [[ $readme_count -gt 0 ]] && echo "  • $readme_count Документы в коде"
  fi
  
  echo ""
  
  return $total_issues
}

# ─── Cursor ─────────────────────────────────────────────────────────────────────
generate_cursor_rules() {
  local target="$1"
  local rules_file="$target/.cursorrules"
  local begin_marker="# BEGIN ai-docs-system"
  local end_marker="# END ai-docs-system"
  
  local block="$begin_marker
# AI Docs System v$VERSION — https://github.com/Pixasso/ai-docs-system
# НЕ редактируйте этот блок. Запустите install.sh update для обновления.

Прочитай и следуй инструкциям из \`.ai-docs-system/instructions.md\`
Конфигурация проекта: \`.ai-docs-system/config.env\`

$end_marker"
  
  if [[ -f "$rules_file" ]]; then
    if grep -q "$begin_marker" "$rules_file" && grep -q "$end_marker" "$rules_file"; then
      # Обновляем существующий блок через sed
      local tmp_file="${rules_file}.tmp"
      
      # Удаляем старый блок и вставляем новый
      sed -e "/$begin_marker/,/$end_marker/d" "$rules_file" > "$tmp_file"
      
      # Добавляем новый блок в начало
      {
        echo "$block"
        echo ""
        cat "$tmp_file"
      } > "$rules_file"
      
      rm -f "$tmp_file"
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

Прочитай и следуй инструкциям из \`.ai-docs-system/instructions.md`
Конфигурация проекта: \`.ai-docs-system/config.env`
EOF
  log_info ".github/copilot-instructions.md создан"
}

# ─── Claude Code ────────────────────────────────────────────────────────────────
generate_claude_rules() {
  local target="$1"
  cat > "$target/CLAUDE.md" <<'EOF'
# AI Docs System

Прочитай и следуй инструкциям из \`.ai-docs-system/instructions.md`
Конфигурация проекта: \`.ai-docs-system/config.env`
EOF
  log_info "CLAUDE.md создан"
}

# ─── Cline ──────────────────────────────────────────────────────────────────────
generate_cline_rules() {
  local target="$1"
  cat > "$target/.clinerules" <<'EOF'
# AI Docs System

Прочитай и следуй инструкциям из \`.ai-docs-system/instructions.md`
Конфигурация проекта: \`.ai-docs-system/config.env`
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
if ! command -v git >/dev/null 2>&1; then
  log_error "git не найден в PATH"
  exit 1
fi

if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  log_error "Не git-репозиторий: $TARGET"
  echo "Инициализируйте командой: git init"
  exit 1
fi

# Нормализуем TARGET до корня репозитория
repo_root="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -n "$repo_root" && "$repo_root" != "$TARGET" ]]; then
  log_warn "TARGET не корень репозитория, использую: $repo_root"
  TARGET="$repo_root"
fi

# Проверка режима
if [[ "$MODE" != "install" && "$MODE" != "update" && "$MODE" != "uninstall" && "$MODE" != "audit" ]]; then
  log_error "Неверный режим: $MODE (используйте 'install', 'update', 'uninstall' или 'audit')"
  usage
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Режим AUDIT
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$MODE" == "audit" ]]; then
  audit_project "$TARGET"
  exit $?
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Режим UNINSTALL
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$MODE" == "uninstall" ]]; then
echo ""
  echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}  AI Docs System — Удаление${NC}"
  echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo ""

  log_step "Удаление AI Docs System из $TARGET"
  
  # 1. Восстановление git hooksPath
  if [[ -f "$TARGET/.ai-docs-system/state/prev-hooksPath" ]]; then
    prev_hooks=$(cat "$TARGET/.ai-docs-system/state/prev-hooksPath")
    git -C "$TARGET" config core.hooksPath "$prev_hooks"
    log_info "Восстановлен git hooksPath: $prev_hooks"
  else
    git -C "$TARGET" config --unset core.hooksPath 2>/dev/null || true
    log_info "Сброшен git hooksPath"
  fi
  
  # 2. Удаление .githooks (только если managed режим)
  if [[ -f "$TARGET/.githooks/.ai-docs-system-managed" ]]; then
    # Маркер есть → мы создали эту папку, можно удалить
    rm -rf "$TARGET/.githooks"
    log_info "Удалена папка .githooks/ (managed режим)"
  elif [[ -d "$TARGET/.githooks" ]]; then
    # Маркера нет → возможно была до нас, удаляем только наши файлы
    if [[ -f "$TARGET/.githooks/pre-commit" ]]; then
      if grep -q "# AI Docs System" "$TARGET/.githooks/pre-commit" 2>/dev/null; then
        rm -f "$TARGET/.githooks/pre-commit"
        rm -f "$TARGET/.githooks/pre-commit.cmd"
        log_info "Удалён pre-commit (другие хуки сохранены)"
      fi
    fi
  fi
  
  # 2a. Удаление для integrate режима
  if [[ -d "$TARGET/.ai-docs-system/hooks" ]]; then
    rm -rf "$TARGET/.ai-docs-system/hooks"
    log_info "Удалена папка .ai-docs-system/hooks/ (integrate режим)"
  fi
  
  # 3. Удаление блоков из AI-файлов
  for ai_file in ".cursorrules" "CLAUDE.md" ".clinerules" ".github/copilot-instructions.md"; do
    file_path="$TARGET/$ai_file"
    if [[ -f "$file_path" ]]; then
      # Удаляем блок между # BEGIN ai-docs-system и # END ai-docs-system
      sed -i.bak '/# BEGIN ai-docs-system/,/# END ai-docs-system/d' "$file_path" 2>/dev/null || \
        sed -i '' '/# BEGIN ai-docs-system/,/# END ai-docs-system/d' "$file_path" 2>/dev/null || true
      rm -f "${file_path}.bak"
      log_info "Удалён блок из $ai_file"
    fi
  done
  
  # 4. Удаление .ai-docs-system/
  if [[ -d "$TARGET/.ai-docs-system" ]]; then
    rm -rf "$TARGET/.ai-docs-system"
    log_info "Удалена папка .ai-docs-system/"
  fi
  
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Удаление завершено!${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Сохранено:"
  echo "  • docs/ — ваша документация"
  echo ""
  echo "Удалено:"
  echo "  • .ai-docs-system/"
  echo "  • .githooks/ (если использовался)"
  echo "  • Блоки в AI-файлах"
  echo ""
  exit 0
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
    owner="$(git -C "$TARGET" config user.name 2>/dev/null || id -un 2>/dev/null || echo "unknown")"
    if [[ -n "$owner" ]]; then
      owner_escaped=$(escape_sed_replacement "$owner")
      sed -i.bak "s/@Pixasso/@$owner_escaped/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || \
        sed -i '' "s/@Pixasso/@$owner_escaped/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || true
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
  
  # Копируем update.sh
  cp -f "$SCRIPT_DIR/.ai-docs-system/update.sh" "$TARGET/.ai-docs-system/update.sh" 2>/dev/null || true
  chmod +x "$TARGET/.ai-docs-system/update.sh" 2>/dev/null || true
  log_info "update.sh скопирован"
else
  # При update — обновляем правила и шаблоны (не перезаписываем существующий конфиг)
  
  # Но если конфига нет вообще (миграция с v1) — создаём
  if [[ ! -f "$TARGET/.ai-docs-system/config.env" ]]; then
    cp "$SCRIPT_DIR/.ai-docs-system/config.env" "$TARGET/.ai-docs-system/config.env"
    owner="$(git -C "$TARGET" config user.name 2>/dev/null || id -un 2>/dev/null || echo "unknown")"
    if [[ -n "$owner" ]]; then
      owner_escaped=$(escape_sed_replacement "$owner")
      sed -i.bak "s/@Pixasso/@$owner_escaped/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || \
        sed -i '' "s/@Pixasso/@$owner_escaped/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || true
      rm -f "$TARGET/.ai-docs-system/config.env.bak"
    fi
    log_info "config.env создан (миграция с v1, owner: @${owner:-unknown})"
  else
    # Конфиг есть — мерджим новые ключи
    merge_config "$TARGET"
  fi
  
  cp -f "$SCRIPT_DIR/.ai-docs-system/rules/"*.md "$TARGET/.ai-docs-system/rules/" 2>/dev/null || true
  cp -f "$SCRIPT_DIR/.ai-docs-system/templates/"*.md "$TARGET/.ai-docs-system/templates/" 2>/dev/null || true
  cp -f "$SCRIPT_DIR/.ai-docs-system/update.sh" "$TARGET/.ai-docs-system/update.sh" 2>/dev/null || true
  chmod +x "$TARGET/.ai-docs-system/update.sh" 2>/dev/null || true
  log_info "Правила и шаблоны обновлены"
fi

# ─── 2. Сборка instructions.md ──────────────────────────────────────────────────
log_step "Сборка instructions.md..."
build_instructions "$TARGET"

# ─── 3. Установка хуков ─────────────────────────────────────────────────────────
log_step "Установка git-хуков..."
setup_hooks "$TARGET"

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
echo "  4. Обновление системы:"
echo "     cd \$PROJECT_ROOT && .ai-docs-system/update.sh"
echo ""