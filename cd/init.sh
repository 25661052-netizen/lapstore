#!/usr/bin/env bash
# Chạy một lần trên server: bash cd/init.sh /home/you/lapstore-runtime
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dir=${1:?Usage: bash cd/init.sh ABSOLUTE_DEPLOY_DIR}
[[ "$dir" = /* && "$dir" != / ]] || { echo 'DEPLOY_DIR phải là đường dẫn tuyệt đối, khác /.'; exit 1; }
mkdir -p "$dir"; dir=$(cd "$dir" && pwd)
[[ "$dir" != "$root" ]] || { echo 'Dùng thư mục runtime riêng, không dùng thư mục source.'; exit 1; }
umask 077
mkdir -p "$dir/database" "$dir/proxy" "$dir/reports"
if [[ -f "$dir/compose.deploy.yml" ]]; then
  cmp -s "$root/cd/compose.deploy.yml" "$dir/compose.deploy.yml" || { echo 'Cấu hình runtime đã khác. Không tự ghi đè.'; exit 1; }
else
  cp "$root/cd/compose.deploy.yml" "$dir/compose.deploy.yml"
  cp "$root/database/schema.sql" "$dir/database/schema.sql"
  chmod 644 "$dir/database/schema.sql"
fi
if [[ ! -f "$dir/.env" ]]; then
  { printf 'DB_PASSWORD=%s\n' "$(openssl rand -hex 24)";
    printf 'MYSQL_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 24)";
    printf 'GATEWAY_BIND=127.0.0.1\nGATEWAY_PORT=8080\n'; } > "$dir/.env"
fi
echo "Runtime đã chuẩn bị: $dir"
echo 'Chưa chạy container. Bước tiếp theo: cấu hình GitHub Variables/Secrets và runner.'
