#!/usr/bin/env bash
# Chạy trên Linux server. Registry chỉ mở trên loopback, dùng runner cùng máy.
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
[[ ! -e certs/ca.key && ! -e auth/htpasswd ]] || { echo 'Đã có cấu hình; không ghi đè khóa/tài khoản.'; exit 1; }
command -v openssl >/dev/null; docker info >/dev/null
umask 077
mkdir -p certs auth
read -rp 'Tên tài khoản registry (ví dụ lapstore-ci): ' registry_user
[[ "$registry_user" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Tên tài khoản không hợp lệ.'; exit 1; }
read -rsp 'Mật khẩu registry (ít nhất 16 ký tự): ' registry_password; echo
[[ ${#registry_password} -ge 16 ]] || { echo 'Mật khẩu quá ngắn.'; exit 1; }
docker pull httpd:2.4-alpine
printf '%s\n' "$registry_password" | docker run --rm -i httpd:2.4-alpine htpasswd -Bni "$registry_user" > auth/htpasswd
unset registry_password
openssl req -x509 -newkey rsa:3072 -nodes -days 365 -keyout certs/ca.key -out certs/ca.crt -subj '/CN=LapStore Lab CA' >/dev/null 2>&1
openssl req -newkey rsa:3072 -nodes -keyout certs/server.key -out certs/server.csr -subj '/CN=registry.lapstore.internal' >/dev/null 2>&1
printf 'subjectAltName=DNS:registry.lapstore.internal,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' > certs/server.ext
openssl x509 -req -in certs/server.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial -days 365 -out certs/server.crt -extfile certs/server.ext >/dev/null 2>&1
echo 'Đã tạo auth và TLS. Làm bước trust CA + /etc/hosts trong docs/REGISTRY.md trước khi docker login.'
