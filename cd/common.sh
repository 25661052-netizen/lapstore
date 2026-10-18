#!/usr/bin/env bash
# Hàm dùng chung; deploy.sh / rollback.sh gọi file này, không chạy riêng.
set -Eeuo pipefail
SOURCE_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
validate_image() { [[ "$1" =~ ^[a-zA-Z0-9._:/-]+@sha256:[a-f0-9]{64}$ ]]; }
compose() { docker compose --project-name lapstore-live --env-file "$DEPLOY_DIR/.env" --project-directory "$DEPLOY_DIR" -f "$DEPLOY_DIR/compose.deploy.yml" "$@"; }
read_state() {
  CURRENT_SLOT=''; CURRENT_IMAGE=''; PREVIOUS_SLOT=''; PREVIOUS_IMAGE=''
  if [[ -f "$DEPLOY_DIR/state" ]]; then
    mapfile -t saved < "$DEPLOY_DIR/state"
    [[ ${#saved[@]} == 4 ]] || { echo 'State không hợp lệ.'; return 1; }
    CURRENT_SLOT=${saved[0]}; CURRENT_IMAGE=${saved[1]}; PREVIOUS_SLOT=${saved[2]}; PREVIOUS_IMAGE=${saved[3]}
    { [[ "$CURRENT_SLOT" == blue || "$CURRENT_SLOT" == green ]] && validate_image "$CURRENT_IMAGE"; } || { echo 'Current state không hợp lệ.'; return 1; }
    if [[ -n "$PREVIOUS_IMAGE" ]]; then
      { [[ "$PREVIOUS_SLOT" == blue || "$PREVIOUS_SLOT" == green ]] && [[ "$PREVIOUS_SLOT" != "$CURRENT_SLOT" ]] && validate_image "$PREVIOUS_IMAGE"; } || { echo 'Previous state không hợp lệ.'; return 1; }
    fi
  fi
}
write_state() {
  printf '%s\n%s\n%s\n%s\n' "$1" "$2" "$3" "$4" > "$DEPLOY_DIR/state.tmp"
  mv "$DEPLOY_DIR/state.tmp" "$DEPLOY_DIR/state"
}
init_context() {
  DEPLOY_DIR=${1:?DEPLOY_DIR required}
  [[ "$DEPLOY_DIR" = /* && "$DEPLOY_DIR" != / && -f "$DEPLOY_DIR/.env" ]] || { echo 'Chạy cd/init.sh trước.'; exit 1; }
  DEPLOY_DIR=$(cd "$DEPLOY_DIR" && pwd)
  [[ "$DEPLOY_DIR" != "$SOURCE_ROOT" ]] || exit 1
  for cmd in docker curl python3 flock; do command -v "$cmd" >/dev/null || { echo "Thiếu $cmd"; exit 1; }; done
  # Hai cấu hình này được đóng băng cho các phiên bản ứng dụng; thay đổi hạ tầng/schema phải làm riêng.
  cmp -s "$SOURCE_ROOT/cd/compose.deploy.yml" "$DEPLOY_DIR/compose.deploy.yml" || { echo 'Cấu hình deployment khác runtime. Cần nâng cấp hạ tầng riêng.'; exit 1; }
  cmp -s "$SOURCE_ROOT/database/schema.sql" "$DEPLOY_DIR/database/schema.sql" || { echo 'Schema khác runtime. Cần lập kế hoạch migration riêng.'; exit 1; }
  mkdir -p "$DEPLOY_DIR/reports" "$SOURCE_ROOT/reports"
  exec 9>"$DEPLOY_DIR/deployment.lock"; flock -n 9 || { echo 'Đang có deploy/rollback khác.'; exit 1; }
  read_state
  export BLUE_IMAGE=${CURRENT_IMAGE:-${NEW_IMAGE:-lapstore:local}}
  export GREEN_IMAGE=$BLUE_IMAGE
  if [[ -n "$PREVIOUS_IMAGE" ]]; then
    if [[ "$PREVIOUS_SLOT" == blue ]]; then export BLUE_IMAGE=$PREVIOUS_IMAGE; else export GREEN_IMAGE=$PREVIOUS_IMAGE; fi
  fi
  HEALTH_URL=$(compose config --format json | python3 -c 'import sys,json; p=json.load(sys.stdin)["services"]["gateway"]["ports"][0]; print("http://127.0.0.1:"+str(p["published"])+"/health")')
  # Phục hồi nếu lần trước bị kill/power loss trong lúc chuyển traffic, trước khi commit state.
  if [[ -f "$DEPLOY_DIR/pending" ]]; then
    if [[ -n "$CURRENT_IMAGE" ]]; then
      render_proxy "$CURRENT_SLOT"; compose up -d --no-deps --no-build --pull never gateway
      compose exec -T gateway nginx -t; compose exec -T gateway nginx -s reload
      wait_public "$CURRENT_IMAGE" || { echo 'Chưa phục hồi được deployment bị gián đoạn.'; exit 1; }
    else compose stop gateway || true
    fi
    rm -f "$DEPLOY_DIR/pending"
  fi
}
render_proxy() {
  local slot=$1
  [[ "$slot" == blue || "$slot" == green ]] || return 1
  # Mount cả thư mục proxy: atomic rename vẫn được container nhìn thấy.
  cat > "$DEPLOY_DIR/proxy/default.conf.tmp" <<'NGINX'
server {
  listen 80;
  server_name _;
  resolver 127.0.0.11 valid=5s;
  client_max_body_size 16k;
  location / {
    set $backend SLOT:3000;
    proxy_pass http://$backend;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Connection "";
    proxy_connect_timeout 3s;
    proxy_read_timeout 15s;
    proxy_next_upstream off;
  }
}
NGINX
  sed "s/SLOT/$slot/g" "$DEPLOY_DIR/proxy/default.conf.tmp" > "$DEPLOY_DIR/proxy/default.conf.next"
  mv "$DEPLOY_DIR/proxy/default.conf.next" "$DEPLOY_DIR/proxy/default.conf"
  rm -f "$DEPLOY_DIR/proxy/default.conf.tmp"
}
wait_public() {
  local image=$1
  for _ in $(seq 1 20); do
    if curl --fail --silent --max-time 4 "$HEALTH_URL" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status")=="ok" and d.get("release")==sys.argv[1] else 1)' "$image" 2>/dev/null; then return 0; fi
    sleep 1
  done
  return 1
}
verify_slot() {
  local slot=$1 image=$2 cid actual expected
  cid=$(compose ps -q "$slot"); [[ -n "$cid" ]]
  actual=$(docker inspect --format '{{.Image}}' "$cid"); expected=$(docker image inspect --format '{{.Id}}' "$image")
  [[ "$actual" == "$expected" ]]
  compose exec -T "$slot" node -e 'fetch("http://127.0.0.1:3000/health").then(async r=>{const d=await r.json();process.exit(r.ok&&d.release===process.env.APP_VERSION?0:1)}).catch(()=>process.exit(1))'
}
stop_monitor() {
  if [[ -n "${MONITOR_PID:-}" ]]; then kill "$MONITOR_PID" 2>/dev/null || true; wait "$MONITOR_PID" 2>/dev/null || true; MONITOR_PID=''; fi
}
save_evidence() {
  stop_monitor
  compose logs --no-color --tail 200 > "$REPORT_DIR/containers.log" 2>&1 || true
  cp -r "$REPORT_DIR/." "$SOURCE_ROOT/reports/"
  if [[ -f "$REPORT_DIR/downtime.csv" ]]; then
    python3 - "$REPORT_DIR/downtime.csv" <<'PY'
import csv,sys
rows=list(csv.DictReader(open(sys.argv[1])))
bad=[r for r in rows if r['http_status']!='200' or r['curl_exit']!='0']
print(f'Monitor: {len(rows)} samples, {len(bad)} failed. CSV: {sys.argv[1]}')
PY
  fi
}
start_monitor() {
  REPORT_DIR="$DEPLOY_DIR/reports/$(date -u +%Y%m%dT%H%M%S)-$$"
  mkdir -p "$REPORT_DIR"
  if [[ -n "$CURRENT_IMAGE" ]]; then
    bash "$SOURCE_ROOT/cd/monitor.sh" "$HEALTH_URL" "$REPORT_DIR/downtime.csv" 0 9>&- & MONITOR_PID=$!
    sleep 2
  fi
}
switch_to() {
  local slot=$1 image=$2
  TARGET_SLOT=$slot
  if [[ "$slot" == blue ]]; then export BLUE_IMAGE=$image; else export GREEN_IMAGE=$image; fi
  # Mọi image đã được pull/kiểm tra trước bước này; không build lại trên server.
  compose up -d --no-deps --no-build --pull never --wait --wait-timeout 180 "$slot"
  verify_slot "$slot" "$image"
  touch "$DEPLOY_DIR/pending"
  render_proxy "$slot"
  compose up -d --no-deps --no-build --pull never gateway
  compose exec -T gateway nginx -t
  compose exec -T gateway nginx -s reload
  wait_public "$image"
  sleep 3
  wait_public "$image"
}
restore_on_error() {
  local status=$?
  trap - ERR INT TERM
  set +e
  echo "Deployment thất bại (exit=$status)."
  if [[ -n "$CURRENT_IMAGE" ]]; then
    render_proxy "$CURRENT_SLOT"
    compose up -d --no-deps --no-build --pull never gateway
    compose exec -T gateway nginx -t && compose exec -T gateway nginx -s reload
    if wait_public "$CURRENT_IMAGE"; then
      echo 'Đã giữ/khôi phục bản cũ khỏe mạnh.'; rm -f "$DEPLOY_DIR/pending"
      if [[ -n "${TARGET_SLOT:-}" && "$TARGET_SLOT" != "$CURRENT_SLOT" ]]; then compose stop "$TARGET_SLOT"; fi
    else echo 'CRITICAL: Không xác minh được bản cũ. Xem báo cáo và state tại runtime.'; fi
  else
    compose stop gateway || true
    if [[ -n "${TARGET_SLOT:-}" ]]; then compose stop "$TARGET_SLOT"; fi
  fi
  save_evidence
  exit 1
}
