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
$Version = "2.0.0"
$ScriptDir = $PSScriptRoot

# ═══════════════════════════════════════════════════════════════════════════════
# Функции логирования
# ═══════════════════════════════════════════════════════════════════════════════
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[X] $msg" -ForegroundColor Red }
function Write-Step { param($msg) Write-Host "[>] $msg" -ForegroundColor Cyan }

# ═══════════════════════════════════════════════════════════════════════════════
# Вспомогательные функции
# ═══════════════════════════════════════════════════════════════════════════════

function Get-ConfigValue {
  param([string]$ConfigPath, [string]$Key, [string]$Default)
  
  if (-not (Test-Path $ConfigPath)) { return $Default }
  
  $content = Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue
  if ($content -match "(?m)^$Key=(.+)$") {
    return $matches[1].Trim()
  }
  return $Default
}

function Build-Instructions {
  param([string]$TargetPath)
  
  $configFile = Join-Path $TargetPath ".ai-docs-system\config.env"
  $rulesDir = Join-Path $TargetPath ".ai-docs-system\rules"
  $outputFile = Join-Path $TargetPath ".ai-docs-system\instructions.md"
  
  $rulesEnabled = Get-ConfigValue -ConfigPath $configFile -Key "RULES_ENABLED" -Default "doc-first,update-docs,adr,shortcuts"
  
  # Создаём заголовок
  $header = @"
# AI Docs System — Инструкции

> **Конфигурация:** ``.ai-docs-system/config.env``  
> **Шаблоны:** ``.ai-docs-system/templates/``

---

<!-- АВТОМАТИЧЕСКИ СОБРАНО ИЗ rules/ -->
<!-- Редактируйте rules/*.md и запустите install.ps1 -Mode update для пересборки -->

"@
  
  Set-Content -Path $outputFile -Value $header -Encoding UTF8 -NoNewline
  
  # Добавляем включённые правила
  $rules = $rulesEnabled -split ","
  foreach ($rule in $rules) {
    $rule = $rule.Trim()
    $ruleFile = Join-Path $rulesDir "$rule.md"
    if (Test-Path $ruleFile) {
      $ruleContent = Get-Content $ruleFile -Raw -Encoding UTF8
      Add-Content -Path $outputFile -Value $ruleContent -Encoding UTF8 -NoNewline
      Add-Content -Path $outputFile -Value "`n---`n" -Encoding UTF8 -NoNewline
    }
  }
  
  Write-Success "instructions.md собран (правила: $rulesEnabled)"
}

function Generate-CursorRules {
  param([string]$TargetPath)
  
  $rulesFile = Join-Path $TargetPath ".cursorrules"
  $beginMarker = "# BEGIN ai-docs-system"
  $endMarker = "# END ai-docs-system"
  
  $block = @"
# BEGIN ai-docs-system
# AI Docs System v2.0 — https://github.com/Pixasso/ai-docs-system
# НЕ редактируйте этот блок. Запустите install.ps1 -Mode update для обновления.

Прочитай и следуй инструкциям из ``.ai-docs-system/instructions.md``
Конфигурация проекта: ``.ai-docs-system/config.env``

# END ai-docs-system
"@
  
  if (Test-Path $rulesFile) {
    $existing = Get-Content $rulesFile -Raw -ErrorAction SilentlyContinue
    if (-not $existing) { $existing = "" }
    
    if ($existing -match [regex]::Escape($beginMarker) -and $existing -match [regex]::Escape($endMarker)) {
      $pattern = [regex]::Escape($beginMarker) + "[\s\S]*?" + [regex]::Escape($endMarker)
      $new = [regex]::Replace($existing, $pattern, $block.TrimEnd())
      Set-Content -Path $rulesFile -Value $new -Encoding UTF8 -NoNewline
      Write-Success ".cursorrules обновлён"
    } else {
      $new = $existing.TrimEnd() + "`n`n" + $block.TrimEnd() + "`n"
      Set-Content -Path $rulesFile -Value $new -Encoding UTF8 -NoNewline
      Write-Success ".cursorrules дополнен"
    }
  } else {
    Set-Content -Path $rulesFile -Value $block -Encoding UTF8 -NoNewline
    Write-Success ".cursorrules создан"
  }
}

function Generate-Adapters {
  param([string]$TargetPath)
  
  $configFile = Join-Path $TargetPath ".ai-docs-system\config.env"
  $adapters = Get-ConfigValue -ConfigPath $configFile -Key "ADAPTERS" -Default "cursor"
  
  $adapterList = $adapters -split ","
  foreach ($adapter in $adapterList) {
    $adapter = $adapter.Trim()
    switch ($adapter) {
      "cursor" { Generate-CursorRules -TargetPath $TargetPath }
      "copilot" {
        $dir = Join-Path $TargetPath ".github"
        New-Item -Force -ItemType Directory $dir | Out-Null
        $content = "# AI Docs System`n`nПрочитай и следуй инструкциям из ``.ai-docs-system/instructions.md```nКонфигурация проекта: ``.ai-docs-system/config.env``"
        Set-Content -Path (Join-Path $dir "copilot-instructions.md") -Value $content -Encoding UTF8
        Write-Success ".github/copilot-instructions.md создан"
      }
      "claude" {
        $content = "# AI Docs System`n`nПрочитай и следуй инструкциям из ``.ai-docs-system/instructions.md```nКонфигурация проекта: ``.ai-docs-system/config.env``"
        Set-Content -Path (Join-Path $TargetPath "CLAUDE.md") -Value $content -Encoding UTF8
        Write-Success "CLAUDE.md создан"
      }
      "cline" {
        $content = "# AI Docs System`n`nПрочитай и следуй инструкциям из ``.ai-docs-system/instructions.md```nКонфигурация проекта: ``.ai-docs-system/config.env``"
        Set-Content -Path (Join-Path $TargetPath ".clinerules") -Value $content -Encoding UTF8
        Write-Success ".clinerules создан"
      }
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Основная логика
# ═══════════════════════════════════════════════════════════════════════════════

# Проверка git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Err "git не найден в PATH"
  exit 1
}

# Разрешаем путь
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
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AI Docs System v$Version" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Цель: $Target"
Write-Host "Режим: $Mode"
Write-Host ""

# ─── 1. Настройка .ai-docs-system/ ──────────────────────────────────────────────
Write-Step "Настройка .ai-docs-system/..."

$aiDocsDir = Join-Path $Target ".ai-docs-system"
$rulesDir = Join-Path $aiDocsDir "rules"
$templatesDir = Join-Path $aiDocsDir "templates"

New-Item -Force -ItemType Directory $rulesDir | Out-Null
New-Item -Force -ItemType Directory $templatesDir | Out-Null

$configDst = Join-Path $aiDocsDir "config.env"
$configSrc = Join-Path $ScriptDir ".ai-docs-system\config.env"

if ($Mode -eq "install") {
  if (-not (Test-Path $configDst)) {
    Copy-Item -Force $configSrc $configDst
    
    # Подставляем владельца из git config
    $owner = (git -C $Target config user.name 2>$null)
    if (-not $owner) { $owner = $env:USERNAME }
    if ($owner) {
      (Get-Content $configDst -Raw) -replace '@Pixasso', "@$owner" | Set-Content $configDst -NoNewline
      Write-Success "config.env создан (owner: @$owner)"
    } else {
      Write-Success "config.env создан"
    }
  } else {
    Write-Warn "config.env уже существует, пропускаем"
  }
  
  Copy-Item -Force (Join-Path $ScriptDir ".ai-docs-system\rules\*") $rulesDir -ErrorAction SilentlyContinue
  Write-Success "Правила скопированы в rules/"
  
  Copy-Item -Force (Join-Path $ScriptDir ".ai-docs-system\templates\*") $templatesDir -ErrorAction SilentlyContinue
  Write-Success "Шаблоны скопированы в templates/"
} else {
  # При update — обновляем правила и шаблоны (не перезаписываем существующий конфиг)
  
  # Но если конфига нет вообще (миграция с v1) — создаём
  if (-not (Test-Path $configDst)) {
    Copy-Item -Force $configSrc $configDst
    
    # Подставляем владельца из git config
    $owner = (git -C $Target config user.name 2>$null)
    if (-not $owner) { $owner = $env:USERNAME }
    if ($owner) {
      (Get-Content $configDst -Raw) -replace '@Pixasso', "@$owner" | Set-Content $configDst -NoNewline
      Write-Success "config.env создан (миграция с v1, owner: @$owner)"
    } else {
      Write-Success "config.env создан (миграция с v1)"
    }
  }
  
  Copy-Item -Force (Join-Path $ScriptDir ".ai-docs-system\rules\*") $rulesDir -ErrorAction SilentlyContinue
  Copy-Item -Force (Join-Path $ScriptDir ".ai-docs-system\templates\*") $templatesDir -ErrorAction SilentlyContinue
  Write-Success "Правила и шаблоны обновлены"
}

# ─── 2. Сборка instructions.md ──────────────────────────────────────────────────
Write-Step "Сборка instructions.md..."
Build-Instructions -TargetPath $Target

# ─── 3. Установка хуков ─────────────────────────────────────────────────────────
Write-Step "Установка git-хуков..."

$hooksDir = Join-Path $Target ".githooks"
New-Item -Force -ItemType Directory $hooksDir | Out-Null

Copy-Item -Force (Join-Path $ScriptDir "githooks\pre-commit") (Join-Path $hooksDir "pre-commit")
Copy-Item -Force (Join-Path $ScriptDir "githooks\pre-commit.cmd") (Join-Path $hooksDir "pre-commit.cmd")

git -C $Target config core.hooksPath .githooks
Write-Success "Хуки установлены в .githooks/"

# ─── 4. Генерация адаптеров ─────────────────────────────────────────────────────
Write-Step "Генерация адаптеров для AI..."
Generate-Adapters -TargetPath $Target

# ─── 5. Установка шаблона docs/ (только при install) ────────────────────────────
if ($Mode -eq "install") {
  Write-Step "Установка шаблона документации..."
  
  $docsSrc = Join-Path $ScriptDir "docs-template"
  $docsDst = Join-Path $Target "docs"
  
  if (Test-Path $docsSrc) {
    $hasDocs = (Test-Path $docsDst) -and ((Get-ChildItem $docsDst -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
    
    if (-not $hasDocs) {
      New-Item -Force -ItemType Directory $docsDst | Out-Null
      Copy-Item -Recurse -Force (Join-Path $docsSrc "*") $docsDst -ErrorAction SilentlyContinue
      Write-Success "Структура docs/ создана из шаблона"
    } else {
      Write-Warn "docs/ уже существует, пропускаем"
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Готово
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Готово!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Следующие шаги:"
Write-Host ""
Write-Host "  1. Проверьте конфигурацию:"
Write-Host "     .ai-docs-system/config.env" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Закоммитьте изменения:"
Write-Host "     git add .ai-docs-system .githooks .cursorrules docs/"
Write-Host "     git commit -m 'chore: добавить ai-docs-system'"
Write-Host ""
Write-Host "  3. Используйте:"
Write-Host "     - Измените код -> при коммите увидите напоминание"
Write-Host "     - Cursor Agent: введите '==' для автообновления доки"
Write-Host ""
