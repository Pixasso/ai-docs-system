Новые рекомендации (с диффами):

1) Audit: .queue0 считать рядом с queue‑файлом, не через общий find
Сейчас fallback ищется в .ai-docs-system/state, но если пути PENDING_UPDATES_* кастомные — пропускается.

--- a/install.sh
+++ b/install.sh
@@ -524,6 +524,16 @@
   if [[ -n "$pending_shared" ]]; then
     # Определяем абсолютный путь для shared queue
     local shared_path
@@ -542,12 +552,17 @@
     fi
   fi
 
-  # .queue0 (fallback)
-  local queue0_files
-  queue0_files=$(find "$target/.ai-docs-system/state" -name "*.queue0" 2>/dev/null)
-  if [[ -n "$queue0_files" ]]; then
-    local queue0_count
-    queue0_count=$(echo "$queue0_files" | wc -l | xargs)
+  # .queue0 (fallback) рядом с локальной/шаред очередью
+  local queue0_count=0
+  if [[ "$queue_path" == *.queue ]]; then
+    local queue0_local="${queue_path%.queue}.queue0"
+    [[ -f "$queue0_local" ]] && ((queue0_count++))
+  fi
+  if [[ -n "$pending_shared" ]]; then
+    local shared_queue_path
+    [[ "$pending_shared" == /* ]] && shared_queue_path="$pending_shared" || shared_queue_path="$target/$pending_shared"
+    [[ "$shared_queue_path" == *.queue && -f "${shared_queue_path%.queue}.queue0" ]] && ((queue0_count++))
+  fi
+  if [[ $queue0_count -gt 0 ]]; then
     echo "  ⏳ $queue0_count .queue0 файлов (fallback)"
     ((pending_count += queue0_count))
   fi
2) update.sh: нормальная обработка ошибки tar -tzf (set -e + pipefail)
Сейчас при сбое tar скрипт вылетает молча. Лучше с явным сообщением.

--- a/.ai-docs-system/update.sh
+++ b/.ai-docs-system/update.sh
@@ -118,7 +118,11 @@
-if ! tar -xzf "$tmp_dir/repo.tar.gz" -C "$tmp_dir"; then
+if ! extract_dir="$(tar -tzf "$tmp_dir/repo.tar.gz" | head -1 | cut -d/ -f1)"; then
+  log_error "Не удалось определить корневую папку архива"
+  exit 1
+fi
+
+if ! tar -xzf "$tmp_dir/repo.tar.gz" -C "$tmp_dir"; then
   log_error "Не удалось распаковать архив"
   exit 1
 fi
-
-# После распаковки файлы в ai-docs-system-{ref}/
-repo_dir="$tmp_dir/$extract_dir"
+# После распаковки файлы в ai-docs-system-{ref}/
+repo_dir="$tmp_dir/$extract_dir"
3) pre-commit: убрать повторный split MAP_* (микро‑ускорение)
Сейчас трижды парсишь MAP_*. Можно пред‑нормализовать, но без оверинжа:

--- a/githooks/pre-commit
+++ b/githooks/pre-commit
@@ -169,6 +169,8 @@
-      map_features="$(get_config_value "$config" "MAP_FEATURES" "src/,app/,lib/")"
+      map_features="$(get_config_value "$config" "MAP_FEATURES" "src/,app/,lib/")"
       map_architecture="$(get_config_value "$config" "MAP_ARCHITECTURE" "schema,models,types")"
       map_infrastructure="$(get_config_value "$config" "MAP_INFRASTRUCTURE" "deploy,docker")"
+      map_features="${map_features//[[:space:]]/}"
+      map_architecture="${map_architecture//[[:space:]]/}"
+      map_infrastructure="${map_infrastructure//[[:space:]]/}"
(И это автоматически ускоряет все три IFS=',' read -ra ... циклы.)