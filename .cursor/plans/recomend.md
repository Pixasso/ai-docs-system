Новые рекомендации + диффы:

1) Audit find всё ещё сканирует весь репо
Ограничь find корнями CODE_DIRS (быстрее на монорепах).

--- a/install.sh
+++ b/install.sh
@@ -569,15 +569,15 @@
-  # Строим code_args через массив (для корректной передачи в find)
-  local code_args=()
+  # Строим список корней кода (быстрый find)
+  local code_roots=()
   IFS=',' read -ra code_arr <<< "$code_dirs"
   for dir in "${code_arr[@]}"; do
     dir=$(echo "$dir" | xargs)
-    [[ -n "$dir" && -d "$target/$dir" ]] && code_args+=("-path" "$target/$dir/*" "-o")
+    [[ -n "$dir" && -d "$target/$dir" ]] && code_roots+=("$target/$dir")
   done
-  [[ ${#code_args[@]} -gt 0 ]] && unset 'code_args[-1]'
 
-  if [[ ${#code_args[@]} -gt 0 ]]; then
+  if [[ ${#code_roots[@]} -gt 0 ]]; then
@@ -595,7 +595,7 @@
-    local find_args=("$target")
+    local find_args=("${code_roots[@]}")
@@ -603,8 +603,6 @@
-    # Добавляем code_args
-    find_args+=("(" "${code_args[@]}" ")")
-    find_args+=("-type" "f")
+    find_args+=("-type" "f")
2) pending‑updates: выставлять kind по doc_hint
Сейчас всегда code, хотя pending-write допускает infra|schema.

--- a/githooks/pre-commit
+++ b/githooks/pre-commit
@@ -149,7 +149,6 @@
-      kind="code"
       ref="commit"
       note="pre-commit"
@@ -203,6 +202,13 @@
       [[ -z "$doc_hint" ]] && doc_hint="docs/"
 
+      # kind по типу изменений
+      case "$doc_hint" in
+        "docs/infrastructure/") kind="infra" ;;
+        "docs/architecture/")   kind="schema" ;;
+        *)                      kind="code" ;;
+      esac
+
       entry="${ts}|${kind}|${ref}|${files_tab}|${doc_hint}|${note}"
После правки — ./install.sh . update чтобы синкнуть копии.

3) update.sh: retry для curl (надёжность сети)
--- a/.ai-docs-system/update.sh
+++ b/.ai-docs-system/update.sh
@@ -61,6 +61,8 @@
 log_step "Скачиваем версию: $UPDATE_REF..."
+curl_opts=(-fsSL --retry 3 --retry-delay 2 --retry-connrefused)
@@ -72,7 +74,7 @@
-  if curl -fsSL "$archive_url" -o "$tmp_dir/repo.tar.gz" 2>/dev/null; then
+  if curl "${curl_opts[@]}" "$archive_url" -o "$tmp_dir/repo.tar.gz" 2>/dev/null; then
@@ -79,7 +81,7 @@
-    if curl -fsSL "$archive_url" -o "$tmp_dir/repo.tar.gz" 2>/dev/null; then
+    if curl "${curl_opts[@]}" "$archive_url" -o "$tmp_dir/repo.tar.gz" 2>/dev/null; then
@@ -85,7 +87,7 @@
-    if curl -fsSL "$archive_url" -o "$tmp_dir/repo.tar.gz" 2>/dev/null; then
+    if curl "${curl_opts[@]}" "$archive_url" -o "$tmp_dir/repo.tar.gz" 2>/dev/null; then