Надёжность (критичное/высокое)
install.sh: local вне функции → краш при install/update
Файл: install.sh L861, L894
Проблема: local owner_escaped в top‑level блоке. При set -euo pipefail скрипт падает.
Варианты:
A) убрать local (простой фикс)
B) вынести блок в функцию set_owner() и сделать local внутри

update.sh обновляет только install.sh, а не весь модуль
Файл: .ai-docs-system/update.sh L53–85
Проблема: скачивается только install.sh, но он копирует правила/шаблоны из своего SCRIPT_DIR. В temp‑директории этих файлов нет → update “пустой”.
Варианты:
A) скачивать tarball репозитория (curl .../archive/refs/tags/vX.tar.gz) и запускать install.sh внутри распакованного
B) в install.sh добавить фетч нужных файлов при отсутствии $SCRIPT_DIR/.ai-docs-system/**
C) убрать update.sh, оставить только “clone + install.sh update”

pre-commit: PENDING_UPDATES_WRITE=shared пишет пустую запись
Файл: githooks/pre-commit L124–250
Проблема: все переменные (ts/kind/ref/doc_hint/entry) вычисляются только в ветке local|both. При shared они не определены → запись битая/пустая.
Варианты:
A) вынести расчёт общих переменных до ветвления
B) дублировать вычисление в shared‑ветке, если local не был выполнен
C) трактовать shared как both (чтобы общие данные гарантированно были)

install.ps1 интеграция ломает существующий bash‑hook
Файл: install.ps1 L259–263
Проблема: в существующий pre-commit добавляется PowerShell‑код, но Git на Windows запускает hooks через sh. Это может сломать hook и блокировать commit.
Варианты:
A) если hook уже есть, дописывать bash‑строку ./.ai-docs-system/hooks/pre-commit || true
B) детектировать shebang и добавлять код под неё (bash/ps1)
C) если hook “не наш”, не модифицировать — только печатать инструкцию

Дрейф между githooks/ и .githooks/
Файлы: githooks/pre-commit vs .githooks/pre-commit
Проблема: файлы разные (в .githooks всё ещё regex‑логика doc_hint, grep -qE вместо grep -qF).
Варианты:
A) хранить только githooks/, генерировать .githooks/ при install/update
B) синхронизировать .githooks/ из githooks/ в репо
C) CI‑проверка, что файлы идентичны

Надёжность (среднее)
RULES_ENABLED не авто‑обновляется до pending-write
Файлы: install.sh L305–394, install.ps1 L302–386
Проблема: дефолты не обновлены под v2.3; если у юзера дефолт v2.1, он не получит pending-write.
Варианты:
A) добавить defaults_v2_3="...structure,pending-write" и обновлять при defaults_v2_1
B) вычислять “дефолт” из нового config.env и сравнивать с текущим

build_instructions дефолт без pending-write
Файлы: install.sh L98, install.ps1 L51
Проблема: если config отсутствует/битый, rule pending-write не попадёт в instructions.md.
Варианты:
A) обновить дефолтный список
B) брать дефолт из SCRIPT_DIR/.ai-docs-system/config.env

Очередь pending updates теряет файлы (>10)
Файл: githooks/pre-commit L91–147
Проблема: массив ограничен 10 файлами и для вывода, и для записи → в очередь попадает неполный список.
Варианты:
A) хранить changed_code_all для записи, changed_code_arr для вывода
B) не ограничивать массив, ограничивать только печать

Пустые паттерны в MAP_* ломают doc_hint
Файл: githooks/pre-commit L158–186
Проблема: если MAP_FEATURES= пустой, grep -qF "" матчится на всё → doc_hint всегда docs/features/.
Варианты:
A) [[ -z "$pattern" ]] && continue
B) не создавать массив, если строка пустая

Безопасность
Supply‑chain риск update.sh
Файл: .ai-docs-system/update.sh L53–85
Проблема: скачивание и запуск install.sh с main без проверки целостности.
Варианты:
A) pin по tag + SHA256
B) gh release download + проверка checksum
C) опционально: UPDATE_PIN=v2.3.3 в config.env
Масштабируемость / скорость
Audit использует find по всему репо
Файл: install.sh audit
Проблема: даже с prune это O(N) по всему дереву. На больших монорепах заметно.
Варианты:
A) ограничить find только CODE_DIRS (сначала сформировать список корней)
B) добавить лимит глубины или early‑exit при большом объёме
Док‑несостыковки
Rule pending‑write ссылается на IGNORE_EXTS, которого нет
Файл: .ai-docs-system/rules/pending-write.md L69
Варианты:
A) убрать упоминание IGNORE_EXTS
B) добавить IGNORE_EXTS в config.env и в pre‑commit логику
И ещё раз про новый регресс в audit find (как просил)
install.sh audit, блок “Документы в коде”
Сейчас code_pattern строится строкой с -o -path ..., а потом используется как один аргумент -path "$target/$code_pattern". Это делает find почти всегда пустым.
Фикс: собрать code_args массивом, как prune_args/ext_args, и добавить в find_args корректно.

