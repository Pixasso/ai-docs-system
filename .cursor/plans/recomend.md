Новые рекомендации (с диффами):

1) update.sh: temp‑script не чистится (self‑copy leak)
Сейчас exec убивает trap → файл в /tmp остаётся.
Фикс: передать путь через env и ставить trap во второй фазе.

--- a/.ai-docs-system/update.sh
+++ b/.ai-docs-system/update.sh
@@ -15,11 +15,11 @@ if [[ -z "${_UPDATE_RUNNING_FROM_TEMP:-}" ]]; then
   export _UPDATE_RUNNING_FROM_TEMP=1
   _tmp_script="$(mktemp)"
-  trap "rm -f '$_tmp_script'" EXIT
+  export _UPDATE_TMP_SCRIPT="$_tmp_script"
   cp "$0" "$_tmp_script"
   chmod +x "$_tmp_script"
   exec bash "$_tmp_script" "$@"
 fi
 
 set -euo pipefail
+[[ -n "${_UPDATE_TMP_SCRIPT:-}" ]] && trap 'rm -f "$_UPDATE_TMP_SCRIPT"' EXIT
2) install.sh audit: корректная обработка файлов с \n (надежность)
Сейчас find → echo | while read ломается на нестандартных именах.
Фикс через -print0:

--- a/install.sh
+++ b/install.sh
@@ -606,17 +606,18 @@
-    local readme_files
-    readme_files=$(find "${find_args[@]}" 2>/dev/null)
-    
-    if [[ -n "$readme_files" ]]; then
-      readme_count=$(echo "$readme_files" | wc -l | xargs)
-      echo "$readme_files" | while read -r f; do
-        local rel_path="${f#$target/}"
-        echo "  ⚠ $rel_path"
-        echo "     → Переместить в: docs/"
-        echo ""
-      done
-    else
+    readme_count=0
+    while IFS= read -r -d '' f; do
+      ((readme_count++))
+      local rel_path="${f#$target/}"
+      echo "  ⚠ $rel_path"
+      echo "     → Переместить в: docs/"
+      echo ""
+    done < <(find "${find_args[@]}" -print0 2>/dev/null)
+
+    if [[ $readme_count -eq 0 ]]; then
       echo "  ✓ Документы в коде не найдены"
       echo ""
     fi