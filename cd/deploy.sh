#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
NEW_IMAGE=${1:?Usage: bash cd/deploy.sh IMAGE_DIGEST DEPLOY_DIR}
validate_image "$NEW_IMAGE" || { echo 'Deploy yêu cầu image@sha256:...'; exit 1; }
init_context "${2:?DEPLOY_DIR required}"
if [[ "$NEW_IMAGE" == "$CURRENT_IMAGE" ]]; then wait_public "$CURRENT_IMAGE"; echo 'Đúng phiên bản này đang chạy.'; exit 0; fi
start_monitor
trap restore_on_error ERR INT TERM
# Registry lỗi: dừng tại pull, chưa thay đổi slot đang phục vụ.
docker pull "$NEW_IMAGE"
if [[ -z "$CURRENT_IMAGE" ]]; then
  compose pull db gateway
  compose up -d --no-build --pull never --wait --wait-timeout 240 db
fi
NEXT_SLOT=blue; [[ "$CURRENT_SLOT" != blue ]] || NEXT_SLOT=green
switch_to "$NEXT_SLOT" "$NEW_IMAGE"
write_state "$NEXT_SLOT" "$NEW_IMAGE" "$CURRENT_SLOT" "$CURRENT_IMAGE"
rm -f "$DEPLOY_DIR/pending"
trap - ERR INT TERM
printf 'current=%s\nimage=%s\nprevious=%s\n' "$NEXT_SLOT" "$NEW_IMAGE" "$CURRENT_IMAGE" > "$REPORT_DIR/deployment.txt"
sleep 2
save_evidence
echo "Deploy thành công: $NEXT_SLOT — $NEW_IMAGE"
# Giữ slot cũ chạy và image cũ trên máy để rollback không cần registry.
