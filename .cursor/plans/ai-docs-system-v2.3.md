# AI Docs System v2.3 — План исправлений

**Версия:** 2.2.0 → 2.3.0  
**Цель:** Исправление критичных багов и улучшение надёжности

---

## 📋 Что делаем

| # | Задача | Приоритет | Сложность | Время |
|---|--------|-----------|-----------|-------|
| 1 | pre-commit: break при >10 файлах | **Критично** | Низкая | 0.5ч |
| 2 | Авто-managed хуки затирают существующие | **Критично** | Средняя | 1.5ч |
| 3 | Подстановка owner небезопасна | **Критично** | Низкая | 1ч |
| 4 | PENDING_UPDATES_WRITE=shared не работает | Средний | Средняя | 1.5ч |
| 5 | audit не учитывает абсолютные пути | Средний | Низкая | 0.5ч |
| 6 | audit плохо prune-ит nested ignore-dirs | Средний | Низкая | 0.5ч |
| 7 | PS игнорирует HOOKS_MODE | Средний | Средняя | 1.5ч |
| 8 | PS не поддерживает пустые значения | Средний | Низкая | 0.5ч |
| 9 | PS не делает merge конфига | Средний | Средняя | 1.5ч |

**Итого:** ~9ч (критичные: 3ч, средние: 6ч)

---

## 🔴 Критичные (блокирующие)

### 1️⃣ pre-commit: break при >10 файлах теряет changed_docs

**Файлы:** `githooks/pre-commit` L92-95, `.githooks/pre-commit` L92-95

**Проблема:**
```bash
# Текущий код
while IFS= read -r -d '' file; do
  if echo "$file" | grep -Eq "$DOCS_RE"; then
    changed_docs="yes"
  elif echo "$file" | grep -Evq "$IGNORE_RE" && echo "$file" | grep -Eq "$CODE_RE"; then
    changed_code="yes"
    changed_code_arr+=("$file")
    [[ ${#changed_code_arr[@]} -ge 10 ]] && break  # ❌ ПРОБЛЕМА: останавливает чтение
  fi
done < <(git diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null)
```

**Сценарий:**
1. Коммит содержит 15 файлов: 12 файлов кода + 3 файла документации
2. `break` срабатывает после 10-го кода → остальные файлы не читаются
3. Файлы документации (11-15) не попадают в `changed_docs`
4. Хук ошибочно ругается "код изменён, но документация нет"

**Решение:**
```bash
# Не прерывать чтение, ограничить только массив для вывода
while IFS= read -r -d '' file; do
  if echo "$file" | grep -Eq "$DOCS_RE"; then
    changed_docs="yes"
  elif echo "$file" | grep -Evq "$IGNORE_RE" && echo "$file" | grep -Eq "$CODE_RE"; then
    changed_code="yes"
    # Добавляем в массив только первые 10 для вывода
    if [[ ${#changed_code_arr[@]} -lt 10 ]]; then
      changed_code_arr+=("$file")
    fi
    # НЕ прерываем цикл — продолжаем искать changed_docs
  fi
done < <(git diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null)
```

**Тесты:**
- ✅ 5 кода + 1 doc → `changed_docs="yes"`, хук молчит
- ✅ 12 кода + 3 doc → `changed_docs="yes"`, массив 10 элементов, хук молчит
- ✅ 15 кода + 0 doc → `changed_docs=""`, массив 10 элементов, хук ругается

---

### 2️⃣ Авто-managed хуки затирают существующие

**Файлы:** `install.sh` setup_hooks L181-208, uninstall L685-689

**Проблема:**
```bash
# setup_hooks при HOOKS_MODE=auto
if [[ "$hooks_mode" == "auto" ]]; then
  if [[ -z "$current_hooks_path" ]]; then
    # Пустой core.hooksPath → переключаем на .githooks
    git -C "$target" config core.hooksPath ".githooks"
    cp -f "$SCRIPT_DIR/githooks/pre-commit" "$target/.githooks/pre-commit"
    # ❌ ПРОБЛЕМА: перезаписывает существующий .githooks/pre-commit без бэкапа
  fi
fi
```

**Сценарий:**
1. У юзера уже есть `.githooks/pre-commit` (свой кастомный хук)
2. Запускает `./install.sh . install` с `HOOKS_MODE=auto` (дефолт)
3. Скрипт видит пустой `core.hooksPath`
4. Создаёт `.githooks/` и перезаписывает `pre-commit` → **потеря данных**

**При uninstall:**
```bash
# uninstall удаляет .githooks целиком
rm -rf "$TARGET/.githooks"
# ❌ ПРОБЛЕМА: если там были другие хуки — потеряны
```

**Решение:**

