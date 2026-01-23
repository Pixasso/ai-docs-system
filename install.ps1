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
$Version = "2.4.1"
$ScriptDir = $PSScriptRoot

# ═══════════════════════════════════════════════════════════════════════════════
# Функции логирования
# ═══════════════════════════════════════════════════════════════════════════════
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[X] $msg" -ForegroundColor Red }
function Write-Step { param($msg) Write-Host "[>] $msg" -ForegroundColor Cyan }
function Write-Info { param($msg) Write-Host "    $msg" -ForegroundColor Gray }

# ═══════════════════════════════════════════════════════════════════════════════
# Вспомогательные функции
# ═══════════════════════════════════════════════════════════════════════════════

function Get-ConfigValue {
  param([string]$ConfigPath, [string]$Key, [string]$Default)
  
  if (-not (Test-Path $ConfigPath)) { return $Default }
  
  $content = Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue
  # Изменено: (.+) → (.*)  для поддержки пустых значений
  if ($content -match "(?m)^$Key=(.*)$") {
    $value = $matches[1].Trim()
    # Различаем "пусто" и "не найдено"
    return $value  # Может быть пустой строкой ""
  }
  # Ключ не найден → возвращаем Default
  return $Default
}

function Build-Instructions {
  param([string]$TargetPath)
  
  $configFile = Join-Path $TargetPath ".ai-docs-system\config.env"
  $rulesDir = Join-Path $TargetPath ".ai-docs-system\rules"
  $outputFile = Join-Path $TargetPath ".ai-docs-system\instructions.md"
  
  $rulesEnabled = Get-ConfigValue -ConfigPath $configFile -Key "RULES_ENABLED" -Default "doc-first,update-docs,adr,shortcuts,structure,pending-write"
  
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
# AI Docs System v2.4.1 — https://github.com/Pixasso/ai-docs-system
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

function Setup-Hooks {
  param([string]$TargetPath)
  
  $config = Join-Path $TargetPath ".ai-docs-system\config.env"
  $hooksMode = Get-ConfigValue -ConfigPath $config -Key "HOOKS_MODE" -Default "auto"
  
  # Получаем текущий core.hooksPath
  $currentHooksPath = git -C $TargetPath config core.hooksPath 2>$null
  
  $actualMode = $hooksMode
  
  switch ($hooksMode) {
    "auto" {
      # Проверяем существующие хуки ПЕРЕД автоматическим переключением
      $hasExistingHooks = $false
      
      # 1. Проверка .githooks/ на наличие файлов
      if (Test-Path (Join-Path $TargetPath ".githooks")) {
        $existingFiles = Get-ChildItem (Join-Path $TargetPath ".githooks") -File -ErrorAction SilentlyContinue
        if ($existingFiles) { 
          $hasExistingHooks = $true
          Write-Warning "⚠ Обнаружены существующие хуки в .githooks/"
        }
      }
      
      # 2. Проверка .git/hooks/ (если core.hooksPath пуст)
      if (-not $currentHooksPath) {
        $gitHooks = Get-ChildItem (Join-Path $TargetPath ".git\hooks\pre-*"),(Join-Path $TargetPath ".git\hooks\post-*"),(Join-Path $TargetPath ".git\hooks\commit-msg") -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.sample" }
        if ($gitHooks) { 
          $hasExistingHooks = $true
          Write-Warning "⚠ Обнаружены существующие хуки в .git/hooks/"
        }
      }
      
      if ($hasExistingHooks) {
        # Автоматически переключаемся на integrate (безопасный режим)
        $actualMode = "integrate"
        Write-Warning "→ Автоматический режим: integrate (безопасная интеграция)"
      } elseif (-not $currentHooksPath -or $currentHooksPath -eq ".githooks") {
        $actualMode = "managed"
      } else {
        $actualMode = "integrate"
      }
    }
    
    "managed" {
      git -C $TargetPath config core.hooksPath ".githooks"
      # Сохраняем предыдущий hooksPath (если был)
      if ($currentHooksPath -and $currentHooksPath -ne ".githooks") {
        $stateDir = Join-Path $TargetPath ".ai-docs-system\state"
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        Set-Content -Path (Join-Path $stateDir "prev-hooksPath") -Value $currentHooksPath -NoNewline
      }
      Write-Success "✓ Managed режим (core.hooksPath = .githooks)"
    }
    
    "integrate" {
      Write-Info "Режим integrate: добавление вызова в существующий pre-commit"
    }
    
    "off" {
      Write-Info "Хуки отключены (HOOKS_MODE=off)"
      return
    }
  }
  
  # Устанавливаем хуки согласно режиму
  switch ($actualMode) {
    "managed" {
      $hooksDir = Join-Path $TargetPath ".githooks"
      New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
      
      # Проверка на существующий pre-commit (бэкап если не наш)
      $preCommit = Join-Path $hooksDir "pre-commit"
      if (Test-Path $preCommit) {
        $content = Get-Content $preCommit -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -notlike "*AI Docs System*") {
          # Не наш хук → создаём бэкап
          $timestamp = [int][double]::Parse((Get-Date -UFormat %s))
          Move-Item $preCommit "$preCommit.bak.$timestamp" -Force
          Write-Warning "⚠ Существующий pre-commit переименован в .bak"
        }
      }
      
      Copy-Item -Force (Join-Path $ScriptDir "githooks\pre-commit") $preCommit
      Copy-Item -Force (Join-Path $ScriptDir "githooks\pre-commit.cmd") (Join-Path $hooksDir "pre-commit.cmd") -ErrorAction SilentlyContinue
      
      # Маркер-файл (для безопасного удаления при uninstall)
      New-Item -ItemType File -Force -Path (Join-Path $hooksDir ".ai-docs-system-managed") | Out-Null
      
      git -C $TargetPath config core.hooksPath ".githooks"
      Write-Success "✓ Хуки установлены в .githooks/ (managed режим)"
    }
    
    "integrate" {
      # Определяем где активные хуки
      $hooksDir = if ($currentHooksPath) { 
        Join-Path $TargetPath $currentHooksPath 
      } else { 
        Join-Path $TargetPath ".git\hooks" 
      }
      New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
      
      $hookFile = Join-Path $hooksDir "pre-commit"
      
      # Копируем наш хук в .ai-docs-system/hooks/
      $ourHooksDir = Join-Path $TargetPath ".ai-docs-system\hooks"
      New-Item -ItemType Directory -Force -Path $ourHooksDir | Out-Null
      Copy-Item -Force (Join-Path $ScriptDir "githooks\pre-commit") (Join-Path $ourHooksDir "pre-commit")
      
      if (Test-Path $hookFile) {
        $content = Get-Content $hookFile -Raw -ErrorAction SilentlyContinue
        if ($content -like "*ai-docs-system*") {
          Write-Success "✓ pre-commit уже интегрирован"
        }
        elseif ($content -match "^#!.*bash" -or $content -match "^#!/bin/sh") {
          # Это bash hook — добавляем bash-строку
          $bashIntegration = @"

# AI Docs System (integrated)
[[ -x ".ai-docs-system/hooks/pre-commit" ]] && .ai-docs-system/hooks/pre-commit
"@
          Add-Content $hookFile $bashIntegration
          Write-Success "✓ Bash-вызов добавлен в существующий pre-commit"
        }
        else {
          # Неизвестный формат hook — НЕ модифицируем, печатаем инструкцию
          Write-Warn "⚠ Существующий pre-commit не модифицирован (неизвестный формат)"
          Write-Info "  Добавьте вручную вызов: .ai-docs-system/hooks/pre-commit"
        }
      } else {
        # Hook не существует — создаём bash wrapper
        @"
#!/usr/bin/env bash
# AI Docs System (integrated)
[[ -x ".ai-docs-system/hooks/pre-commit" ]] && .ai-docs-system/hooks/pre-commit
"@ | Out-File $hookFile -Encoding UTF8 -NoNewline
        Write-Success "✓ Создан wrapper pre-commit"
      }
      
      Write-Success "✓ Хук установлен в .ai-docs-system/hooks/ (integrate режим)"
    }
  }
}

