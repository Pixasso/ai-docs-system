@echo off
REM AI Docs System — Pre-commit Hook (Windows)
REM Запускает bash-версию хука если доступна
REM НЕ блокирует коммиты

setlocal

REM Проверяем наличие bash (Git Bash, WSL, etc.)
where bash >nul 2>&1
if %errorlevel% equ 0 (
  bash "%~dp0pre-commit"
  exit /b %errorlevel%
)

REM Fallback: показываем простое напоминание на чистом CMD
for /f "usebackq delims=" %%f in (`git diff --cached --name-only 2^>nul`) do (
  echo %%f | findstr /r /c:"^src/" /c:"^app/" /c:"^lib/" /c:"^services/" >nul 2>&1
  if !errorlevel! equ 0 (
    echo.
    echo ============================================================
    echo   Напоминание: проверьте, нужно ли обновить документацию
    echo ============================================================
    echo   Конфигурация: .ai-docs-system/config.env
    echo ============================================================
    echo.
    goto :done
  )
)
:done

REM Никогда не блокируем коммит
exit /b 0