#### 1. Проверка на существующие хуки перед режимом "auto"
```bash
setup_hooks() {
  local target="$1"
  local config="$target/.ai-docs-system/config.env"
  local hooks_mode
  hooks_mode=$(get_config_value "$config" "HOOKS_MODE" "auto")
  
  # Сохраняем текущее значение core.hooksPath
  local current_hooks_path
  current_hooks_path=$(git -C "$target" config core.hooksPath 2>/dev/null || echo "")
  
  case "$hooks_mode" in
    auto)
      # Проверяем существующие хуки ПЕРЕД переключением
      local has_existing_hooks=false
      
      # 1. Проверка .githooks/
      if [[ -d "$target/.githooks" ]] && ls "$target/.githooks/"* >/dev/null 2>&1; then
        has_existing_hooks=true
        log_warn "⚠ Обнаружены существующие хуки в .githooks/"
      fi
      
      # 2. Проверка .git/hooks/ (активные)
      if [[ -z "$current_hooks_path" ]]; then
        # Если core.hooksPath пуст → активна .git/hooks/
        if ls "$target/.git/hooks/"pre-* "$target/.git/hooks/"post-* "$target/.git/hooks/"commit-msg 2>/dev/null | grep -v ".sample" >/dev/null; then
          has_existing_hooks=true
          log_warn "⚠ Обнаружены существующие хуки в .git/hooks/"
        fi
      fi
      
      if [[ "$has_existing_hooks" == true ]]; then
        # Автоматически переключаемся на режим integrate
        log_warn "→ Автоматический режим: integrate (безопасная интеграция)"
        hooks_mode="integrate"
      else
        # Нет существующих хуков → безопасно переключиться на managed
        if [[ -z "$current_hooks_path" ]]; then
          git -C "$target" config core.hooksPath ".githooks"
          set_config_value "$config" "prev-hooksPath" ""
          log_info "✓ Переключено на managed режим (core.hooksPath = .githooks)"
        fi
      fi
      ;;
    
    managed)
      # managed: устанавливаем core.hooksPath = .githooks (перезаписываем)
      git -C "$target" config core.hooksPath ".githooks"
      set_config_value "$config" "prev-hooksPath" "$current_hooks_path"
      log_info "✓ Managed режим (core.hooksPath = .githooks)"
      ;;
    
    integrate)
      # integrate: добавляем вызов в существующий хук (или создаём с fallback)
      log_info "Режим integrate: добавление вызова в существующий pre-commit"
      ;;
    
    off)
      log_info "Хуки отключены (HOOKS_MODE=off)"
      return 0
      ;;
  esac
  
  # Устанавливаем хуки согласно режиму
  case "$hooks_mode" in
    managed)
      mkdir -p "$target/.githooks"
      
      # Проверка на существующий хук (бэкап)
      if [[ -f "$target/.githooks/pre-commit" ]]; then
        if ! grep -q "# AI Docs System" "$target/.githooks/pre-commit"; then
          # Не наш хук → создаём бэкап
          mv "$target/.githooks/pre-commit" "$target/.githooks/pre-commit.bak.$(date +%s)"
          log_warn "⚠ Существующий pre-commit переименован в .bak"
        fi
      fi
      
      cp -f "$SCRIPT_DIR/githooks/pre-commit" "$target/.githooks/pre-commit"
      cp -f "$SCRIPT_DIR/githooks/pre-commit.cmd" "$target/.githooks/pre-commit.cmd" 2>/dev/null || true
      chmod +x "$target/.githooks/pre-commit"
      
      # Создаём маркер-файл (для безопасного удаления при uninstall)
      touch "$target/.githooks/.ai-docs-system-managed"
      log_info "✓ Хуки установлены в .githooks/ (managed)"
      ;;
    
    integrate)
      # Определяем где находятся активные хуки
      local hooks_dir
      if [[ -n "$current_hooks_path" ]]; then
        hooks_dir="$target/$current_hooks_path"
      else
        hooks_dir="$target/.git/hooks"
      fi
      
      mkdir -p "$hooks_dir"
      local hook_file="$hooks_dir/pre-commit"
      
      # Создаём wrapper с fallback на наш скрипт
      if [[ -f "$hook_file" ]]; then
        # Добавляем вызов в конец (если ещё не добавлен)
        if ! grep -q "ai-docs-system" "$hook_file"; then
          echo "" >> "$hook_file"
          echo "# AI Docs System (integrated)" >> "$hook_file"
          echo "[[ -x \"\$GIT_DIR/../.ai-docs-system/hooks/pre-commit\" ]] && \"\$GIT_DIR/../.ai-docs-system/hooks/pre-commit\"" >> "$hook_file"
          log_info "✓ Вызов добавлен в существующий pre-commit"
        fi
      else
        # Создаём новый с вызовом
        cat > "$hook_file" <<'EOF'
#!/usr/bin/env bash
# AI Docs System (integrated)
[[ -x "$GIT_DIR/../.ai-docs-system/hooks/pre-commit" ]] && "$GIT_DIR/../.ai-docs-system/hooks/pre-commit"
EOF
        chmod +x "$hook_file"
        log_info "✓ Создан wrapper pre-commit с вызовом AI Docs System"
      fi
      
      # Копируем наш хук в .ai-docs-system/hooks/
      mkdir -p "$target/.ai-docs-system/hooks"
      cp -f "$SCRIPT_DIR/githooks/pre-commit" "$target/.ai-docs-system/hooks/pre-commit"
      chmod +x "$target/.ai-docs-system/hooks/pre-commit"
      log_info "✓ Хук установлен в .ai-docs-system/hooks/ (integrate)"
      ;;
  esac
}
```

