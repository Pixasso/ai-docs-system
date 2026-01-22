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
      
      # ВАЖНО: Вставляем ПЕРЕД блоком "Примеры кастомизации"
      local insert_marker="# ═══════════════════════════════════════════════════════════════════════════════"
      local insert_marker_line="# Примеры кастомизации под специфичные проекты"
      
      # Ищем строку с маркером примеров
      if grep -q "^$insert_marker" "$temp_config" && grep -q "^$insert_marker_line" "$temp_config"; then
        # Вставляем ПЕРЕД маркером
        local new_content
        if [[ -n "$comment_block" ]]; then
          new_content="\\n${comment_block}\\n${key}=${default_value}\\n"
        else
          new_content="\\n${key}=${default_value}\\n"
        fi
        
        # Используем awk для вставки перед маркером
        awk -v marker="$insert_marker" -v new="$new_content" '
          $0 ~ marker { 
            found = 1
          }
          found && $0 ~ /Примеры кастомизации/ {
            printf "%s", new
            found = 0
          }
          { print }
        ' "$temp_config" > "$temp_config.new" && mv "$temp_config.new" "$temp_config"
      else
        # Fallback: в конец
        if [[ -n "$comment_block" ]]; then
          echo "" >> "$temp_config"
          echo "$comment_block" >> "$temp_config"
        fi
        echo "${key}=${default_value}" >> "$temp_config"
      fi
      
      ((added++))
      log_info "+ $key=${default_value}"
    else
      ((skipped++))
    fi
  done
  
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
  
  # Ищем все документы в DOC_DIRS с нужными расширениями
  local doc_files=""
  IFS=',' read -ra doc_arr <<< "$doc_dirs"
  IFS=',' read -ra ext_arr <<< "$doc_exts"
  
  for dir in "${doc_arr[@]}"; do
    dir=$(echo "$dir" | xargs)
    if [[ -d "$target/$dir" ]]; then
      # Строим паттерн для расширений
      local ext_pattern=""
      for ext in "${ext_arr[@]}"; do
        ext=$(echo "$ext" | xargs)
        ext_pattern="$ext_pattern -o -name *.${ext}"
      done
      ext_pattern="${ext_pattern:4}"  # Убираем первый " -o "
      
      # Ищем файлы с prune
      local prune_pattern=""
      IFS=',' read -ra ignore_arr <<< "$ignore_dirs"
      for idir in "${ignore_arr[@]}"; do
        idir=$(echo "$idir" | xargs)
        prune_pattern="$prune_pattern -o -path $target/$idir"
      done
      prune_pattern="${prune_pattern:4}"
      
      doc_files=$(find "$target/$dir" \( $prune_pattern \) -prune -o -type f \( $ext_pattern \) -print 2>/dev/null)
      
      if [[ -n "$doc_files" ]]; then
        # Собираем устаревшие в файл
        local stale_tmp
        stale_tmp=$(mktemp)
        
        while read -r f; do
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
        done <<< "$doc_files"
        
        # Показываем топ N
        local total_stale
        total_stale=$(wc -l < "$stale_tmp" | xargs)
        
        if [[ $total_stale -gt 0 ]]; then
          sort -t'|' -k1 -rn "$stale_tmp" | head -n "$doc_stale_max" | while IFS='|' read -r age path date; do
            echo "  ⚠ $path"
            echo "     Last verified: $date ($age дней)"
            echo ""
          done
          
          if [[ $total_stale -gt $doc_stale_max ]]; then
            local remaining=$((total_stale - doc_stale_max))
            echo "  (ещё $remaining документов...)"
            echo ""
          fi
          
          stale_count=$total_stale
        fi
        
        rm -f "$stale_tmp"
      fi
    fi
  done
  
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
  if [[ -d "$target/docs" ]]; then
    while read -r f; do
      local rel_path="${f#$target/}"
      local issues_found=""
      
      grep -q "^Owner:" "$f" || issues_found="${issues_found}Owner, "
      grep -q "^Last verified:" "$f" || issues_found="${issues_found}Last verified, "
      
      if [[ -n "$issues_found" ]]; then
        issues_found="${issues_found%, }"
        echo "  ⚠ $rel_path — отсутствует: $issues_found"
        ((meta_count++))
      fi
    done < <(find "$target/docs" -type f -name "*.md" 2>/dev/null)
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

- `githooks/pre-commit` — добавить блок записи

### Реализация

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
      
      # Собираем файлы через TAB
      local files_tab
      files_tab=$(echo "$changed_code" | tr '\n' '\t' | sed 's/\t$//')
      
      # Определяем doc_hint по маппингу
      local doc_hint=""
      local map_features
      map_features="$(get_config_value "$config" "MAP_FEATURES" "src/,app/,lib/")"
      local map_architecture
      map_architecture="$(get_config_value "$config" "MAP_ARCHITECTURE" "schema,models,types")"
      local map_infrastructure
      map_infrastructure="$(get_config_value "$config" "MAP_INFRASTRUCTURE" "deploy,docker")"
      
      # Простая эвристика: первый файл определяет категорию
      local first_file
      first_file=$(echo "$changed_code" | head -1)
      
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
      
      # Пробуем записать
      local entry="${ts}|${kind}|${ref}|${files_tab}|${doc_hint}|${note}"
      
      # Проверка на проблемные символы (pipe или TAB в путях)
      if echo "$files_tab" | grep -qE '\||	'; then
        # Fallback: .queue0 с NUL-разделителем
        local queue0_file="${pending_local%.queue}.queue0"
        printf '%s|%s|%s|%s|%s|%s\0' "$ts" "$kind" "$ref" "$files_tab" "$doc_hint" "$note" >> "$queue0_file" 2>/dev/null
      else
        # Обычная запись
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
- Fallback на `.queue0` если в путях есть `|` или TAB
- Не падать если запись не удалась (pre-commit не должен блокировать)

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
- [ ] Exit code `audit` = количество проблем (для CI)
- [ ] `pre-commit` реально пишет в `.ai-docs-system/state/pending-updates.queue`
- [ ] `pre-commit`: fallback на `.queue0` для проблемных путей
- [ ] PowerShell версия синхронизирована с Bash
- [ ] Документация обновлена

---

## 📌 Исправленные баги из первоначального плана

1. **`merge_config`: вставка "перед примерами"**
   - Было: `echo >> "$temp_config"` (в конец)
   - Стало: Поиск маркера `# Примеры кастомизации` + вставка через `awk`

2. **`audit_project`: subshell баг с `meta_count`**
   - Было: `find ... | while read` → счётчик в subshell, теряется
   - Стало: `while read < <(find ...)` → process substitution, счётчик работает

3. **`audit_project`: macOS-only парсинг дат**
   - Было: `date -j -f` (работает только на macOS)
   - Стало: Helper `date_to_epoch()` с fallback на GNU date и python3

4. **`audit_project`: хардкод `*.md`**
   - Было: `find ... -name "*.md"`
   - Стало: Динамическое построение паттерна из `DOC_EXTS`

5. **`audit_project`: отсутствие оптимизации**
   - Было: `find` без `-prune` → обходит `node_modules/`
   - Стало: Строим prune-паттерн из `IGNORE_DIRS`

6. **`pre-commit`: отсутствие реальной записи**
   - Было: Только текст "📝 Запись в pending updates..."
   - Стало: Реальная запись в `.ai-docs-system/state/pending-updates.queue`

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
