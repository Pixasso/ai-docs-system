Новые рекомендации (и диффы):

A) install.sh / install.ps1: всегда ставить в корень репо
Сейчас если запустить из поддиректории, всё ставится туда же. Надёжнее всегда поднимать TARGET до repo root.

install.sh

--- a/install.sh
+++ b/install.sh
@@ -758,6 +758,13 @@ if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
   exit 1
 fi
+
+# Нормализуем TARGET до корня репозитория
+repo_root="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || echo "")"
+if [[ -n "$repo_root" && "$repo_root" != "$TARGET" ]]; then
+  log_warn "TARGET не корень репозитория, использую: $repo_root"
+  TARGET="$repo_root"
+fi
install.ps1

--- a/install.ps1
+++ b/install.ps1
@@ -458,6 +458,12 @@ if ($LASTEXITCODE -ne 0) {
   exit 1
 }
+
+# Нормализуем Target до корня репозитория
+$repoRoot = (git -C $Target rev-parse --show-toplevel 2>$null)
+if ($repoRoot -and $repoRoot -ne $Target) {
+  Write-Warn "TARGET не корень репозитория, использую: $repoRoot"
+  $Target = $repoRoot
+}
B) update.sh: защита от пустого/пробельного UPDATE_REF
Если в config UPDATE_REF= пустой — сейчас получится пустой URL.

--- a/.ai-docs-system/update.sh
+++ b/.ai-docs-system/update.sh
@@ -48,6 +48,9 @@ get_config_value() {
 }
 
 UPDATE_REF="${UPDATE_REF:-$(get_config_value "UPDATE_REF" "main")}"
+UPDATE_REF="$(echo "$UPDATE_REF" | xargs)"
+[[ -z "$UPDATE_REF" ]] && UPDATE_REF="main"
C) audit: ускорить find (не сканировать весь репо)
Сейчас find стартует с $target и фильтрует -path. Быстрее запускать только на корнях CODE_DIRS.

--- a/install.sh
+++ b/install.sh
@@ -562,15 +562,15 @@ audit_project() {
-  # Строим code_args через массив (для корректной передачи в find)
-  local code_args=()
+  # Строим список корней кода (для быстрого find)
+  local code_roots=()
   IFS=',' read -ra code_arr <<< "$code_dirs"
   for dir in "${code_arr[@]}"; do
     dir=$(echo "$dir" | xargs)
-    [[ -n "$dir" && -d "$target/$dir" ]] && code_args+=("-path" "$target/$dir/*" "-o")
+    [[ -n "$dir" && -d "$target/$dir" ]] && code_roots+=("$target/$dir")
   done
-  [[ ${#code_args[@]} -gt 0 ]] && unset 'code_args[-1]'  # Убираем последний "-o"
 
-  if [[ ${#code_args[@]} -gt 0 ]]; then
+  if [[ ${#code_roots[@]} -gt 0 ]]; then
@@ -595,9 +595,9 @@ audit_project() {
-    local find_args=("$target")
+    local find_args=("${code_roots[@]}")
@@ -603,7 +603,6 @@ audit_project() {
-    # Добавляем code_args (правильно через массив)
-    find_args+=("(" "${code_args[@]}" ")")
+    # code_roots уже ограничивают область поиска
     find_args+=("-type" "f")