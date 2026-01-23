1) install.sh — git‑проверка (worktree/submodule) + git в PATH
--- a/install.sh
+++ b/install.sh
@@ -752,10 +752,15 @@ TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
   exit 1
 }
 
-# Проверка git
-if [[ ! -d "$TARGET/.git" ]]; then
+# Проверка git
+if ! command -v git >/dev/null 2>&1; then
+  log_error "git не найден в PATH"
+  exit 1
+fi
+
+if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
   log_error "Не git-репозиторий: $TARGET"
   echo "Инициализируйте командой: git init"
   exit 1
 }
2) install.ps1 — git‑проверка без .git директории
--- a/install.ps1
+++ b/install.ps1
@@ -458,10 +458,11 @@ try {
   exit 1
 }
 
-# Проверка git-репозитория
-if (-not (Test-Path (Join-Path $Target ".git"))) {
+# Проверка git-репозитория
+git -C $Target rev-parse --git-dir *> $null
+if ($LASTEXITCODE -ne 0) {
   Write-Err "Не git-репозиторий: $Target"
   Write-Host "Инициализируйте командой: git init"
   exit 1
 }
3) install.ps1 — убрать Join-String (PS5.1)
--- a/install.ps1
+++ b/install.ps1
@@ -417,10 +417,10 @@ if (Test-Path $rulesDir) {
-    $availableRules = Get-ChildItem "$rulesDir\*.md" -ErrorAction SilentlyContinue | 
-                      ForEach-Object { $_.BaseName } | 
-                      Sort-Object |
-                      Join-String -Separator ","
+    $availableRules = Get-ChildItem "$rulesDir\*.md" -ErrorAction SilentlyContinue | 
+                      ForEach-Object { $_.BaseName } | 
+                      Sort-Object
+    $availableRules = $availableRules -join ","
4) update.sh — корректный extract_dir для refs с /
--- a/.ai-docs-system/update.sh
+++ b/.ai-docs-system/update.sh
@@ -75,6 +75,13 @@ if ! curl -fsSL "$archive_url" -o "$tmp_dir/repo.tar.gz"; then
   exit 1
 fi
 
+# Определяем корневую папку архива (устойчиво для refs с '/')
+extract_dir="$(tar -tzf "$tmp_dir/repo.tar.gz" | head -1 | cut -d/ -f1)"
+if [[ -z "$extract_dir" ]]; then
+  log_error "Не удалось определить корневую папку архива"
+  exit 1
+fi
+
 log_step "Распаковываем..."
 if ! tar -xzf "$tmp_dir/repo.tar.gz" -C "$tmp_dir"; then
   log_error "Не удалось распаковать архив"
5) pre-commit — опциональные docs в monorepo (packages/*/docs, apps/*/docs)
Добавляем DOC_DIRS_ROOTS (по умолчанию пусто).
Правим githooks/pre-commit и потом синкаем копии через install.sh update.

--- a/githooks/pre-commit
+++ b/githooks/pre-commit
@@ -27,6 +27,7 @@ CODE_DIRS="src,app,apps,packages,services,server,client,api,lib,cmd,internal,supabase"
 CODE_EXTS="ts,tsx,js,jsx,mjs,cjs,py,go,rs,java,kt,kts,cs,php,rb,swift,c,cpp,h,hpp,sql,graphql,proto"
 DOC_DIRS="docs,doc,documentation"
+DOC_DIRS_ROOTS=""
 DOC_EXTS="md,mdx,rst,adoc"
 DOC_FILES="README.md,CHANGELOG.md,CONTRIBUTING.md,ARCHITECTURE.md"
 IGNORE_DIRS="node_modules,vendor,dist,build,.git,.idea,.vscode,__pycache__,.next,.nuxt"
@@ -36,6 +37,7 @@ if [[ -f "$config" ]]; then
   CODE_EXTS="$(get_config_value "$config" "CODE_EXTS" "$CODE_EXTS")"
   DOC_DIRS="$(get_config_value "$config" "DOC_DIRS" "$DOC_DIRS")"
+  DOC_DIRS_ROOTS="$(get_config_value "$config" "DOC_DIRS_ROOTS" "$DOC_DIRS_ROOTS")"
   DOC_EXTS="$(get_config_value "$config" "DOC_EXTS" "$DOC_EXTS")"
   DOC_FILES="$(get_config_value "$config" "DOC_FILES" "$DOC_FILES")"
   IGNORE_DIRS="$(get_config_value "$config" "IGNORE_DIRS" "$IGNORE_DIRS")"
@@ -66,9 +68,16 @@ DOC_EXTS_RE="$(csv_to_re "$DOC_EXTS")"
 DOC_FILES_RE="$(csv_to_re "$DOC_FILES")"
 IGNORE_DIRS_RE="$(csv_to_re "$IGNORE_DIRS")"
+DOC_DIRS_ROOTS_RE=""
+if [[ -n "$DOC_DIRS_ROOTS" ]]; then
+  DOC_DIRS_ROOTS_RE="$(csv_to_re "$DOC_DIRS_ROOTS")"
+fi
 
 # Паттерн для документации: ТОЛЬКО папки docs/ ИЛИ корневые файлы (README.md и т.д.)
 # НЕ включаем *.md везде — иначе .ai-docs-system/instructions.md считается документацией
-DOCS_RE="^${DOC_DIRS_RE}/|^${DOC_FILES_RE}$"
+DOCS_RE="^${DOC_DIRS_RE}/|^${DOC_FILES_RE}$"
+if [[ -n "$DOC_DIRS_ROOTS_RE" ]]; then
+  DOCS_RE="${DOCS_RE}|(^|/)${DOC_DIRS_ROOTS_RE}/[^/]+/${DOC_DIRS_RE}/"
+fi
Синхронизация копий после правки:

./install.sh . update
6) config.env — документация опции DOC_DIRS_ROOTS
--- a/.ai-docs-system/config.env
+++ b/.ai-docs-system/config.env
@@ -21,6 +21,10 @@ DOC_DIRS=docs,doc,documentation
 # Какие расширения считать документацией
 DOC_EXTS=md,mdx,rst,adoc
 
+# Доп. корни docs в monorepo (пример: packages,apps)
+# DOC_DIRS_ROOTS=packages,apps
+
 # Отдельные файлы документации в корне
 DOC_FILES=README.md,CHANGELOG.md,CONTRIBUTING.md,ARCHITECTURE.md