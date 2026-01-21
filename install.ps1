#
# AI Docs System — Скрипт установки / обновления (Windows)
# https://github.com/Pixasso/ai-docs-system
#
param(
  [string]$Target = ".",
  [ValidateSet("install","update")]
  [string]$Mode = "install"
)

$ErrorActionPreference = "Stop"
$Version = "1.0.0"
$ScriptDir = $PSScriptRoot

function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[ПРЕДУПРЕЖДЕНИЕ] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[ОШИБКА] $msg" -ForegroundColor Red }

# Проверка git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Err "git не найден в PATH"
  exit 1
}

# Разрешаем путь к цели
try {
  $Target = (Resolve-Path $Target).Path
} catch {
  Write-Err "Папка не найдена: $Target"
  exit 1
}

# Проверка git-репозитория
if (-not (Test-Path (Join-Path $Target ".git"))) {
  Write-Err "Не git-репозиторий: $Target"
  Write-Host "Инициализируйте командой: git init"
  exit 1
}

Write-Host ""
Write-Host "AI Docs System v$Version"
Write-Host "Цель: $Target"
Write-Host "Режим: $Mode"
Write-Host ""

# 1. Установка хуков
$HooksDir = Join-Path $Target ".githooks"
New-Item -Force -ItemType Directory $HooksDir | Out-Null

Copy-Item -Force (Join-Path $ScriptDir "githooks\pre-commit") (Join-Path $HooksDir "pre-commit")
Copy-Item -Force (Join-Path $ScriptDir "githooks\pre-commit.cmd") (Join-Path $HooksDir "pre-commit.cmd")

git -C $Target config core.hooksPath .githooks
Write-Success "Хуки установлены в .githooks/"

# 2. Обновление .cursorrules (управляемый блок)
$BeginMarker = "# BEGIN ai-docs-system"
$EndMarker = "# END ai-docs-system"

$Block = @"
# BEGIN ai-docs-system
# AI Docs System — https://github.com/Pixasso/ai-docs-system
# НЕ редактируйте этот блок вручную. Запустите install.ps1 -Mode update для обновления.

## Шорткаты

**"=="** — обнови документацию с учётом последних изменений в коде:
1. Найди изменённые файлы в ``src/``, ``services/``
2. Определи какие документы в ``docs/`` нужно обновить
3. Предложи конкретные изменения с diff
4. Примени после approval

---

## Doc-first (ОБЯЗАТЕЛЬНО)

Перед любым ответом или изменением кода:
1. Сначала прочитай ``/docs/README.md`` (точка входа)
2. Найди и прочитай релевантные документы в ``/docs/**``
3. Если документация есть — следуй ей
4. Если документация устарела/противоречит коду — явно скажи и предложи diff на обновление

---

## Автоматические напоминания

- При изменении ``src/``, ``services/`` — ВСЕГДА предлагай обновить ``docs/``
- При архитектурных решениях — предлагай создать ``docs/adr/NNNN-название.md``

---

## Метаданные документов

Каждый новый документ начинай с:
``````markdown
> **Status:** current | draft | legacy
> **Last verified:** YYYY-MM-DD
> **Owner:** @Pixasso
``````

# END ai-docs-system
"@

$RulesPath = Join-Path $Target ".cursorrules"

if (Test-Path $RulesPath) {
  $Existing = Get-Content $RulesPath -Raw -ErrorAction SilentlyContinue
  if (-not $Existing) { $Existing = "" }
  
  if ($Existing -match [regex]::Escape($BeginMarker) -and $Existing -match [regex]::Escape($EndMarker)) {
    # Обновляем существующий блок
    $pattern = [regex]::Escape($BeginMarker) + "[\s\S]*?" + [regex]::Escape($EndMarker)
    $New = [regex]::Replace($Existing, $pattern, $Block.TrimEnd())
    Set-Content -Path $RulesPath -Value $New -Encoding UTF8 -NoNewline
    Write-Success ".cursorrules обновлён (блок заменён)"
  } else {
    # Добавляем блок
    $New = $Existing.TrimEnd() + "`n`n" + $Block.TrimEnd() + "`n"
    Set-Content -Path $RulesPath -Value $New -Encoding UTF8 -NoNewline
    Write-Success ".cursorrules обновлён (блок добавлен)"
  }
} else {
  # Создаём новый файл
  Set-Content -Path $RulesPath -Value $Block -Encoding UTF8 -NoNewline
  Write-Success ".cursorrules создан"
}

# 3. Установка шаблона docs (только при первой установке)
if ($Mode -eq "install") {
  $DocsSrc = Join-Path $ScriptDir "docs-template"
  $DocsDst = Join-Path $Target "docs"
  
  if (Test-Path $DocsSrc) {
    $HasDocs = (Test-Path $DocsDst) -and ((Get-ChildItem $DocsDst -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
    
    if (-not $HasDocs) {
      New-Item -Force -ItemType Directory $DocsDst | Out-Null
      Copy-Item -Recurse -Force (Join-Path $DocsSrc "*") $DocsDst -ErrorAction SilentlyContinue
      Write-Success "Структура docs/ создана из шаблона"
    } else {
      Write-Warn "docs/ уже существует, пропускаем шаблон"
    }
  }
}

Write-Host ""
Write-Host "Готово!" -ForegroundColor Green
Write-Host ""
Write-Host "Следующие шаги:"
Write-Host "  1. Коммит: git add .githooks .cursorrules docs; git commit -m 'chore: добавить ai-docs-system'"
Write-Host "  2. Тест: измените что-то в src/, закоммитьте, увидите напоминание"
Write-Host "  3. Используйте Cursor Agent (Cmd+Shift+I) и введите '==' для автообновления документации"
Write-Host ""