function Merge-Config {
  param([string]$TargetPath)
  
  $defaultConfig = Join-Path $ScriptDir ".ai-docs-system\config.env"
  $userConfig = Join-Path $TargetPath ".ai-docs-system\config.env"
  $tempConfig = "$userConfig.merge.tmp"
  
  if (-not (Test-Path $defaultConfig)) {
    Write-Warning "⚠ Дефолтный конфиг не найден"
    return
  }
  
  if (-not (Test-Path $userConfig)) {
    Write-Warning "⚠ Конфиг юзера не найден"
    return
  }
  
  Write-Step "Merge конфига (консервативный режим)..."
  
  # Версионированные дефолты для RULES_ENABLED
  $defaultsV20 = "doc-first,update-docs,adr,shortcuts"
  $defaultsV21 = "doc-first,update-docs,adr,shortcuts,structure"
  $defaultsV22 = $defaultsV21
  $defaultsV23 = "doc-first,update-docs,adr,shortcuts,structure,pending-write"
  
  # Получаем все ключи из дефолтного конфига
  $defaultContent = Get-Content $defaultConfig
  $keys = $defaultContent | Where-Object { $_ -match '^([A-Z_]+)=' } | ForEach-Object {
    ($_ -split '=', 2)[0]
  } | Sort-Object -Unique
  
  # Начинаем с конфига юзера
  Copy-Item $userConfig $tempConfig -Force
  
  $added = 0
  $skipped = 0
  $additions = @()
  
  # Добавляем отсутствующие ключи
  foreach ($key in $keys) {
    $userValue = Get-ConfigValue -ConfigPath $userConfig -Key $key -Default $null
    
    if ($null -eq $userValue) {
      # Ключа нет → добавляем
      $defaultValue = Get-ConfigValue -ConfigPath $defaultConfig -Key $key -Default ""
      
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
      Write-Info "+ $key=$defaultValue"
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
  $userRules = Get-ConfigValue -ConfigPath $userConfig -Key "RULES_ENABLED" -Default ""
  
  if ($userRules -eq $defaultsV20 -or $userRules -eq $defaultsV21 -or $userRules -eq $defaultsV22) {
    # На старом дефолте → обновляем до v2.3
    $tempContent = Get-Content $tempConfig -Raw
    $tempContent = $tempContent -replace "(?m)^RULES_ENABLED=.*", "RULES_ENABLED=$defaultsV23"
    $tempContent | Out-File $tempConfig -Encoding UTF8 -NoNewline
    Write-Success "✓ RULES_ENABLED обновлён: $defaultsV23"
  } elseif ($userRules -eq "") {
    # Пусто (добавлен выше из дефолта)
  } else {
    # Кастомизирован — показываем какие правила отсутствуют
    $defaultRulesList = $defaultsV23 -split ',' | Sort-Object
    $userRulesList = $userRules -split ',' | Sort-Object
    $missingRules = $defaultRulesList | Where-Object { $_ -notin $userRulesList }
    
    if ($missingRules) {
      $missingStr = $missingRules -join ','
      Write-Warning "⚠ RULES_ENABLED не обновлён (кастомизирован: $userRules)"
      Write-Info "  Новые правила доступны: $missingStr"
      Write-Info "  Добавьте вручную: RULES_ENABLED=$userRules,$missingStr"
    }
  }
  
  # Обновляем комментарий "# Доступные правила:" с актуальным списком
  $rulesDir = Join-Path $TargetPath ".ai-docs-system\rules"
  if (Test-Path $rulesDir) {
    $availableRules = Get-ChildItem "$rulesDir\*.md" -ErrorAction SilentlyContinue | 
                      ForEach-Object { $_.BaseName } | 
                      Sort-Object
    $availableRules = $availableRules -join ","
    
    if ($availableRules) {
      $tempContent = Get-Content $tempConfig -Raw
      $tempContent = $tempContent -replace "(?m)^# Доступные правила:.*", "# Доступные правила: $availableRules"
      $tempContent | Out-File $tempConfig -Encoding UTF8 -NoNewline
      Write-Success "✓ Комментарий 'Доступные правила' обновлён"
    }
  }
  
  # Обновляем комментарий "# Доступные адаптеры:" (фиксированный список)
  $availableAdapters = "cursor,copilot,claude,cline"
  $tempContent = Get-Content $tempConfig -Raw
  $tempContent = $tempContent -replace "(?m)^# Доступные адаптеры:.*", "# Доступные адаптеры: $availableAdapters"
  $tempContent | Out-File $tempConfig -Encoding UTF8 -NoNewline
  
  # Применяем
  Move-Item $tempConfig $userConfig -Force
  
  Write-Success "Merge завершён: +$added новых, ~$skipped существующих"
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
git -C $Target rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Err "Не git-репозиторий: $Target"
  Write-Host "Инициализируйте командой: git init"
  exit 1
}

# Нормализуем Target до корня репозитория
$repoRoot = (git -C $Target rev-parse --show-toplevel 2>$null)
if ($repoRoot -and $repoRoot -ne $Target) {
  Write-Warn "TARGET не корень репозитория, использую: $repoRoot"
  $Target = $repoRoot
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
      $content = Get-Content $configDst -Raw
      $content = $content.Replace('@Pixasso', "@$owner")
      $content | Set-Content $configDst -NoNewline
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
      $content = Get-Content $configDst -Raw
      $content = $content.Replace('@Pixasso', "@$owner")
      $content | Set-Content $configDst -NoNewline
      Write-Success "config.env создан (миграция с v1, owner: @$owner)"
    } else {
      Write-Success "config.env создан (миграция с v1)"
    }
  } else {
    # Конфиг есть — мерджим новые ключи
    Merge-Config -TargetPath $Target
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
Setup-Hooks -TargetPath $Target

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
