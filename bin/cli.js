#!/usr/bin/env node

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const SCRIPT_DIR = path.join(__dirname, '..');
const VERSION = '2.5.2';

// Определяем ОС
const isWindows = process.platform === 'win32';

// Парсим аргументы
const args = process.argv.slice(2);
const command = args[0];
const targetPath = args[1] || process.cwd();
const mode = args[2] || 'install';

// Цвета для консоли
const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  blue: '\x1b[34m',
  yellow: '\x1b[33m'
};

function log(msg, color = 'reset') {
  console.log(`${colors[color]}${msg}${colors.reset}`);
}

function showHelp() {
  console.log(`
AI Docs System v${VERSION}
Универсальная модульная система автоматизации документации

Использование:
  npx ai-docs-system <команда> [опции]

Команды:
  install <путь>     Установить в проект (по умолчанию: текущая директория)
  update <путь>      Обновить существующую установку
  uninstall <путь>   Удалить из проекта
  audit <путь>       Проверить здоровье документации
  version            Показать версию

Примеры:
  npx ai-docs-system install .
  npx ai-docs-system update /path/to/project
  npx ai-docs-system audit .

Альтернативный способ (bash):
  ./install.sh /path/to/project install
  
Документация: https://github.com/Pixasso/ai-docs-system
`);
}

function runBashScript(scriptName, targetPath, mode) {
  const scriptPath = path.join(SCRIPT_DIR, scriptName);
  
  if (!fs.existsSync(scriptPath)) {
    log(`✗ Скрипт не найден: ${scriptPath}`, 'red');
    process.exit(1);
  }

  log(`→ Запускаю ${scriptName}...`, 'blue');
  
  const child = spawn('bash', [scriptPath, targetPath, mode], {
    cwd: SCRIPT_DIR,
    stdio: 'inherit',
    env: { ...process.env, SCRIPT_DIR }
  });

  child.on('error', (err) => {
    log(`✗ Ошибка запуска: ${err.message}`, 'red');
    log('💡 Убедитесь что bash установлен', 'yellow');
    log('💡 Или используйте ./install.sh напрямую', 'yellow');
    process.exit(1);
  });

  child.on('close', (code) => {
    process.exit(code);
  });
}

function runPowerShellScript(targetPath, mode) {
  const scriptPath = path.join(SCRIPT_DIR, 'install.ps1');
  
  if (!fs.existsSync(scriptPath)) {
    log(`✗ Скрипт не найден: ${scriptPath}`, 'red');
    process.exit(1);
  }

  log(`→ Запускаю install.ps1...`, 'blue');
  
  const child = spawn('powershell.exe', [
    '-ExecutionPolicy', 'Bypass',
    '-File', scriptPath,
    '-Target', targetPath,
    '-Mode', mode
  ], {
    cwd: SCRIPT_DIR,
    stdio: 'inherit'
  });

  child.on('error', (err) => {
    log(`✗ Ошибка запуска: ${err.message}`, 'red');
    log('💡 Используйте install.ps1 напрямую', 'yellow');
    process.exit(1);
  });

  child.on('close', (code) => {
    process.exit(code);
  });
}

// Главная логика
switch (command) {
  case 'install':
  case 'update':
  case 'uninstall':
  case 'audit':
    if (isWindows) {
      runPowerShellScript(targetPath, command);
    } else {
      runBashScript('install.sh', targetPath, command);
    }
    break;

  case 'version':
  case '--version':
  case '-v':
    console.log(`AI Docs System v${VERSION}`);
    break;

  case 'help':
  case '--help':
  case '-h':
  case undefined:
    showHelp();
    break;

  default:
    log(`✗ Неизвестная команда: ${command}`, 'red');
    log('💡 Запустите: npx ai-docs-system help', 'yellow');
    process.exit(1);
}
