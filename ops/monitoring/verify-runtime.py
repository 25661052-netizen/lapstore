"""Exercise the rebuilt Grafana and Prometheus inside the image builder."""

import base64
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def wait_http(url, timeout=120):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                return response.read()
        except (OSError, urllib.error.URLError) as error:
            last_error = error
            time.sleep(1)
    raise RuntimeError(f"HTTP readiness failed: {url}: {last_error}")


with tempfile.TemporaryDirectory(prefix="lapstore-monitoring-smoke-") as directory:
    root = Path(directory)
    root.chmod(0o755)
    processes = []
    logs = []

    def start(name, command, uid, environment):
        log_path = root / f"{name}.log"
        log_file = log_path.open("wb")
        logs.append((log_path, log_file))
        process = subprocess.Popen(
            command,
            cwd="/opt/grafana",
            env={**os.environ, **environment},
            stdout=log_file,
            stderr=subprocess.STDOUT,
            user=uid,
            group=uid,
            extra_groups=[],
            start_new_session=True,
        )
        processes.append(process)

    try:
        for name, uid in (("prometheus", 10001), ("grafana", 10002)):
            folder = root / name
            folder.mkdir()
            os.chown(folder, uid, uid)
        for name in ("plugins", "logs"):
            folder = root / "grafana" / name
            folder.mkdir()
            os.chown(folder, 10002, 10002)

        # Scrape only loopback; do not contact the live gateway during a build.
        config = root / "prometheus.yml"
        config.write_text(
            "global:\n  scrape_interval: 1s\nscrape_configs:\n"
            "  - job_name: self\n    static_configs:\n"
            "      - targets: ['127.0.0.1:9090']\n",
            encoding="utf-8",
        )
        config.chmod(0o644)
        start(
            "prometheus",
            ["/usr/local/bin/prometheus", f"--config.file={config}",
             f"--storage.tsdb.path={root / 'prometheus'}",
             "--web.listen-address=127.0.0.1:9090"],
            10001,
            {"HOME": str(root / "prometheus"), "GOMEMLIMIT": "192MiB"},
        )
        wait_http("http://127.0.0.1:9090/-/ready")
        if b"<html" not in wait_http("http://127.0.0.1:9090/query").lower():
            raise RuntimeError("Prometheus UI assets are unavailable")

        username = "lapstore-build-check"
        password = secrets.token_hex(24)
        start(
            "grafana",
            ["/opt/grafana/bin/grafana", "server", "--homepath=/opt/grafana"],
            10002,
            {"HOME": str(root / "grafana"),
             "GF_PATHS_DATA": str(root / "grafana"),
             "GF_PATHS_LOGS": str(root / "grafana" / "logs"),
             "GF_PATHS_PLUGINS": str(root / "grafana" / "plugins"),
             "GF_SERVER_HTTP_ADDR": "127.0.0.1", "GF_SERVER_HTTP_PORT": "3000",
             "GF_SECURITY_ADMIN_USER": username, "GF_SECURITY_ADMIN_PASSWORD": password,
             "GOMEMLIMIT": "384MiB"},
        )
        wait_http("http://127.0.0.1:3000/api/health")
        auth = "Basic " + base64.b64encode(f"{username}:{password}".encode()).decode()

        def grafana_json(path, payload=None):
            request = urllib.request.Request(
                "http://127.0.0.1:3000" + path,
                data=None if payload is None else json.dumps(payload).encode(),
                headers={"Authorization": auth, "Content-Type": "application/json"},
            )
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)

        def wait_grafana_json(path, ready):
            deadline = time.monotonic() + 60
            last_error = "not ready"
            while time.monotonic() < deadline:
                try:
                    result = grafana_json(path)
                    if ready(result):
                        return result
                except (OSError, urllib.error.URLError, ValueError) as error:
                    last_error = error
                time.sleep(1)
            raise RuntimeError(f"Grafana check failed: {path}: {last_error}")

        wait_grafana_json("/api/datasources/uid/lapstore-prometheus/health",
                          lambda result: result.get("status") == "OK")
        wait_grafana_json("/api/search?query=LapStore",
                          lambda result: any(item.get("uid") == "lapstore-monitoring"
                                             for item in result))

        now = int(time.time() * 1000)
        query = grafana_json("/api/ds/query", {
            "from": str(now - 60000), "to": str(now),
            "queries": [{"refId": "A", "expr": "1+1", "instant": True,
                         "range": False, "intervalMs": 1000, "maxDataPoints": 1,
                         "datasource": {"type": "prometheus", "uid": "lapstore-prometheus"}}],
        })
        result = query.get("results", {}).get("A", {})
        frames = result.get("frames") or []
        has_two = any(2 in column for frame in frames
                      for column in frame.get("data", {}).get("values", []))
        if result.get("error") or not has_two:
            raise RuntimeError("Grafana -> Prometheus query did not return 1+1=2")
        print("MONITORING_RUNTIME_SMOKE=OK", flush=True)
    except BaseException:
        for path, stream in logs:
            stream.flush()
            print(f"--- {path.name} (last lines) ---", flush=True)
            print("\n".join(path.read_text(errors="replace").splitlines()[-30:]), flush=True)
        raise
    finally:
        for process in reversed(processes):
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
        for _, stream in logs:
            stream.close()
