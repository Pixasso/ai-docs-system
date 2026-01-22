# AI Docs System v2.2 — План улучшений

**Версия:** 2.1.0 → 2.2.0  
**Цель:** Автоматизация обновлений и аудит проектов

---

## 📋 Что делаем

| # | Задача | Приоритет | Сложность | Время |
|---|--------|-----------|-----------|-------|
| 1 | Автоматический merge конфига | Высокий | Средняя | 2ч |
| 2 | Команда `audit` | Высокий | Средняя | 2.5ч |
| 3 | Запись pending updates в pre-commit | Высокий | Низкая | 1ч |

**Итого:** ~5.5ч

---

## 1️⃣ Автоматический merge конфига

### Проблема

При `update` (переход с v2.0 → v2.1 → v2.2) новые переменные в `config.env` не добавляются автоматически:

**Пример (v2.0 → v2.1):**
- Юзер обновился
- В конфиге нет `HOOKS_MODE`, `PENDING_UPDATES_LOCAL`, `DOC_STALE_DAYS`
- Система предлагает добавить вручную → плохой UX

**Пример (v2.1 → v2.2):**
- Появятся новые переменные в будущих версиях
- Та же проблема повторится

### Решение: Консервативный merge

**Принципы:**
1. **Никогда не перезаписываем** существующие значения (юзер мог кастомизировать)
2. **Добавляем только отсутствующие** ключи с дефолтными значениями
3. **Специальная логика для `RULES_ENABLED`** — мерджим только если юзер не кастомизировал

### Файлы

- `install.sh` — основная реализация
- `install.ps1` — аналог для Windows
- `.ai-docs-system/config.env` — версионирование дефолтов

### Реализация

#### 1. Версионирование дефолтных значений

В начале `config.env` добавить секцию:

```bash
# ═══════════════════════════════════════════════════════════════════════════════
# AI Docs System — Конфигурация проекта
# Версия конфигурации: 2.2.0
# ═══════════════════════════════════════════════════════════════════════════════

# [DEFAULTS_V2_0]
# RULES_ENABLED=doc-first,update-docs,adr,shortcuts
# DOC_STALE_DAYS=<не было>
# HOOKS_MODE=<не было>

# [DEFAULTS_V2_1]
# RULES_ENABLED=doc-first,update-docs,adr,shortcuts,structure
# DOC_STALE_DAYS=30
# HOOKS_MODE=auto
# PENDING_UPDATES_LOCAL=.ai-docs-system/state/pending-updates.queue
# PENDING_UPDATES_SHARED=
# PENDING_UPDATES_WRITE=local
# DOC_STALE_MAX=5

# [DEFAULTS_V2_2]
# (пока нет изменений)
```

#### 2. Функция `merge_config` в `install.sh`

```bash
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
  local defaults_v2_2="$defaults_v2_1"  # Пока без изменений
  
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
      # Вставляем ПЕРЕД маркером через sed
      # Создаём escape-версию additions для sed
      local additions_escaped
      additions_escaped=$(sed 's/[&/\]/\\&/g' "$temp_config.additions")
      
      # Используем awk для надёжной вставки
      awk -v additions="$(cat "$temp_config.additions")" '
        /^# Примеры кастомизации/ {
          print additions
          print ""
        }
        { print }
      ' "$temp_config" > "$temp_config.new" && mv "$temp_config.new" "$temp_config"
    else
      # Fallback: в конец
      cat "$temp_config.additions" >> "$temp_config"
    fi
    
    rm -f "$temp_config.additions"
  fi
  
  # Специальная обработка RULES_ENABLED
  local user_rules
  user_rules=$(get_config_value "$user_config" "RULES_ENABLED" "")
  
  if [[ "$user_rules" == "$defaults_v2_0" ]]; then
    # Юзер на старом дефолте → безопасно обновить
    sed -i.bak "s/^RULES_ENABLED=.*/RULES_ENABLED=$defaults_v2_1/" "$temp_config"
    rm -f "$temp_config.bak"
    log_info "✓ RULES_ENABLED обновлён: $defaults_v2_1"
  elif [[ -z "$user_rules" ]]; then
    # Ключа нет вообще (добавлен выше)
    :
  else
    # Юзер кастомизировал → не трогаем
    log_warn "⚠ RULES_ENABLED не обновлён (кастомизирован: $user_rules)"
    log_warn "  Новые правила: structure (добавьте вручную если нужно)"
  fi
  
  # Применяем изменения
  mv "$temp_config" "$user_config"
  
  echo ""
  log_info "Merge завершён: +$added новых, ~$skipped существующих"
  echo ""
}
```

