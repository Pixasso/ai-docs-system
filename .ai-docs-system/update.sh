#!/usr/bin/env bash
#
# AI Docs System — Self-Update Script
# Обновляет систему прямо из проекта
#

VERSION="2.3.6"

set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "${BLUE}→${NC} $1"; }

# Находим корень репозитория
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  log_error "Не найден git-репозиторий"
  exit 1
}

config_file="$repo_root/.ai-docs-system/config.env"

# Проверяем что система установлена
if [[ ! -f "$config_file" ]]; then
  log_error "AI Docs System не установлена в этом проекте"
  echo ""
  echo "Запустите сначала:"
  echo "  cd /path/to/ai-docs-system"
  echo "  ./install.sh \"$repo_root\" install"
  exit 1
fi

# Читаем UPDATE_REF из конфига (для pin на конкретную версию/тег)
get_config_value() {
  local key="$1"
  local default="$2"
  grep "^${key}=" "$config_file" 2>/dev/null | head -1 | cut -d'=' -f2- || echo "$default"
}

UPDATE_REF="${UPDATE_REF:-$(get_config_value "UPDATE_REF" "main")}"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  AI Docs System — Обновление                                 ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Проект: $repo_root"
echo ""

# Временная папка
tmp_dir=$(mktemp -d)
trap "rm -rf $tmp_dir" EXIT

log_step "Скачиваем версию: $UPDATE_REF..."

# Формируем URL для скачивания (поддержка веток и тегов)
if [[ "$UPDATE_REF" == v* ]]; then
  # Тег (v2.3.5)
  archive_url="https://github.com/Pixasso/ai-docs-system/archive/refs/tags/${UPDATE_REF}.tar.gz"
  extract_dir="ai-docs-system-${UPDATE_REF#v}"
else
  # Ветка (main, develop)
  archive_url="https://github.com/Pixasso/ai-docs-system/archive/refs/heads/${UPDATE_REF}.tar.gz"
  extract_dir="ai-docs-system-${UPDATE_REF}"
fi

# Скачиваем архив репозитория
if ! curl -fsSL "$archive_url" -o "$tmp_dir/repo.tar.gz"; then
  log_error "Не удалось скачать архив репозитория ($UPDATE_REF)"
  exit 1
fi

log_step "Распаковываем..."
if ! tar -xzf "$tmp_dir/repo.tar.gz" -C "$tmp_dir"; then
  log_error "Не удалось распаковать архив"
  exit 1
fi

# После распаковки файлы в ai-docs-system-{ref}/
repo_dir="$tmp_dir/$extract_dir"

if [[ ! -f "$repo_dir/install.sh" ]]; then
  log_error "Структура архива неожиданная"
  exit 1
fi

chmod +x "$repo_dir/install.sh"

# Показываем версию
current_version="$VERSION"
new_version=$(grep "^VERSION=" "$repo_dir/install.sh" | head -1 | cut -d'"' -f2)

echo ""
echo "Текущая версия: $current_version"
echo "Новая версия: $new_version"
echo ""

if [[ "$current_version" == "$new_version" ]]; then
  log_warn "Уже установлена последняя версия"
  echo ""
  read -p "Переустановить? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Отменено"
    exit 0
  fi
fi

log_step "Запускаем обновление..."
echo ""

# Запускаем install.sh в режиме update
cd "$repo_dir"
./install.sh "$repo_root" update

echo ""
log_info "Обновление завершено!"
echo ""
