@echo off
REM AI Docs System — Pre-commit Hook (Windows)
REM Напоминает обновить документацию при изменении кода
REM НЕ блокирует коммиты — просто дружеское напоминание

setlocal enabledelayedexpansion

set "CHANGED_CODE="
set "CHANGED_DOCS="

REM Проверяем изменения в коде
for /f "usebackq delims=" %%f in (`git diff --cached --name-only 2^>nul`) do (
  echo %%f | findstr /r /c:"^src/" /c:"^services/" >nul 2>&1
  if !errorlevel! equ 0 (
    set "CHANGED_CODE=!CHANGED_CODE! %%f"
  )
  echo %%f | findstr /r /c:"^docs/" >nul 2>&1
  if !errorlevel! equ 0 (
    set "CHANGED_DOCS=1"
  )
)

REM Если код изменился, но документация нет — показываем напоминание
if defined CHANGED_CODE if not defined CHANGED_DOCS (
  echo.
  echo ============================================================
  echo   Внимание: Вы изменили код, но не обновили документацию
  echo ============================================================
  echo.
  echo Изменённые файлы:
  for %%f in (!CHANGED_CODE!) do (
    echo   - %%f
  )
  echo.
  echo Совет: Запустите Cursor Agent и введите "==" для автообновления
  echo.
  echo ============================================================
  echo.
)

REM Никогда не блокируем коммит
exit /b 0