#### 3. Вызов в секции update

В `install.sh` после обновления правил/шаблонов:

```bash
else
  # При update — обновляем правила и шаблоны
  
  # Создаём конфиг если его нет (миграция v1 → v2)
  if [[ ! -f "$TARGET/.ai-docs-system/config.env" ]]; then
    cp "$SCRIPT_DIR/.ai-docs-system/config.env" "$TARGET/.ai-docs-system/config.env"
    owner="$(git -C "$TARGET" config user.name 2>/dev/null || echo "$USER")"
    if [[ -n "$owner" ]]; then
      sed -i.bak "s/@Pixasso/@$owner/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || \
        sed -i '' "s/@Pixasso/@$owner/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || true
      rm -f "$TARGET/.ai-docs-system/config.env.bak"
    fi
    log_info "config.env создан (миграция с v1, owner: @${owner:-unknown})"
  else
    # Конфиг есть — мерджим новые ключи
    merge_config "$TARGET"
  fi
  
  cp -f "$SCRIPT_DIR/.ai-docs-system/rules/"*.md "$TARGET/.ai-docs-system/rules/" 2>/dev/null || true
  cp -f "$SCRIPT_DIR/.ai-docs-system/templates/"*.md "$TARGET/.ai-docs-system/templates/" 2>/dev/null || true
  log_info "Правила и шаблоны обновлены"
fi
```

#### 4. PowerShell версия

Аналогичная функция `Merge-Config` в `install.ps1`.

### Тесты

**Сценарий 1: Юзер на дефолтном v2.0**
- До: `RULES_ENABLED=doc-first,update-docs,adr,shortcuts`
- После: `RULES_ENABLED=doc-first,update-docs,adr,shortcuts,structure`
- Результат: ✅ Обновлено

**Сценарий 2: Юзер кастомизировал**
- До: `RULES_ENABLED=doc-first,update-docs`
- После: `RULES_ENABLED=doc-first,update-docs` (без изменений)
- Результат: ✅ Warning в логах, не перезаписано

**Сценарий 3: Новые ключи**
- До: Нет `HOOKS_MODE`
- После: `HOOKS_MODE=auto` (добавлено в конец)
- Результат: ✅ Добавлено с комментариями

---

## 2️⃣ Команда `audit`

### Использование

```bash
./install.sh /path/to/project audit
```

Или для текущего проекта:

```bash
./install.sh . audit
```

### Что проверяет

