#!/usr/bin/env bash
set -euo pipefail

lock=/usr/local/lib/lapstore-monitoring/source-lock.json
provenance=/usr/local/share/lapstore-monitoring-build
work="$(mktemp -d /tmp/lapstore-monitoring-build.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT

read_lock() {
  python3 - "$lock" "$@" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    value = json.load(f)
for key in sys.argv[2:]:
    value = value[key]
if isinstance(value, list):
    print('\n'.join(value))
else:
    print(value)
PY
}

fetch() {
  local output="$1" url="$2" sha="$3"
  local cache=/var/cache/lapstore-monitoring-downloads
  local archive="$cache/$sha" partial="$cache/$sha.partial" attempt status
  mkdir -p "$cache"
  if [ -f "$partial" ] && printf '%s  %s\n' "$sha" "$partial" | sha256sum -c - >/dev/null 2>&1; then
    mv "$partial" "$archive"
  fi
  if [ -f "$archive" ]; then
    if printf '%s  %s\n' "$sha" "$archive" | sha256sum -c -; then
      printf 'DOWNLOAD_CACHE=HIT %s\n' "$url"
      cp "$archive" "$output"
      return 0
    fi
    rm -f -- "$archive"
  fi
  # Separate curl invocations resume from the current file size after a failure.
  # Keep partial/verified archives in a BuildKit cache, including after cancellation.
  for attempt in 1 2 3 4; do
    printf 'DOWNLOAD_ATTEMPT=%s/4 %s\n' "$attempt" "$url"
    if curl --fail --location --show-error --connect-timeout 20 \
      --max-time 0 --speed-limit 1024 --speed-time 120 \
      --continue-at - "$url" -o "$partial"; then
      if ! printf '%s  %s\n' "$sha" "$partial" | sha256sum -c -; then
        rm -f -- "$partial"
        return 1
      fi
      mv "$partial" "$archive"
      cp "$archive" "$output"
      printf 'DOWNLOAD_VERIFIED=OK %s\n' "$url"
      return 0
    else
      status=$?
      if [ "$status" -eq 33 ]; then
        echo 'Download server does not support resuming; next attempt starts from zero.' >&2
        rm -f -- "$partial"
      fi
    fi
    if [ "$attempt" -lt 4 ]; then
      printf 'Download interrupted (curl=%s); retrying with saved progress.\n' "$status" >&2
      sleep 2
    fi
  done
  return "$status"
}

extract_source() {
  local component="$1"
  fetch "$work/$component.tar.gz" \
    "$(read_lock sources "$component" url)" "$(read_lock sources "$component" sha256)"
  mkdir -p "$work/$component"
  tar --no-same-owner -xzf "$work/$component.tar.gz" --strip-components=1 -C "$work/$component"
}

apply_pins() {
  local component="$1"
  local -a pins
  mapfile -t pins < <(read_lock patches "$component")
  test "${#pins[@]}" -gt 0
  go get "${pins[@]}"
  go mod verify
}

record_binary() {
  local name="$1" binary="$2"
  go version -m "$binary" > "$provenance/$name.build-info.txt"
  sha256sum "$binary" > "$provenance/$name.sha256"
}

mkdir -p "$provenance" /opt/grafana /usr/local/bin
cp "$lock" "$provenance/source-lock.json"
echo 'BUILD_PHASE=1/8 download-go'
fetch "$work/go.tar.gz" "$(read_lock go url)" "$(read_lock go sha256)"
tar --no-same-owner -xzf "$work/go.tar.gz" -C "$work"
export PATH="$work/go/bin:$PATH"
export GOTOOLCHAIN=local GOPATH="$work/gopath" GOENV=off
export GOMODCACHE=/var/cache/lapstore-monitoring-go-modules
export GOCACHE=/var/cache/lapstore-monitoring-go-build
export GOMAXPROCS=1 GOMEMLIMIT=768MiB GOFLAGS=-p=1
test "$(go env GOVERSION)" = "go$(read_lock go version)"

# Reuse verified frontend assets; replace retained vulnerable Go binaries.
echo 'BUILD_PHASE=2/8 download-grafana-assets'
fetch "$work/grafana-assets.tar.gz" \
  "$(read_lock assets grafana url)" "$(read_lock assets grafana sha256)"
tar --no-same-owner -xzf "$work/grafana-assets.tar.gz" --strip-components=1 -C /opt/grafana
test -f /opt/grafana/data/plugins-bundled/prometheus/plugin.json
for plugin_dir in /opt/grafana/data/plugins-bundled/*; do
  if [ "${plugin_dir##*/}" != prometheus ]; then
    rm -rf -- "$plugin_dir"
  fi
