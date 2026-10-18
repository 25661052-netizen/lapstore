#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /backups
while true; do
  file="/backups/lapstore-$(date -u +%Y%m%dT%H%M%S).sql"
  if mysqldump --host=db --user=lapstore --single-transaction --no-tablespaces --skip-lock-tables --set-gtid-purged=OFF --column-statistics=0 lapstore > "$file.tmp"; then
    mv "$file.tmp" "$file"
    echo "Backup OK: $file"
    shopt -s nullglob
    files=(/backups/lapstore-*.sql)
    # Giữ 7 bản thành công gần nhất; không phải PITR.
    count=${#files[@]}
    for ((i=0; i<count-7; i++)); do rm -- "${files[i]}"; done
  else
    rm -f "$file.tmp"
    echo 'Backup thất bại; giữ nguyên các bản sao trước.' >&2
  fi
  sleep 86400
done