#### 2. Безопасный uninstall
```bash
# В режиме uninstall
if [[ -f "$TARGET/.githooks/.ai-docs-system-managed" ]]; then
  # Маркер есть → мы создали эту папку, можно удалить
  rm -rf "$TARGET/.githooks"
  log_info "✓ .githooks/ удалена (managed режим)"
else
  # Маркера нет → возможно была до нас, удаляем только наши файлы
  if [[ -f "$TARGET/.githooks/pre-commit" ]]; then
    if grep -q "# AI Docs System" "$TARGET/.githooks/pre-commit"; then
      rm -f "$TARGET/.githooks/pre-commit"
      rm -f "$TARGET/.githooks/pre-commit.cmd"
      log_info "✓ pre-commit удалён (другие хуки сохранены)"
    fi
  fi
fi

# Для integrate режима — удаляем вызов
if [[ -d "$TARGET/.ai-docs-system/hooks" ]]; then
  rm -rf "$TARGET/.ai-docs-system/hooks"
  # Удаляем строки из существующего хука
  local hooks_dir
  hooks_dir=$(git -C "$TARGET" config core.hooksPath 2>/dev/null || echo ".git/hooks")
  local hook_file="$TARGET/$hooks_dir/pre-commit"
  if [[ -f "$hook_file" ]]; then
    sed -i.bak '/# AI Docs System (integrated)/,+1d' "$hook_file" 2>/dev/null || \
      sed -i '' '/# AI Docs System (integrated)/,+1d' "$hook_file" 2>/dev/null || true
    rm -f "$hook_file.bak"
    log_info "✓ Вызов удалён из pre-commit"
  fi
fi
```

**Тесты:**
- ✅ Новый проект без хуков + HOOKS_MODE=auto → managed режим
- ✅ Проект с `.githooks/pre-commit` + HOOKS_MODE=auto → integrate режим (не перезаписывает)
- ✅ Проект с `.git/hooks/pre-commit` + HOOKS_MODE=auto → integrate режим
- ✅ uninstall на managed проекте → удаляет `.githooks/` (есть маркер)
- ✅ uninstall на integrate проекте → удаляет только вызов, не трогает хук

---

### 3️⃣ Подстановка owner небезопасна (sed injection)

**Файлы:**
- `install.sh` L746-749, L777-780
- `install.ps1` L201-205, L226-230

**Проблема:**
```bash
# install.sh
owner="$(git -C "$TARGET" config user.name 2>/dev/null || echo "$USER")"
sed -i.bak "s/@Pixasso/@$owner/g" "$TARGET/.ai-docs-system/config.env"
# ❌ ПРОБЛЕМА: если owner содержит &, /, \, $ → sed ломается
```

**Сценарий:**
```bash
git config user.name "John & Sons"  # Содержит &
# sed интерпретирует & как "всё совпадение"
# Результат: @John John & Sons Sons (вместо @John & Sons)
```

**Другие проблемные символы:**
- `/` — разделитель команды sed
- `\` — escape-символ
- `$` — переменная bash
- `&` — весь match в sed replacement

**Решение:**

#### Bash (install.sh)
```bash
# Функция для экранирования sed replacement
escape_sed_replacement() {
  local str="$1"
  # Экранируем \ → \\, затем & → \&, затем / → \/
  printf '%s' "$str" | sed 's/\\/\\\\/g; s/&/\\&/g; s/\//\\\//g'
}

# При подстановке owner
owner="$(git -C "$TARGET" config user.name 2>/dev/null || id -un 2>/dev/null || echo "unknown")"
if [[ -n "$owner" ]]; then
  local owner_escaped
  owner_escaped=$(escape_sed_replacement "$owner")
  sed -i.bak "s/@Pixasso/@$owner_escaped/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || \
    sed -i '' "s/@Pixasso/@$owner_escaped/g" "$TARGET/.ai-docs-system/config.env" 2>/dev/null || true
  rm -f "$TARGET/.ai-docs-system/config.env.bak"
fi
```

**Альтернатива (без sed):**
```bash
# Через perl (безопаснее)
owner="$(git -C "$TARGET" config user.name 2>/dev/null || id -un 2>/dev/null || echo "unknown")"
if [[ -n "$owner" ]] && command -v perl >/dev/null 2>&1; then
  perl -pi -e "s/\@Pixasso/\@\Q$owner\E/g" "$TARGET/.ai-docs-system/config.env"
  # \Q...\E экранирует все спецсимволы