done
# The upstream signature no longer describes this locally rebuilt plugin.
rm -f /opt/grafana/data/plugins-bundled/prometheus/MANIFEST.txt
find /opt/grafana -type f -name '*.map' -delete

echo 'BUILD_PHASE=3/8 download-source-archives'
for component in prometheus cadvisor grafana prometheus_plugin; do
  extract_source "$component"
done

(
  echo 'BUILD_PHASE=4/8 compile-prometheus-and-promtool'
  cd "$work/prometheus"
  apply_pins prometheus
  fetch "$work/prometheus-ui.tar.gz" \
    "$(read_lock assets prometheus_ui url)" "$(read_lock assets prometheus_ui sha256)"
  tar --no-same-owner -xzf "$work/prometheus-ui.tar.gz" -C web/ui
  test -s web/ui/static/mantine-ui/index.html
  test -s web/ui/static/react-app/index.html
  bash scripts/compress_assets.sh
  for binary in prometheus promtool; do
    CGO_ENABLED=0 go build -buildvcs=false -trimpath -tags builtinassets \
      -ldflags "-s -w -X github.com/prometheus/common/version.Version=$(read_lock sources prometheus version)-lapstore.security1 -X github.com/prometheus/common/version.Revision=$(read_lock sources prometheus commit) -X github.com/prometheus/common/version.BuildUser=lapstore" \
      -o "/usr/local/bin/$binary" "./cmd/$binary"
    record_binary "$binary" "/usr/local/bin/$binary"
  done
)

(
  echo 'BUILD_PHASE=5/8 compile-cadvisor'
  cd "$work/cadvisor/cmd"
  apply_pins cadvisor
  test -s internal/pages/static/assets.go
  CGO_ENABLED=0 go build -buildvcs=false -trimpath -tags netgo \
    -ldflags "-s -w -X github.com/google/cadvisor/lib/version.Version=$(read_lock sources cadvisor version)-lapstore.security1 -X github.com/google/cadvisor/lib/version.Revision=$(read_lock sources cadvisor commit) -X github.com/google/cadvisor/lib/version.BuildUser=lapstore -X github.com/google/cadvisor/lib/version.GoVersion=$(read_lock go version)" \
    -o /usr/local/bin/cadvisor .
  record_binary cadvisor /usr/local/bin/cadvisor
)

(
  echo 'BUILD_PHASE=6/8 compile-grafana'
  cd "$work/grafana"
  go work edit -go="$(read_lock go version)"
  apply_pins grafana
  test -s pkg/server/wire_gen.go
  CGO_ENABLED=1 go build -buildvcs=false -trimpath -tags 'oss libsqlite3' \
    -ldflags "-s -w -X main.version=$(read_lock sources grafana version)-lapstore.security1 -X main.commit=$(read_lock sources grafana commit) -X main.buildBranch=lapstore-monitoring" \
    -o /opt/grafana/bin/grafana ./pkg/cmd/grafana
  record_binary grafana /opt/grafana/bin/grafana
)

(
  echo 'BUILD_PHASE=7/8 compile-prometheus-plugin'
  cd "$work/prometheus_plugin"
  go mod verify
  CGO_ENABLED=0 go build -buildvcs=false -trimpath -ldflags '-s -w' \
    -o /opt/grafana/data/plugins-bundled/prometheus/gpx_grafana-prometheus-datasource_linux_amd64 ./pkg
  record_binary prometheus-plugin \
    /opt/grafana/data/plugins-bundled/prometheus/gpx_grafana-prometheus-datasource_linux_amd64
)

# No HIGH/CRITICAL was reported in this pinned Blackbox release.
echo 'BUILD_PHASE=8/8 install-blackbox-and-record-build-info'
fetch "$work/blackbox.tar.gz" "$(read_lock assets blackbox url)" "$(read_lock assets blackbox sha256)"
mkdir -p "$work/blackbox"
tar --no-same-owner -xzf "$work/blackbox.tar.gz" --strip-components=1 -C "$work/blackbox"
install -m 0755 "$work/blackbox/blackbox_exporter" /usr/local/bin/blackbox_exporter
record_binary blackbox /usr/local/bin/blackbox_exporter

for component in prometheus cadvisor grafana prometheus_plugin blackbox go; do
  mkdir -p "/usr/local/share/licenses/$component"
  for license in "$work/$component"/LICENSE* "$work/$component"/NOTICE*; do
    if [ -f "$license" ]; then
      cp "$license" "/usr/local/share/licenses/$component/"
    fi
  done
done
echo 'MONITORING_BINARIES_REBUILT=OK'
