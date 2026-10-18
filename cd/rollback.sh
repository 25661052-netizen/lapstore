#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
init_context "${1:?Usage: bash cd/rollback.sh DEPLOY_DIR}"
[[ -n "$PREVIOUS_IMAGE" ]] || { echo 'Chưa có phiên bản trước để rollback.'; exit 1; }
docker image inspect "$PREVIOUS_IMAGE" >/dev/null || { echo 'Image cũ đã bị xóa khỏi máy. Cần pull lại trước khi rollback.'; exit 1; }
start_monitor
trap restore_on_error ERR INT TERM
switch_to "$PREVIOUS_SLOT" "$PREVIOUS_IMAGE"
write_state "$PREVIOUS_SLOT" "$PREVIOUS_IMAGE" "$CURRENT_SLOT" "$CURRENT_IMAGE"
rm -f "$DEPLOY_DIR/pending"
trap - ERR INT TERM
printf 'rollback_to=%s\nimage=%s\n' "$PREVIOUS_SLOT" "$PREVIOUS_IMAGE" > "$REPORT_DIR/deployment.txt"
sleep 2
save_evidence
echo "Rollback thành công: $PREVIOUS_IMAGE"