fi
```

#### PowerShell (install.ps1)
```powershell
# БЫЛО (regex):
$owner = (git config user.name 2>$null) ?? $env:USERNAME
$content = $content -replace '@Pixasso', "@$owner"
# ❌ ПРОБЛЕМА: owner с regex-символами ($, ^, [, ]) ломает замену

# СТАЛО (literal string replace):
$owner = (git config user.name 2>$null) ?? $env:USERNAME
if ($owner) {
  $content = $content.Replace('@Pixasso', "@$owner")
  # .Replace() — literal string, не regex
}
```

**Тесты:**
- ✅ `user.name = "John & Sons"` → `@John & Sons`
- ✅ `user.name = "a/b/c"` → `@a/b/c`
- ✅ `user.name = "test$var"` → `@test$var`
- ✅ `user.name = "back\slash"` → `@back\slash`

---

## 🟡 Средний риск / надёжность

### 4️⃣ PENDING_UPDATES_WRITE=shared|both не работает

**Файлы:** `githooks/pre-commit` L118-188, `.githooks/pre-commit`

**Проблема:**
```bash
# В конфиге есть опция
PENDING_UPDATES_WRITE=shared  # или both

# Но в pre-commit только это:
if [[ "$pending_write" == "local" || "$pending_write" == "both" ]]; then
  echo "$entry" >> "$pending_local"
  # ❌ ПРОБЛЕМА: shared никогда не пишется
fi
```

**Решение:**
```bash
# После записи в local
if [[ "$pending_write" == "local" || "$pending_write" == "both" ]]; then
  # ... запись в pending_local ...
fi

