Новые рекомендации (без SHA‑auto):

1) update.sh: try gh как fallback (скорость/надёжность)
Если curl заблокирован корпоративной проксей, gh уже авторизован.
Добавить fallback:

if ! curl ...; then
  if command -v gh >/dev/null 2>&1; then
    gh api -H "Accept: application/octet-stream" \
      "/repos/Pixasso/ai-docs-system/tarball/${UPDATE_REF}" > "$tmp_dir/repo.tar.gz" || true
  fi
fi
2) pre-commit: doc_hint по первому изменённому файлу — может быть неверно
Если смешанные изменения (infra + feature), сейчас берётся первый файл.
Простой апгрейд без оверинжа:

если любой файл матчится infra → docs/infrastructure/
иначе если любой матчится architecture → docs/architecture/
иначе features.
Это уменьшит ложные рекомендации в pending‑queue.
3) audit: pending_count считает только .queue (строки), но .queue0 может быть >1 записи
Сейчас .queue0 счётчик == количество файлов .queue0, а не записей.
В .queue0 записи разделены двойным NUL — можно хотя бы подсчитать \0\0 через tr -cd + awk (дёшево).

Если хочешь — дам диффы по этим 3 пунктам.