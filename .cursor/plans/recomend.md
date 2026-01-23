Согласен. SHA256 как opt‑in — ок, по умолчанию не надо. Но overhead можно почти убрать автоматизацией:

Компромисс без ручного ввода:

Поддержать UPDATE_SHA256=auto в update.sh:
если UPDATE_REF — tag, пробовать скачать checksums.txt из релиза.
Если файла нет — просто предупреждение и continue.
Мини‑код (update.sh):

UPDATE_SHA256="${UPDATE_SHA256:-$(get_config_value "UPDATE_SHA256" "")}"
 
if [[ "$UPDATE_SHA256" == "auto" && "$UPDATE_REF" == v* ]]; then
  checksums_url="https://github.com/Pixasso/ai-docs-system/releases/download/${UPDATE_REF}/checksums.txt"
  if curl -fsSL "$checksums_url" -o "$tmp_dir/checksums.txt"; then
    UPDATE_SHA256="$(grep "repo.tar.gz" "$tmp_dir/checksums.txt" | awk '{print $1}')"
  else
    log_warn "checksums.txt не найден — пропускаю проверку"
  fi
fi
Автоматическая публикация checksums (GitHub Action):

name: release-checksums
on:
  release:
    types: [published]
 
jobs:
  checksums:
    runs-on: ubuntu-latest
    steps:
      - name: Download tag tarball
        run: |
          TAG="${{ github.event.release.tag_name }}"
          curl -L "https://github.com/${{ github.repository }}/archive/refs/tags/${TAG}.tar.gz" -o repo.tar.gz
      - name: Create checksums
        run: sha256sum repo.tar.gz > checksums.txt
      - name: Upload checksums
        uses: softprops/action-gh-release@v1
        with:
          files: checksums.txt
Итого:

99% пользователей ничего не трогают.
Enterprise ставит UPDATE_SHA256=auto + UPDATE_REF=vX и получает проверку без ручного копипаста.
Никакого оверхеда для мейнтейнера, если есть release‑workflow.