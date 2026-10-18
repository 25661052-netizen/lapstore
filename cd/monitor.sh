#!/usr/bin/env bash
# bash cd/monitor.sh http://127.0.0.1:8080/health reports/downtime.csv 60
# DURATION=0: chạy đến khi nhận TERM (deploy.sh dùng chế độ này).
set -uo pipefail
url=${1:?URL required}; output=${2:?CSV path required}; duration=${3:-60}
[[ "$duration" =~ ^[0-9]+$ ]] || exit 2
mkdir -p "$(dirname "$output")"
printf 'timestamp_utc,http_status,curl_exit,latency_seconds\n' > "$output"
trap 'exit 0' TERM INT
start=$SECONDS
while (( duration == 0 || SECONDS - start < duration )); do
  status=0; value=$(curl --silent --output /dev/null --max-time 3 --write-out '%{http_code},%{time_total}' "$url") || status=$?
  printf '%s,%s,%s,%s\n' "$(date -u +%FT%T.%3NZ)" "${value%%,*}" "$status" "${value##*,}" >> "$output"
  sleep 0.2
done