# Добавить запись в shared
if [[ "$pending_write" == "shared" || "$pending_write" == "both" ]]; then
  pending_shared="$(get_config_value "$config" "PENDING_UPDATES_SHARED" "")"
  
  if [[ -n "$pending_shared" ]]; then
    # Создаём папку для shared очереди
    local shared_dir
    if [[ "$pending_shared" == /* ]]; then
      # Абсолютный путь
      shared_dir="$(dirname "$pending_shared")"
    else
      # Относительный путь
      shared_dir="$(dirname "$repo_root/$pending_shared")"
    fi
    
    mkdir -p "$shared_dir" 2>/dev/null
    
    # Запись в shared (тот же формат)
    if [[ "$has_bad_chars" == true ]]; then
      # .queue0 для shared
      local queue0_file="${pending_shared%.queue}.queue0"
      if [[ "$pending_shared" != /* ]]; then
        queue0_file="$repo_root/$queue0_file"
      fi
      {
        printf '%s\0%s\0%s\0' "$ts" "$kind" "$ref"
        for f in "${changed_code_arr[@]}"; do
          printf '%s\0' "$f"
        done
        printf '\0%s\0%s\0\0' "$doc_hint" "$note"
      } >> "$queue0_file" 2>/dev/null
    else
      # Обычная запись
      local shared_file="$pending_shared"
      [[ "$pending_shared" != /* ]] && shared_file="$repo_root/$pending_shared"
      echo "$entry" >> "$shared_file" 2>/dev/null
    fi
    
    log_info "✓ Запись в shared очередь: $pending_shared"
  else
    log_warn "⚠ PENDING_UPDATES_WRITE=$pending_write, но PENDING_UPDATES_SHARED пуст"
  fi
fi
```

**Тесты:**
- ✅ `PENDING_UPDATES_WRITE=local` → пишет в local
- ✅ `PENDING_UPDATES_WRITE=shared` + `PENDING_UPDATES_SHARED=/tmp/shared.queue` → пишет в shared
- ✅ `PENDING_UPDATES_WRITE=both` → пишет в оба
- ✅ `PENDING_UPDATES_WRITE=shared` + `PENDING_UPDATES_SHARED=""` → warning, не падает

---

### 5️⃣ audit не учитывает абсолютные пути очередей

**Файлы:** `install.sh` L402-405, L451-453

**Проблема:**
```bash
# audit_project читает очередь
pending_local=$(get_config_value "$config_file" "PENDING_UPDATES_LOCAL" ".ai-docs-system/state/pending-updates.queue")

if [[ -f "$target/$pending_local" ]]; then
  # ❌ ПРОБЛЕМА: если pending_local=/tmp/queue → проверяет /path/to/project//tmp/queue
fi
```

**Решение:**
```bash
# Проверка на абсолютный путь
pending_local=$(get_config_value "$config_file" "PENDING_UPDATES_LOCAL" ".ai-docs-system/state/pending-updates.queue")

local queue_path
if [[ "$pending_local" == /* ]]; then
  # Абсолютный путь → используем как есть
  queue_path="$pending_local"
else
  # Относительный путь → добавляем $target
  queue_path="$target/$pending_local"
fi

if [[ -f "$queue_path" ]]; then
  pending_count=$(wc -l < "$queue_path" | xargs)
  # ...
fi
```

**Применить к:**
- `pending_local` (L402-405)
- `pending_shared` (L469-476)
- Везде где строится путь через `$target/$variable`

---

### 6️⃣ audit плохо prune-ит nested ignore-dirs

**Файлы:** `install.sh` L485-505

**Проблема:**
```bash
# Текущий код
for idir in "${ignore_arr[@]}"; do
  idir=$(echo "$idir" | xargs)
  prune_pattern="$prune_pattern -o -path $target/$idir"
done

# Строит: -path /project/node_modules
# ❌ ПРОБЛЕМА: не матчит /project/apps/backend/node_modules
```

**На монорепе:**
```
project/
  apps/
    frontend/node_modules/  ← не исключается
    backend/node_modules/   ← не исключается
  packages/
    shared/node_modules/    ← не исключается
  node_modules/             ← исключается
```

**Решение:**
```bash
# Используем wildcard для nested dirs
for idir in "${ignore_arr[@]}"; do
  idir=$(echo "$idir" | xargs)
  # Матчим как начало пути И вложенные
  prune_pattern="$prune_pattern -o -path $target/$idir -o -path $target/*/$idir"
done

# Или универсальнее (через name вместо path):
for idir in "${ignore_arr[@]}"; do
  idir=$(echo "$idir" | xargs)
  prune_pattern="$prune_pattern -o -name $idir"
done
# -name матчит на любом уровне вложенности
```

**Ещё лучше (для всех уровней):**
```bash
# find с -prune работает по name (не path)
local prune_args=()
IFS=',' read -ra ignore_arr <<< "$ignore_dirs"
for idir in "${ignore_arr[@]}"; do
  idir=$(echo "$idir" | xargs)
  prune_args+=("-name" "$idir" "-o")
done
[[ ${#prune_args[@]} -gt 0 ]] && unset 'prune_args[-1]'  # Убираем последний "-o"

# Использование
if [[ ${#prune_args[@]} -gt 0 ]]; then
  find_args+=("(" "${prune_args[@]}" ")" "-prune" "-o")
fi
# Теперь prune работает для ЛЮБОГО node_modules на ЛЮБОМ уровне
```

**Применить к:**
- Секция "README в коде" (L491-543)
- Секция "Устаревшие документы" (L547-654)
- Секция "Метаданные" (L677-747)

---

### 7️⃣ PS игнорирует HOOKS_MODE

**Файлы:** `install.ps1` L246-255

**Проблема:**
```powershell
# Текущий код
Write-Host "Настройка Git hooks..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "$Target\.githooks" | Out-Null
Copy-Item "$ScriptDir\githooks\*" "$Target\.githooks\" -Recurse -Force
git -C $Target config core.hooksPath ".githooks"
# ❌ ПРОБЛЕМА: всегда ставит .githooks, игнорирует HOOKS_MODE из конфига
```

**Решение:**

Портировать логику `setup_hooks` из bash (задача #2):
```powershell
function Setup-Hooks {
  param(
    [string]$Target
  )
  
  $config = "$Target\.ai-docs-system\config.env"
  $hooksMode = Get-ConfigValue $config "HOOKS_MODE" "auto"
  
  # Получаем текущий core.hooksPath
  $currentHooksPath = git -C $Target config core.hooksPath 2>$null
  
  switch ($hooksMode) {
    "auto" {
      # Проверяем существующие хуки
      $hasExistingHooks = $false
      
      if (Test-Path "$Target\.githooks") {
        $existingFiles = Get-ChildItem "$Target\.githooks" -File -ErrorAction SilentlyContinue
        if ($existingFiles) { $hasExistingHooks = $true }
      }
      
      if (-not $currentHooksPath) {
        $gitHooks = Get-ChildItem "$Target\.git\hooks\pre-*","$Target\.git\hooks\post-*","$Target\.git\hooks\commit-msg" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.sample" }
        if ($gitHooks) { $hasExistingHooks = $true }
      }
      
      if ($hasExistingHooks) {
        Write-Host "⚠ Обнаружены существующие хуки → режим integrate" -ForegroundColor Yellow
        $hooksMode = "integrate"
      } else {
        if (-not $currentHooksPath) {
          git -C $Target config core.hooksPath ".githooks"
          Write-Host "✓ Переключено на managed режим" -ForegroundColor Green
        }
      }
    }
    
    "managed" {
      git -C $Target config core.hooksPath ".githooks"
      Set-ConfigValue $config "prev-hooksPath" $currentHooksPath
      Write-Host "✓ Managed режим (core.hooksPath = .githooks)" -ForegroundColor Green
    }
    
    "integrate" {
      Write-Host "Режим integrate: добавление вызова в существующий pre-commit" -ForegroundColor Cyan
    }
    
    "off" {
      Write-Host "Хуки отключены (HOOKS_MODE=off)" -ForegroundColor Gray
      return
    }
  }
  
  # Устанавливаем хуки согласно режиму
  switch ($hooksMode) {
    "managed" {
      New-Item -ItemType Directory -Force -Path "$Target\.githooks" | Out-Null
      
      # Проверка на существующий хук (бэкап)
      if (Test-Path "$Target\.githooks\pre-commit") {
        $content = Get-Content "$Target\.githooks\pre-commit" -Raw -ErrorAction SilentlyContinue
        if ($content -notlike "*AI Docs System*") {
          $timestamp = [int][double]::Parse((Get-Date -UFormat %s))
          Move-Item "$Target\.githooks\pre-commit" "$Target\.githooks\pre-commit.bak.$timestamp" -Force
          Write-Host "⚠ Существующий pre-commit переименован в .bak" -ForegroundColor Yellow
        }
      }
      
      Copy-Item "$ScriptDir\githooks\pre-commit" "$Target\.githooks\pre-commit" -Force
      Copy-Item "$ScriptDir\githooks\pre-commit.cmd" "$Target\.githooks\pre-commit.cmd" -Force -ErrorAction SilentlyContinue
      
      # Маркер-файл
      New-Item -ItemType File -Force -Path "$Target\.githooks\.ai-docs-system-managed" | Out-Null
      Write-Host "✓ Хуки установлены в .githooks/ (managed)" -ForegroundColor Green
    }
    
    "integrate" {
      # Определяем где активные хуки
      $hooksDir = if ($currentHooksPath) { "$Target\$currentHooksPath" } else { "$Target\.git\hooks" }
      New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
      
      $hookFile = "$hooksDir\pre-commit"
      
      if (Test-Path $hookFile) {
        $content = Get-Content $hookFile -Raw
        if ($content -notlike "*ai-docs-system*") {
          Add-Content $hookFile "`n# AI Docs System (integrated)`nif (Test-Path `"`$PSScriptRoot\..\.ai-docs-system\hooks\pre-commit`") { & `"`$PSScriptRoot\..\.ai-docs-system\hooks\pre-commit`" }"
          Write-Host "✓ Вызов добавлен в существующий pre-commit" -ForegroundColor Green
        }
      } else {
        @"
#!/usr/bin/env bash
# AI Docs System (integrated)
[[ -x "`$GIT_DIR/../.ai-docs-system/hooks/pre-commit" ]] && "`$GIT_DIR/../.ai-docs-system/hooks/pre-commit"
"@ | Out-File $hookFile -Encoding UTF8 -NoNewline
        Write-Host "✓ Создан wrapper pre-commit" -ForegroundColor Green
      }
      
      # Копируем наш хук
      New-Item -ItemType Directory -Force -Path "$Target\.ai-docs-system\hooks" | Out-Null
      Copy-Item "$ScriptDir\githooks\pre-commit" "$Target\.ai-docs-system\hooks\pre-commit" -Force
      Write-Host "✓ Хук установлен в .ai-docs-system/hooks/ (integrate)" -ForegroundColor Green
    }
  }
}

# Вызов вместо текущего блока
Setup-Hooks $Target
```

---

### 8️⃣ PS не поддерживает пустые значения в конфиге

**Файлы:** `install.ps1` L27-35

**Проблема:**
```powershell
# Get-ConfigValue
if ($line -match "^$Key=(.+)$") {
  return $matches[1]
}
# ❌ ПРОБЛЕМА: (.+) требует минимум 1 символ
# KEY= (пустое значение) → не матчится → возвращает Default
```

**Сценарий:**
```bash
# config.env
PENDING_UPDATES_SHARED=          # Намеренно пусто (только local очередь)
ADAPTERS=                        # Намеренно пусто (отключить адаптеры)
```

**Решение:**
```powershell
function Get-ConfigValue {
  param(
    [string]$ConfigPath,
    [string]$Key,
    [string]$Default = ""
  )
  
  if (-not (Test-Path $ConfigPath)) {
    return $Default
  }
  
  $content = Get-Content $ConfigPath -ErrorAction SilentlyContinue
  foreach ($line in $content) {
    # БЫЛО: (.+)
    # СТАЛО: (.*)
    if ($line -match "^$Key=(.*)$") {
      $value = $matches[1]
      # Различаем "пусто" и "не найдено"
      return $value  # Может быть пустой строкой ""
    }
  }
  
  # Ключ не найден → возвращаем Default
  return $Default
}
```

**Тесты:**
- ✅ `KEY=value` → `"value"`
- ✅ `KEY=` → `""` (пустая строка, НЕ default)
- ✅ Ключа нет → `$Default`

---

### 9️⃣ PS не делает merge конфига при update

**Файлы:** `install.ps1` L219-238

**Проблема:**
```powershell
# Текущий код
if (-not (Test-Path "$Target\.ai-docs-system\config.env")) {
  Copy-Item "$ScriptDir\.ai-docs-system\config.env" "$Target\.ai-docs-system\config.env" -Force
  # ... подстановка owner ...
} else {
  Write-Host "Конфиг существует, пропускаем" -ForegroundColor Gray
  # ❌ ПРОБЛЕМА: новые ключи не добавляются
}
```

**Решение:**

Портировать логику `merge_config` из bash:
```powershell
function Merge-Config {
  param(
    [string]$Target
  )
  
  $defaultConfig = "$ScriptDir\.ai-docs-system\config.env"
  $userConfig = "$Target\.ai-docs-system\config.env"
  $tempConfig = "$userConfig.merge.tmp"
  
  if (-not (Test-Path $defaultConfig)) {
    Write-Host "⚠ Дефолтный конфиг не найден" -ForegroundColor Yellow
    return
  }
  
  if (-not (Test-Path $userConfig)) {
    Write-Host "⚠ Конфиг юзера не найден" -ForegroundColor Yellow
    return
  }
  
  Write-Host "Merge конфига (консервативный режим)..." -ForegroundColor Cyan
  
  # Версионированные дефолты для RULES_ENABLED
  $defaultsV20 = "doc-first,update-docs,adr,shortcuts"
  $defaultsV21 = "doc-first,update-docs,adr,shortcuts,structure"
  $defaultsV22 = $defaultsV21  # Без изменений
  
  # Получаем все ключи из дефолтного конфига
  $defaultContent = Get-Content $defaultConfig
  $keys = $defaultContent | Where-Object { $_ -match "^[A-Z_]+=" } | ForEach-Object {
    ($_ -split "=", 2)[0]
  } | Sort-Object -Unique
  
  # Начинаем с конфига юзера
  Copy-Item $userConfig $tempConfig -Force
  
  $added = 0
  $skipped = 0
  $additions = @()
  
  # Добавляем отсутствующие ключи
  foreach ($key in $keys) {
    $userValue = Get-ConfigValue $userConfig $key $null
    
    if ($null -eq $userValue) {
      # Ключа нет → добавляем
      $defaultValue = Get-ConfigValue $defaultConfig $key ""
      
      # Собираем комментарии перед ключом
      $commentBlock = ""
      $inComments = $false
      foreach ($line in $defaultContent) {
        if ($line -match "^# ───") {
          $commentBlock = "$line`n"
          $inComments = $true
        } elseif ($inComments -and $line -match "^# ") {
          $commentBlock += "$line`n"
        } elseif ($line -match "^$key=") {
          if ($commentBlock) {
            $additions += "`n$commentBlock$key=$defaultValue"
          } else {
            $additions += "$key=$defaultValue"
          }
          break
        } elseif ($line -match "^[A-Z_]+=") {
          $inComments = $false
          $commentBlock = ""
        }
      }
      
      $added++
      Write-Host "+ $key=$defaultValue" -ForegroundColor Green
    } else {
      $skipped++
    }
  }
  
  # Вставляем новые ключи ПЕРЕД "Примеры кастомизации"
  if ($additions.Count -gt 0) {
    $tempContent = Get-Content $tempConfig -Raw
    $marker = "# Примеры кастомизации под специфичные проекты"
    
    if ($tempContent -like "*$marker*") {
      $additionsText = $additions -join "`n"
      $tempContent = $tempContent.Replace($marker, "$additionsText`n`n$marker")
      $tempContent | Out-File $tempConfig -Encoding UTF8 -NoNewline
    } else {
      # Fallback: в конец
      $additions | Out-File $tempConfig -Append -Encoding UTF8
    }
  }
  
  # Специальная обработка RULES_ENABLED
  $userRules = Get-ConfigValue $userConfig "RULES_ENABLED" ""
  
  if ($userRules -eq $defaultsV20) {
    # На старом дефолте → обновляем
    $tempContent = Get-Content $tempConfig -Raw
    $tempContent = $tempContent -replace "^RULES_ENABLED=.*", "RULES_ENABLED=$defaultsV21"
    $tempContent | Out-File $tempConfig -Encoding UTF8 -NoNewline
    Write-Host "✓ RULES_ENABLED обновлён: $defaultsV21" -ForegroundColor Green
  } elseif ($userRules -eq "") {
    # Пусто (добавлен выше)
  } else {
    # Кастомизирован → не трогаем
    Write-Host "⚠ RULES_ENABLED не обновлён (кастомизирован: $userRules)" -ForegroundColor Yellow
    Write-Host "  Новые правила: structure (добавьте вручную если нужно)" -ForegroundColor Gray
  }
  
  # Применяем
  Move-Item $tempConfig $userConfig -Force
  
  Write-Host "`nMerge завершён: +$added новых, ~$skipped существующих`n" -ForegroundColor Cyan
}

# Вызов при update
if (Test-Path "$Target\.ai-docs-system\config.env") {
  Merge-Config $Target
} else {
  # Создание конфига (миграция v1 → v2)
  Copy-Item "$ScriptDir\.ai-docs-system\config.env" "$Target\.ai-docs-system\config.env" -Force
  # ... подстановка owner ...
}
```

---

## 📝 Низкоприоритетные (опциональные, но улучшат надёжность)

### 🔹 pre-commit: echo вместо printf для путей
- **Файл:** `githooks/pre-commit` L84-90
- **Риск:** Файлы типа `-n`, `-e` или с `\` могут исказиться
- **Решение:** `printf '%s\n' "$file"` вместо `echo "$file"`

### 🔹 Пробелы в CSV конфигах
- **Файл:** `githooks/pre-commit` csv_to_re L52-58
- **Риск:** `CODE_DIRS=src, app` → токен ` app` не матчится
- **Решение:** `xargs` или `tr -d ' '` внутри `csv_to_re`

### 🔹 Supply-chain риск в update.sh
- **Файл:** `.ai-docs-system/update.sh` L51-83
- **Риск:** Скачивается и выполняется install.sh с main без проверки
- **Решение:** Опция на pin к tag + SHA256 (не обязательно по умолчанию)

### 🔹 install.sh не проверяет наличие git
- **Файл:** `install.sh` перед первым `git -C`
- **Риск:** Если `.git` есть, а `git` нет → упадёт молча из-за `set -e`
- **Решение:** `command -v git >/dev/null || { echo "git не найден"; exit 1; }`

---

## 🔄 Порядок реализации

1. **Критичные (блокеры):**
   1. `pre-commit`: break при >10 файлах (30 мин)
   2. Авто-managed хуки затирают существующие (1.5ч)
   3. Подстановка owner небезопасна (1ч)

2. **Средние (надёжность):**
   4. PENDING_UPDATES_WRITE=shared (1.5ч)
   5. audit: абсолютные пути очередей (30 мин)
   6. audit: nested prune (30 мин)
   7. PS: HOOKS_MODE (1.5ч)
   8. PS: пустые значения (30 мин)
   9. PS: merge конфига (1.5ч)

3. **Низкоприоритетные (опционально):**
   10-13. Если время позволяет

---

## ✅ Критерии готовности

### Критичные
- [ ] `pre-commit`: цикл по файлам продолжается после 10-го кода (для поиска docs)
- [ ] `install.sh`: режим `auto` проверяет существующие хуки перед перезаписью
- [ ] `install.sh`: `uninstall` использует маркер `.ai-docs-system-managed` для безопасного удаления
- [ ] `install.sh`: режим `integrate` создаёт wrapper без перезаписи
- [ ] `install.sh`: `escape_sed_replacement()` или `perl -pi` для owner
- [ ] `install.ps1`: `.Replace()` вместо `-replace` для owner

### Средние
- [ ] `pre-commit`: реально пишет в shared очередь при `PENDING_UPDATES_WRITE=shared|both`
- [ ] `audit_project`: проверяет `pending_local =~ ^/` для абсолютных путей
- [ ] `audit_project`: `-name` вместо `-path` для prune (работает на всех уровнях)
- [ ] `install.ps1`: функция `Setup-Hooks` портирована из bash
- [ ] `install.ps1`: `Get-ConfigValue` с `(.*)` вместо `(.+)`
- [ ] `install.ps1`: функция `Merge-Config` портирована из bash

### Тесты
- [ ] Проект с 12 кода + 3 doc → хук молчит (docs найдены)
- [ ] Проект с `.githooks/pre-commit` + `auto` → integrate режим
- [ ] `user.name = "John & Sons"` → `@John & Sons` в config
- [ ] `PENDING_UPDATES_WRITE=shared` → файл появляется в shared
- [ ] `PENDING_UPDATES_LOCAL=/tmp/queue` → audit читает из `/tmp/queue`
- [ ] Монорепо с `apps/*/node_modules` → audit не обходит эти папки
- [ ] PowerShell: `ADAPTERS=` → пустая строка (не default)

---

## 📌 Связь с v2.2

Все задачи **дополняют v2.2** (не перезаписывают):
- v2.2 внедрил `merge_config`, `audit`, `pending updates`
- v2.3 исправляет **баги и недоработки** в этих фичах

Можно делать **как патч** или как **отдельный релиз**.

---

## 🎯 Финализация

После завершения:
1. ✅ Обновить `VERSION` → `2.3.0`
2. ✅ Добавить в `README.md` секцию "Исправления в v2.3"
3. ✅ Обновить план v2.2 (пометить как Done)
4. ✅ Закоммитить и запушить
5. ✅ Протестировать на монорепе + Windows

---

## 📚 Примечания

- **Без оверинжиниринга:** Все задачи адресуют реальные баги из ревью
- **Критичные сначала:** Потеря данных и security issues в приоритете
- **Кроссплатформенность:** PS синхронизация с bash для консистентности
- **Обратная совместимость:** Все изменения не ломают существующие проекты