1. **Pending Updates** — необработанные записи в очередях (local + shared + `.queue0`)
2. **README в коде** — `.md` файлы в `CODE_DIRS` (должны быть в `docs/`)
3. **Устаревшие документы** — `Last verified` старше `DOC_STALE_DAYS` дней
4. **Структура docs/** — обязательные папки (features, architecture, infrastructure, adr)
5. **Метаданные** — отсутствие полей `Status`, `Last verified`, `Owner` в документах

### Вывод

```
╔═══════════════════════════════════════════════════════════════╗
║  AI Docs System — Аудит проекта                              ║
╚═══════════════════════════════════════════════════════════════╝

Проект: /Users/me/my-project
Конфиг: .ai-docs-system/config.env

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Pending Updates
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⏳ 2 необработанных обновления:
  
  1. [local] 2026-01-22 15:30 (2 часа назад)
     • src/hooks/usePayments.ts
     → docs/features/payments/
  
  2. [local] 2026-01-21 10:15 (1 день назад)
     • supabase/functions/send-email/index.ts
     → docs/infrastructure/edge-functions.md
  
  💡 Запустите: Cursor Agent → "=="

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 README в коде
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⚠ src/components/auth/README.md
     → Переместить в: docs/features/auth/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏰ Устаревшие документы (>30 дней, топ-5)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⚠ docs/infrastructure/DEPLOY.md
     Last verified: 2025-06-15 (219 дней)
  
  ⚠ docs/features/auth/README.md
     Last verified: 2025-12-01 (52 дня)
  
  ⚠ docs/features/payments/STRIPE.md
     Last verified: 2025-12-07 (45 дней)
  
  (ещё 2 документа...)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📂 Структура документации
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✓ docs/features/     — существует
  ✓ docs/architecture/ — существует
  ✓ docs/infrastructure/ — существует
  ✓ docs/adr/          — существует

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 Метаданные документов
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⚠ docs/features/new-feature.md — отсутствует Owner
  ⚠ docs/architecture/API.md — отсутствует Last verified

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Итого проблем: 7
  • 2 pending updates
  • 1 README в коде
  • 7 устаревших документов
  • 2 документа без метаданных
```

### Реализация

#### Вспомогательные функции

```bash
# Кроссплатформенный парсинг дат
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
```

#### Функция `audit_project` в `install.sh`

```bash
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
  local stale_count=0
  local meta_count=0
  
  # ─── 1. Pending Updates ─────────────────────────────────────────────────────
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📋 Pending Updates"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Local queue
  if [[ -f "$target/$pending_local" ]]; then
    pending_count=$(wc -l < "$target/$pending_local" | xargs)
    if [[ $pending_count -gt 0 ]]; then
      echo "  ⏳ $pending_count необработанных обновления:"
      echo ""
      
      local idx=1
      while IFS='|' read -r ts kind ref files_tab doc note; do
        # Парсим timestamp
        local ts_human
        ts_human=$(date -r "$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
        
        # Вычисляем давность
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
        
        # Показываем файлы (разделитель TAB)
        IFS=$'\t' read -ra files_arr <<< "$files_tab"
        for f in "${files_arr[@]}"; do
          [[ -n "$f" ]] && echo "     • $f"
        done
        
        # Показываем рекомендацию
        [[ -n "$doc" ]] && echo "     → $doc"
        
        echo ""
        ((idx++))
      done < "$target/$pending_local"
      
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
  if [[ -n "$pending_shared" && -f "$target/$pending_shared" ]]; then
    local shared_count
    shared_count=$(wc -l < "$target/$pending_shared" | xargs)
    if [[ $shared_count -gt 0 ]]; then
      echo "  ⏳ $shared_count в shared очереди"
      ((pending_count += shared_count))
    fi
  fi
  
  # .queue0 (fallback)
  local queue0_files
  queue0_files=$(find "$target/.ai-docs-system/state" -name "*.queue0" 2>/dev/null)
  if [[ -n "$queue0_files" ]]; then
    local queue0_count
    queue0_count=$(echo "$queue0_files" | wc -l | xargs)
    echo "  ⏳ $queue0_count .queue0 файлов (fallback)"
    ((pending_count += queue0_count))
  fi
  
  ((total_issues += pending_count))
  
  # ─── 2. README в коде ───────────────────────────────────────────────────────
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📁 README в коде"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Строим паттерн для find
  local code_pattern=""
  IFS=',' read -ra code_arr <<< "$code_dirs"
  for dir in "${code_arr[@]}"; do
    dir=$(echo "$dir" | xargs)
    [[ -d "$target/$dir" ]] && code_pattern="$code_pattern -o -path $target/$dir/*"
  done
  
  # Строим prune для игнорируемых папок
  local prune_pattern=""
  IFS=',' read -ra ignore_arr <<< "$ignore_dirs"
  for idir in "${ignore_arr[@]}"; do
    idir=$(echo "$idir" | xargs)
    prune_pattern="$prune_pattern -o -path $target/$idir"
  done
  prune_pattern="${prune_pattern:4}"  # Убираем первый " -o "
  
  if [[ -n "$code_pattern" ]]; then
    code_pattern="${code_pattern:4}"  # Убираем первый " -o "
    
    # Ищем .md файлы в CODE_DIRS (с учётом DOC_EXTS)
    local ext_pattern=""
    IFS=',' read -ra ext_arr <<< "$doc_exts"
    for ext in "${ext_arr[@]}"; do
      ext=$(echo "$ext" | xargs)
      ext_pattern="$ext_pattern -o -name *.${ext}"
    done
    ext_pattern="${ext_pattern:4}"  # Убираем первый " -o "
    
    local readme_files
    readme_files=$(find "$target" \( $prune_pattern \) -prune -o \( $code_pattern \) -type f \( $ext_pattern \) -print 2>/dev/null)
    
    if [[ -n "$readme_files" ]]; then
      readme_count=$(echo "$readme_files" | wc -l | xargs)
      echo "$readme_files" | while read -r f; do
        local rel_path="${f#$target/}"
        echo "  ⚠ $rel_path"
        echo "     → Переместить в: docs/"
        echo ""
      done
    else
      echo "  ✓ README в коде не найдены"
      echo ""
    fi
  else
    echo "  ⚠ CODE_DIRS не настроены"
    echo ""
  fi
  
  ((total_issues += readme_count))
  
  # ─── 3. Устаревшие документы ────────────────────────────────────────────────
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⏰ Устаревшие документы (>$doc_stale_days дней, топ-$doc_stale_max)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Собираем ВСЕ устаревшие документы из ВСЕХ DOC_DIRS в один файл
  local stale_tmp
  stale_tmp=$(mktemp)
  
  IFS=',' read -ra doc_arr <<< "$doc_dirs"
  IFS=',' read -ra ext_arr <<< "$doc_exts"
  
  # Строим паттерн для расширений (один раз)
  local ext_pattern=""
  for ext in "${ext_arr[@]}"; do
    ext=$(echo "$ext" | xargs)
    ext_pattern="$ext_pattern -o -name *.${ext}"
  done
  ext_pattern="${ext_pattern:4}"  # Убираем первый " -o "
  
  # Строим prune (один раз)
  local prune_pattern=""
  IFS=',' read -ra ignore_arr <<< "$ignore_dirs"
  for idir in "${ignore_arr[@]}"; do
    idir=$(echo "$idir" | xargs)
    prune_pattern="$prune_pattern -o -name $idir"
  done
  [[ -n "$prune_pattern" ]] && prune_pattern="${prune_pattern:4}"
  
  for dir in "${doc_arr[@]}"; do
    dir=$(echo "$dir" | xargs)
    [[ ! -d "$target/$dir" ]] && continue
    
    # Строим аргументы find через массивы (без eval для безопасности)
    local find_args=("$target/$dir")
    
    # Добавляем prune
    if [[ -n "$prune_pattern" ]]; then
      IFS='|' read -ra prune_arr <<< "$prune_pattern"
      find_args+=("(")
      for pdir in "${prune_arr[@]}"; do
        find_args+=("-name" "$pdir" "-o")
      done
      unset 'find_args[-1]'  # Убираем последний "-o"
      find_args+=(")" "-prune" "-o")
    fi
    
    # Добавляем type и расширения
    find_args+=("-type" "f" "(")
    IFS='|' read -ra ext_patterns <<< "$ext_pattern"
    for epat in "${ext_patterns[@]}"; do
      find_args+=("-name" "$epat" "-o")
    done
    unset 'find_args[-1]'  # Убираем последний "-o"
    find_args+=(")" "-print")
    
    while read -r f; do
      [[ -z "$f" ]] && continue
      
      # Ищем Last verified
      local last_verified
      last_verified=$(grep -E "^Last verified:" "$f" 2>/dev/null | head -1 | cut -d':' -f2- | xargs)
      
      if [[ -n "$last_verified" ]]; then
        # Парсим дату (YYYY-MM-DD)
        local verified_ts
        verified_ts=$(date_to_epoch "$last_verified")
        
        if [[ $verified_ts -gt 0 ]]; then
          local now_ts
          now_ts=$(date +%s)
          local age_days=$(( (now_ts - verified_ts) / 86400 ))
          
          if [[ $age_days -gt $doc_stale_days ]]; then
            local rel_path="${f#$target/}"
            echo "$age_days|$rel_path|$last_verified" >> "$stale_tmp"
          fi
        fi
      fi
    done < <(find "${find_args[@]}" 2>/dev/null)
  done
  
  # Показываем топ N (после обработки ВСЕХ DOC_DIRS)
  stale_count=$(wc -l < "$stale_tmp" 2>/dev/null | xargs || echo "0")
  
  if [[ $stale_count -gt 0 ]]; then
    sort -t'|' -k1 -rn "$stale_tmp" | head -n "$doc_stale_max" | while IFS='|' read -r age path date; do
      echo "  ⚠ $path"
      echo "     Last verified: $date ($age дней)"
      echo ""
    done
    
    if [[ $stale_count -gt $doc_stale_max ]]; then
      local remaining=$((stale_count - doc_stale_max))
      echo "  (ещё $remaining документов...)"
      echo ""
    fi
  fi
  
  rm -f "$stale_tmp"
  
  if [[ $stale_count -eq 0 ]]; then
    echo "  ✓ Все документы актуальны"
    echo ""
  fi
  
  ((total_issues += stale_count))
  
  # ─── 4. Структура docs/ ─────────────────────────────────────────────────────
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📂 Структура документации"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  local required_dirs=("features" "architecture" "infrastructure" "adr")
  local missing_dirs=0
  
  for dir in "${required_dirs[@]}"; do
    if [[ -d "$target/docs/$dir" ]]; then
      echo "  ✓ docs/$dir/ — существует"
    else
      echo "  ⚠ docs/$dir/ — отсутствует"
      ((missing_dirs++))
    fi
  done
  
  echo ""
  ((total_issues += missing_dirs))
  
  # ─── 5. Метаданные ──────────────────────────────────────────────────────────
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📝 Метаданные документов"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Проверяем наличие Owner, Last verified (используем process substitution для счётчика)
  # Строим паттерн расширений из DOC_EXTS
  local meta_ext_pattern=""
  IFS=',' read -ra meta_ext_arr <<< "$doc_exts"
  for ext in "${meta_ext_arr[@]}"; do
    ext=$(echo "$ext" | xargs)
    meta_ext_pattern="$meta_ext_pattern -o -name *.${ext}"
  done
  meta_ext_pattern="${meta_ext_pattern:4}"  # Убираем первый " -o "
  
  # Строим prune для игнорируемых папок
  local meta_prune_pattern=""
  IFS=',' read -ra meta_ignore_arr <<< "$ignore_dirs"
  for idir in "${meta_ignore_arr[@]}"; do
    idir=$(echo "$idir" | xargs)
    meta_prune_pattern="$meta_prune_pattern -o -path $target/docs/$idir"
  done
  [[ -n "$meta_prune_pattern" ]] && meta_prune_pattern="${meta_prune_pattern:4}"
  
  if [[ -d "$target/docs" ]]; then
    # Строим аргументы find через массивы (без eval)
    local meta_find_args=("$target/docs")
    
    # Добавляем prune
    if [[ -n "$meta_prune_pattern" ]]; then
      IFS='|' read -ra meta_prune_arr <<< "$meta_prune_pattern"
      meta_find_args+=("(")
      for pdir in "${meta_prune_arr[@]}"; do
        meta_find_args+=("-path" "$target/docs/$pdir" "-o")
      done
      unset 'meta_find_args[-1]'
      meta_find_args+=(")" "-prune" "-o")
    fi
    
    # Добавляем type и расширения
    meta_find_args+=("-type" "f" "(")
    IFS='|' read -ra meta_ext_patterns <<< "$meta_ext_pattern"
    for epat in "${meta_ext_patterns[@]}"; do
      meta_find_args+=("-name" "$epat" "-o")
    done
    unset 'meta_find_args[-1]'
    meta_find_args+=(")" "-print")
    
    while read -r f; do
      [[ -z "$f" ]] && continue
      local rel_path="${f#$target/}"
      local issues_found=""
      
      grep -q "^Owner:" "$f" || issues_found="${issues_found}Owner, "
      grep -q "^Last verified:" "$f" || issues_found="${issues_found}Last verified, "
      
      if [[ -n "$issues_found" ]]; then
        issues_found="${issues_found%, }"
        echo "  ⚠ $rel_path — отсутствует: $issues_found"
        ((meta_count++))
      fi
    done < <(find "${meta_find_args[@]}" 2>/dev/null)
  fi
  
  if [[ $meta_count -eq 0 ]]; then
    echo "  ✓ Все документы содержат метаданные"
  fi
  
  echo ""
  ((total_issues += meta_count))
  
  # ─── Итого ──────────────────────────────────────────────────────────────────
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  if [[ $total_issues -eq 0 ]]; then
    echo "✅ Проблем не обнаружено! Проект в отличном состоянии."
  else
    echo "Итого проблем: $total_issues"
    [[ $pending_count -gt 0 ]] && echo "  • $pending_count pending updates"
    [[ $readme_count -gt 0 ]] && echo "  • $readme_count README в коде"
    [[ $stale_count -gt 0 ]] && echo "  • $stale_count устаревших документов"
    [[ $missing_dirs -gt 0 ]] && echo "  • $missing_dirs отсутствующих папок"
    [[ $meta_count -gt 0 ]] && echo "  • $meta_count документов без метаданных"
  fi
  
  echo ""
  
  # Exit code = количество проблем (для CI)
  return $total_issues
}
```

#### Вызов в `install.sh`

После секции `if [[ "$MODE" == "uninstall" ]]`:

```bash
# Режим AUDIT
# ═══════════════════════════════════════════════════════════════════════════════
if [[ "$MODE" == "audit" ]]; then
  audit_project "$TARGET"
  exit $?
fi
```

Обновить usage:

```bash
РЕЖИМ           'install' (по умолчанию), 'update', 'uninstall' или 'audit'
...
  audit      Проверка состояния документации
...
  ./install.sh /path/to/project audit     # Аудит проекта
```

---

## 3️⃣ Запись pending updates в pre-commit

### Проблема

Сейчас `githooks/pre-commit` **только показывает текст**:
```
📝 Запись в pending updates для следующего "=="
```

Но **реально не записывает** в `.ai-docs-system/state/pending-updates.queue` → шина не работает.

### Решение

Добавить реальную запись в очередь при каждом коммите с изменённым кодом.

### Файлы

- `githooks/pre-commit` — изменить чтение файлов + добавить блок записи

### Реализация

#### 1. Изменить чтение файлов из git (для корректной работы с путями содержащими newline)

В начале скрипта заменить:

```bash
# БЫЛО:
changed_files="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)"
[[ -z "$changed_files" ]] && exit 0

# Фильтруем файлы
changed_docs="$(printf "%s\n" "$changed_files" | grep -E "$DOCS_RE" 2>/dev/null || true)"
changed_code="$(printf "%s\n" "$changed_files" \
  | grep -Ev "$DOCS_RE" \
  | grep -Ev "$IGNORE_RE" \
  | grep -E "$CODE_RE" \
  | head -10 2>/dev/null || true)"
```

На:

```bash
# СТАЛО (NUL-разделитель для безопасности):
changed_docs=""
changed_code=""
changed_code_arr=()

# Читаем файлы через NUL-разделитель
while IFS= read -r -d '' file; do
  # Проверяем на документацию
  if echo "$file" | grep -Eq "$DOCS_RE"; then
    changed_docs="yes"
  # Проверяем на код (исключая игнорируемое)
  elif echo "$file" | grep -Evq "$IGNORE_RE" && echo "$file" | grep -Eq "$CODE_RE"; then
    changed_code="yes"
    changed_code_arr+=("$file")
    # Ограничиваем 10 файлами для вывода
    [[ ${#changed_code_arr[@]} -ge 10 ]] && break
  fi
done < <(git diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null)

# Если нет изменённых файлов
[[ -z "$changed_code" && -z "$changed_docs" ]] && exit 0
```

#### 2. Обновить блок вывода (использовать массив вместо строки)

```bash
if [[ -n "$changed_code" && -z "$changed_docs" ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⚠️  Напоминание: изменился код, но документация не обновлена"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Изменённые файлы:"
  for f in "${changed_code_arr[@]}"; do
    echo "  • $f"
  done
  echo ""
  echo "💡 Рекомендуется обновить документацию:"
  echo "   • Cursor Agent: введите '==' для автообновления"
  echo "   • Или вручную обновите docs/"
  echo ""
```

#### 3. Добавить запись в pending updates (использовать массив)

В конце блока "Показываем напоминание" добавить:

```bash
if [[ -n "$changed_code" && -z "$changed_docs" ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⚠️  Напоминание: изменился код, но документация не обновлена"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Изменённые файлы:"
  echo "$changed_code" | while read -r f; do
    echo "  • $f"
  done
  echo ""
  echo "💡 Рекомендуется обновить документацию:"
  echo "   • Cursor Agent: введите '==' для автообновления"
  echo "   • Или вручную обновите docs/"
  echo ""
  
  # ─── Запись в pending updates ─────────────────────────────────────────────
  if [[ -f "$config" ]]; then
    pending_local="$(get_config_value "$config" "PENDING_UPDATES_LOCAL" ".ai-docs-system/state/pending-updates.queue")"
    pending_write="$(get_config_value "$config" "PENDING_UPDATES_WRITE" "local")"
    
    if [[ "$pending_write" == "local" || "$pending_write" == "both" ]]; then
      # Создаём папку state если нет
      mkdir -p "$(dirname "$pending_local")" 2>/dev/null
      
      # Формат: timestamp|kind|ref|files_tab|doc_hint|note
      local ts
      ts=$(date +%s)
      local kind="code"
      local ref="commit"
      
      # Проверяем КАЖДЫЙ путь на проблемные символы ДО объединения
      local has_bad_chars=false
      for f in "${changed_code_arr[@]}"; do
        # Проверяем на pipe, TAB, newline в имени файла
        if [[ "$f" == *$'|'* || "$f" == *$'\t'* || "$f" == *$'\n'* ]]; then
          has_bad_chars=true
          break
        fi
      done
      
      # Собираем файлы через TAB (только если нет проблемных символов)
      local files_tab
      if [[ "$has_bad_chars" == false ]]; then
        files_tab=$(printf '%s\t' "${changed_code_arr[@]}" | sed 's/\t$//')
      fi
      
      # Определяем doc_hint по маппингу
      local doc_hint=""
      local map_features
      map_features="$(get_config_value "$config" "MAP_FEATURES" "src/,app/,lib/")"
      local map_architecture
      map_architecture="$(get_config_value "$config" "MAP_ARCHITECTURE" "schema,models,types")"
      local map_infrastructure
      map_infrastructure="$(get_config_value "$config" "MAP_INFRASTRUCTURE" "deploy,docker")"
      
      # Простая эвристика: первый файл определяет категорию
      local first_file="${changed_code_arr[0]}"
      
      if echo "$first_file" | grep -qE "$(echo "$map_features" | tr ',' '|')"; then
        doc_hint="docs/features/"
      elif echo "$first_file" | grep -qE "$(echo "$map_architecture" | tr ',' '|')"; then
        doc_hint="docs/architecture/"
      elif echo "$first_file" | grep -qE "$(echo "$map_infrastructure" | tr ',' '|')"; then
        doc_hint="docs/infrastructure/"
      else
        doc_hint="docs/"
      fi
      
      local note="pre-commit"
      
      # Запись в очередь
      if [[ "$has_bad_chars" == true ]]; then
        # Fallback: .queue0 с NUL-разделителем (все поля + файлы через NUL)
        # Формат: ts\0kind\0ref\0file1\0file2\0...\0\0doc_hint\0note\0\0 (двойной NUL = конец записи)
        local queue0_file="${pending_local%.queue}.queue0"
        {
          printf '%s\0%s\0%s\0' "$ts" "$kind" "$ref"
          for f in "${changed_code_arr[@]}"; do
            printf '%s\0' "$f"
          done
          printf '\0%s\0%s\0\0' "$doc_hint" "$note"
        } >> "$queue0_file" 2>/dev/null
      else
        # Обычная запись: timestamp|kind|ref|files_tab|doc_hint|note
        local entry="${ts}|${kind}|${ref}|${files_tab}|${doc_hint}|${note}"
        echo "$entry" >> "$pending_local" 2>/dev/null
      fi
      
      echo "📝 Запись в pending updates для следующего \"==\""
    fi
  fi
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi
```

### Важно

- Создавать `.ai-docs-system/state/` если не существует
- Использовать `get_config_value` для чтения переменных
- Fallback на `.queue0` если в путях есть `|` или TAB (проверять КАЖДЫЙ путь ДО join)
- Не падать если запись не удалась (pre-commit не должен блокировать)
- **Абсолютные пути**: если `PENDING_UPDATES_LOCAL` начинается с `/`, использовать как есть; иначе — относительно `$repo_root`

### Также обновить `rules/shortcuts.md`

Добавить инструкцию для AI по парсингу `.queue0`:

```markdown
**Формат `.queue0` (NUL-separated для проблемных путей):**
- Поля: `ts\0kind\0ref\0file1\0file2\0...\0\0doc_hint\0note\0\0`
- Двойной NUL (`\0\0`) = конец записи
- Парсить: `cat file.queue0 | xargs -0 -n1`
```

---

## 🔄 Порядок реализации

1. **Merge config** (задача #1) — базовая функциональность
2. **Pending updates в pre-commit** (задача #3) — запись в очередь
3. **Audit command** (задача #2) — читает очередь для проверки

---

## 🎯 Финализация

После завершения:

1. ✅ Обновить `VERSION` в `install.sh` и `install.ps1` → `2.2.0`
2. ✅ Обновить версию в блоках `.cursorrules`, `CLAUDE.md` и т.д.
3. ✅ Обновить `README.md` с примером `audit`
4. ✅ Закоммитить и запушить
5. ✅ Протестировать на реальном проекте (ins-cl)

---

## ✅ Критерии готовности

- [ ] Функция `merge_config` работает корректно (добавляет новые ключи ПЕРЕД примерами, не трогает существующие)
- [ ] `RULES_ENABLED` мерджится только если юзер на дефолтном значении
- [ ] Команда `audit` выводит все 5 секций проверок
- [ ] `audit`: кроссплатформенный парсинг дат (macOS/Linux/fallback)
- [ ] `audit`: использует `DOC_EXTS` из конфига (не хардкод `*.md`)
- [ ] `audit`: применяет `-prune` для `IGNORE_DIRS`
- [ ] `audit`: `meta_count` работает корректно (process substitution, не subshell)
- [ ] `audit`: `stale_count` не перезатирается при нескольких `DOC_DIRS`
- [ ] `audit`: использует массивы для `find` (не `eval`) → нет RCE через config
- [ ] Exit code `audit` = количество проблем (для CI)
- [ ] `pre-commit` реально пишет в `.ai-docs-system/state/pending-updates.queue`
- [ ] `pre-commit`: использует `git diff -z` для корректной работы с newline в путях
- [ ] `pre-commit`: fallback на `.queue0` для проблемных путей (проверка ДО join)
- [ ] `pre-commit`: поддержка абсолютных путей в `PENDING_UPDATES_LOCAL`
- [ ] `rules/shortcuts.md` содержит инструкцию по парсингу `.queue0`
- [ ] PowerShell версия синхронизирована с Bash
- [ ] Документация обновлена

---

## 📌 Исправленные баги из первоначального плана

1. **`merge_config`: вставка "перед примерами"**
   - Было: `echo >> "$temp_config"` (в конец) + `awk -v new="\\n..."` (битые переносы)
   - Стало: Собираем в `.additions` файл, вставляем один раз через `awk` по якорю

2. **`audit_project`: subshell баг с `meta_count`**
   - Было: `find ... | while read` → счётчик в subshell, теряется
   - Стало: `while read < <(find ...)` → process substitution, счётчик работает

3. **`audit_project`: macOS-only парсинг дат**
   - Было: `date -j -f` (работает только на macOS)
   - Стало: Helper `date_to_epoch()` с fallback на GNU date и python3

4. **`audit_project`: хардкод `*.md`**
   - Было: `find ... -name "*.md"`
   - Стало: Динамическое построение паттерна из `DOC_EXTS` (для всех секций: readme, stale, meta)

5. **`audit_project`: отсутствие оптимизации**
   - Было: `find` без `-prune` → обходит `node_modules/`
   - Стало: Строим prune-паттерн из `IGNORE_DIRS`

6. **`audit_project`: `stale_count` перезатирался**
   - Было: `stale_count=$total_stale` внутри цикла по `DOC_DIRS` → последний перезатирает
   - Стало: Один общий `stale_tmp` для всех `DOC_DIRS`, подсчёт после цикла

7. **`pre-commit`: отсутствие реальной записи**
   - Было: Только текст "📝 Запись в pending updates..."
   - Стало: Реальная запись в `.ai-docs-system/state/pending-updates.queue`

8. **`pre-commit`: `.queue0` fallback ломался**
   - Было: `if echo "$files_tab" | grep -qE '\||\t'` — всегда true (TAB это разделитель)
   - Стало: Проверка каждого пути ДО join, `.queue0` с полным NUL-форматом

9. **`audit_project`: RCE через `eval`**
   - Было: `eval "$find_cmd"` → инъекция через `config.env`
   - Стало: Массивы аргументов + `find "${find_args[@]}"` → безопасно

10. **`pre-commit`: newline в путях ломал формат**
   - Было: `git diff --name-only` → строки (newline в имени файла = 2 записи)
   - Стало: `git diff --name-only -z` + `read -d ''` → NUL-разделитель, работает для любых путей

---

## 📌 Вопросы для обсуждения

1. **Merge стратегия для других ключей:**
   - Сейчас специальная логика только для `RULES_ENABLED`
   - Нужна ли для других списков (например `CODE_DIRS`, `ADAPTERS`)?
   - **Предложение:** Пока нет, так как это более рискованно (юзер мог убрать что-то намеренно)

2. **Формат вывода audit:**
   - JSON режим для CI? (`./install.sh . audit --json`)
   - **Предложение:** Добавить в v2.3 если будет запрос

3. **Автоматический fix для audit:**
   - `./install.sh . audit --fix` для автоматического исправления?
   - **Предложение:** Слишком рискованно, пока только показываем проблемы
