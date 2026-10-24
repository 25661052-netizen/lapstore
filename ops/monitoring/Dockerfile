# One stage; build tools are installed and removed within the same RUN.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

SHELL ["/bin/sh", "-o", "pipefail", "-c"]

RUN set -eux; \
    test "$(apk --print-arch)" = x86_64; \
    apk upgrade --no-cache; \
    apk add --no-cache ca-certificates supervisor sqlite-libs tzdata; \
    addgroup -g 10001 monitor; \
    adduser -D -H -u 10001 -G monitor -h /var/lib/prometheus -s /sbin/nologin monitor; \
    addgroup -g 10002 grafana; \
    adduser -D -H -u 10002 -G grafana -h /var/lib/grafana -s /sbin/nologin grafana; \
    mkdir -p /var/lib/prometheus /var/lib/grafana/plugins /var/log/grafana \
      /etc/lapstore /etc/supervisor /etc/grafana/provisioning/datasources \
      /etc/grafana/provisioning/dashboards /etc/grafana/dashboards /run/supervisor; \
    chown -R monitor:monitor /var/lib/prometheus; \
    chown -R grafana:grafana /var/lib/grafana /var/log/grafana

ENV GF_PATHS_HOME=/opt/grafana \
    GF_PATHS_DATA=/var/lib/grafana \
    GF_PATHS_LOGS=/var/log/grafana \
    GF_PATHS_PLUGINS=/var/lib/grafana/plugins \
    GF_PATHS_PROVISIONING=/etc/grafana/provisioning \
    GF_LOG_MODE=console \
    GF_USERS_ALLOW_SIGN_UP=false \
    GF_ANALYTICS_REPORTING_ENABLED=false \
    GF_ANALYTICS_CHECK_FOR_UPDATES=false \
    GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false \
    GF_PLUGINS_PREINSTALL_DISABLED=true \
    GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=prometheus \
    PYTHONDONTWRITEBYTECODE=1

COPY source-lock.json build-monitoring.sh /usr/local/lib/lapstore-monitoring/

RUN --mount=type=cache,id=lapstore-monitoring-go-modules,target=/var/cache/lapstore-monitoring-go-modules,sharing=locked \
    --mount=type=cache,id=lapstore-monitoring-go-build,target=/var/cache/lapstore-monitoring-go-build,sharing=locked \
    --mount=type=cache,id=lapstore-monitoring-downloads,target=/var/cache/lapstore-monitoring-downloads,sharing=locked \
    set -eux; \
    apk add --no-cache --virtual .monitoring-build-deps \
      bash build-base curl git gzip tar sqlite-dev linux-headers pkgconf findutils coreutils; \
    bash /usr/local/lib/lapstore-monitoring/build-monitoring.sh; \
    apk del .monitoring-build-deps; \
    apk info -v > /usr/local/share/lapstore-monitoring-build/apk-packages.txt

COPY supervisord.conf /etc/supervisor/lapstore.conf
COPY prometheus.yml blackbox.yml /etc/lapstore/
COPY grafana-datasource.yml /etc/grafana/provisioning/datasources/lapstore.yml
COPY grafana-dashboard-provider.yml /etc/grafana/provisioning/dashboards/lapstore.yml
COPY dashboard.json /etc/grafana/dashboards/lapstore.json
COPY verify-runtime.py /usr/local/lib/lapstore-monitoring/verify-runtime.py

# Verify patched binaries, SQLite, plugin loading and a Grafana -> Prometheus query.
# All test processes/data live inside the builder; no host mounts or published ports.
RUN prometheus --version && promtool --version && cadvisor --version \
    && blackbox_exporter --version && /opt/grafana/bin/grafana --version \
    && supervisord --version \
    && promtool check config /etc/lapstore/prometheus.yml \
    && blackbox_exporter --config.file=/etc/lapstore/blackbox.yml --config.check \
    && python3 /usr/local/lib/lapstore-monitoring/verify-runtime.py

EXPOSE 3000 9090

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
  CMD python3 -c "import urllib.request; [urllib.request.urlopen('http://127.0.0.1:' + p, timeout=2).close() for p in ('3000/api/health', '9090/-/ready', '9115/metrics', '8080/healthz')]"

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/lapstore.conf"]
