# LapStore monitoring

Một container chạy Supervisor, cAdvisor, Blackbox Exporter, Prometheus và
Grafana. Compose dùng project `lapstore-monitoring`, độc lập với ứng dụng live.
Phần backup database tiếp tục triển khai sau monitoring.

## Bản sửa nguồn security.1

Image Debian đầu tiên bị Trivy chặn: 157 HIGH + 1 CRITICAL trong báo cáo người
dùng gửi. Bản sửa này vẫn dùng một Dockerfile single-stage và một container,
chuyển sang Alpine 3.24.3 khóa digest và build lại các binary cần thiết.
Người vận hành đã báo build OK và Trivy PASS cho bản sửa. Trợ lý chưa đọc
log/JSON cuối hoặc xác minh image ID trên server; bằng chứng thực tế lưu trong
`reports`. Khả năng thu thập metrics cần kiểm tra sau khi khởi chạy.

| File | Vai trò |
| --- | --- |
| `Dockerfile` | Cài runtime, gọi build và kiểm tra trước khi tạo image |
| `source-lock.json` | Khóa commit, SHA256 nguồn/assets, Go 1.27.3 và dependency vá lỗi |
| `build-monitoring.sh` | Build Prometheus/promtool, cAdvisor, Grafana và plugin Prometheus |
| `verify-runtime.py` | Kiểm tra SQLite, dashboard, plugin và truy vấn Grafana → Prometheus |

Các source archive được khóa theo commit chính thức và SHA256. Phiên bản
kin-openapi, gRPC, x/net, x/text, x/crypto và compress được chọn theo báo cáo;
Go mới dùng để build lại stdlib. Blackbox giữ bản đã khóa không bị báo
HIGH/CRITICAL trong lần quét trước. Vẫn phải quét toàn bộ image mới.

Grafana giữ datasource Prometheus và các assets giao diện; các datasource
Elasticsearch, MySQL, Tempo... không dùng trong dashboard LapStore được loại
khỏi `data/plugins-bundled`. Các file debug sourcemap `.map` cũng được loại.
Plugin Prometheus được build lại nên không còn dùng chữ ký của binary upstream:
chỉ ID `prometheus` được cho phép nạp dưới dạng unsigned. Không bật chế độ
development hoặc cho phép mọi plugin unsigned. Bài kiểm tra build xác minh
plugin thực sự nạp và thực hiện được truy vấn.

Go/compiler/curl và source tạm chỉ phục vụ build, được loại khỏi filesystem
cuối trong cùng RUN. Healthcheck dùng Python đã có cho Supervisor, không cần
curl ở runtime. Các build-info, hash binary và danh sách package cuối nằm trong
`/usr/local/share/lapstore-monitoring-build` bên trong image.

Go build dùng `GOMAXPROCS=1`, `-p=1`, `GOMEMLIMIT=768MiB` để giảm độ song song;
đây không phải giới hạn RAM cứng cho toàn bộ build. Build từ source lâu hơn
bản tải binary; BuildKit giữ ba cache có ID `lapstore-monitoring-go-modules`,
`lapstore-monitoring-go-build` và `lapstore-monitoring-downloads` để tái sử dụng.
Đây là cache build, không phải named volume dữ liệu runtime. Không dùng lệnh
prune toàn host.

Phần tải không còn giới hạn tổng 600 giây. Nếu đường truyền dưới 1 KiB/s trong
120 giây, curl dừng lượt tải và script thử lại, tối đa bốn lượt. Mỗi lượt mới
tiếp tục file dở bằng `--continue-at -` nếu máy chủ tải hỗ trợ HTTP Range;
nếu không hỗ trợ thì tải lại từ đầu. SHA256 vẫn bắt buộc trước khi giải nén.
File tải dở và archive đã xác minh được giữ trong cache BuildKit riêng để dùng
lại sau lỗi/hủy build, miễn cache chưa bị Docker dọn. Lần đầu áp dụng bản sửa
không lấy lại được file dở từ RUN cũ vốn chưa có cache tải.

Log `BUILD_PHASE=1/8` đến `8/8` chỉ thứ tự công việc, không phải phần trăm
thời gian. `Time Total/Left` của curl chỉ ước tính một lượt tải, không phải ETA
toàn bộ build. Chỉ `MONITORING_BUILD=OK` từ lệnh bên dưới xác nhận build xong.

Để thử bản sửa trên server, chuyển đúng bốn file trong bảng vào thư mục
`$HOME/lapstore/ops/monitoring` đã có. Giữ `.env` đã thiết lập trên server.
Sau đó chạy lại lệnh build ở bước 6.1 bên dưới. Không cần tạo thư mục server
mới; các thư mục tải/build tạm nằm bên trong filesystem của Docker builder.

Build mới cần đi qua `MONITORING_BINARIES_REBUILT=OK`,
`MONITORING_RUNTIME_SMOKE=OK` rồi `MONITORING_BUILD=OK`. Smoke test dùng dữ liệu
SQLite tạm, tài khoản test ngẫu nhiên và UID riêng bên trong builder; Prometheus
chỉ scrape loopback, không liên hệ gateway live. Nó kiểm tra trang web Prometheus,
datasource health, dashboard được provision và truy vấn `1+1=2` qua Grafana.
Build lỗi ở bất kỳ bước nào thì dừng để xử lý. Khi build đạt, quét lại theo
bước 6.3; không coi smoke test là thay thế security gate.

## Bước 5/8: chuẩn bị Compose trên server

Chuyển các file trong thư mục này vào `$HOME/lapstore/ops/monitoring` bằng panel
đang dùng. Giữ cả file ẩn `.dockerignore`; `.env.example` là mẫu không có mật khẩu.
Không thay `.env` của app, runtime hoặc registry.

Trên terminal SSH của server Ubuntu, chạy:

```bash
cd "$HOME/lapstore/ops/monitoring"

if [ ! -f .env ]; then
  (
    umask 077
    printf 'MONITORING_IMAGE=lapstore-monitoring:1.0.0\n'
    printf 'GRAFANA_PASSWORD=%s\n' "$(openssl rand -hex 24)"
  ) > .env
fi
chmod 600 .env

unset GRAFANA_PASSWORD MONITORING_IMAGE
docker compose -p lapstore-monitoring --env-file .env -f compose.yml config --quiet \
  && echo 'MONITORING_COMPOSE=OK'
```

Lệnh `config --quiet` kiểm tra mô hình Compose và các biến cần thiết, không
build image, tạo volume hoặc chạy container. Nếu `.env` đã tồn tại, lệnh trên
giữ nguyên nội dung; Compose sẽ báo lỗi nếu thiếu mật khẩu.
Chưa dùng `up` ở bước này. Mật khẩu Grafana nằm trong `.env` vừa tạo; dùng tài
khoản `admin` ở bước đăng nhập sau. Biến này khởi tạo admin khi dữ liệu Grafana
còn mới; đổi `.env` không tự đổi mật khẩu admin đã lưu trong volume.

## Những gì Compose cấu hình

| Thành phần | Giá trị |
| --- | --- |
| Image local dự kiến | `lapstore-monitoring:1.0.0` |
| Build context | Chính thư mục `ops/monitoring` |
| Grafana | `127.0.0.1:5202` → container `3000` |
| Prometheus | `127.0.0.1:5203` → container `9090` |
| Network có sẵn | `lapstore-live_default` |
| Volume Prometheus | `lapstore-monitoring_prometheus_data` |
| Volume Grafana | `lapstore-monitoring_grafana_data` |
| CPU tối đa | Tương đương 1 CPU |
| RAM tối đa | 1536 MiB |
| RAM + swap tối đa | 2048 MiB, nếu host hỗ trợ giới hạn swap |
| Thời gian chờ dừng | 90 giây |

Hai named volume do Docker quản lý, thuộc project monitoring. Chúng không dùng
chung volume MySQL. Root filesystem của container ở chế độ read-only; dữ liệu
ghi vào hai volume, các đường dẫn tạm và log Docker đã giới hạn xoay vòng.

Truy cập Grafana/Prometheus trên máy cá nhân sẽ dùng SSH tunnel ở bước sau.
Không đổi Cloudflare Tunnel của website trong bước này.

## Phạm vi quan sát host: cần thống nhất trước khi chạy

cAdvisor cần metadata host để liên kết số liệu tài nguyên với container Docker.
Compose đề xuất các bind mount sau:

| Đường dẫn host | Đường dẫn container | Mục đích |
| --- | --- | --- |
| `/` | `/rootfs` | Thông tin filesystem và tiến trình host |
| `/sys` | `/sys` | Cgroup và thông tin kernel/tài nguyên |
| `/var/lib/docker` | `/var/lib/docker` | Metadata lưu trữ Docker theo cấu hình host đã cung cấp |
| `/var/run/docker.sock` | `/var/run/docker.sock` | Tra cứu container, tên và nhãn qua Docker API |

Tất cả bind mount khai báo `read_only: true` và `create_host_path: false`.
Chúng không tạo thư mục host khi đường dẫn nguồn thiếu. Tuy nhiên,
`/rootfs` cho phép nhìn thấy nội dung ngoài LapStore; cAdvisor có thể khám phá
cả container khác. Bộ lọc trong Prometheus chỉ quyết định metrics nào được lưu,
không giới hạn phạm vi cAdvisor đọc host.

Socket Docker là kênh API: mount socket read-only **không** biến API thành
read-only. Compose này không có proxy giới hạn API. Quyền quan sát host và
quyền truy cập socket cần được người dùng chấp nhận riêng vì trước đó đã giới
hạn thao tác trong thư mục LapStore. Chưa có container nào được chạy bằng file
này. Không thực hiện thao tác sửa/xóa các tài nguyên ngoài project.

Cấu hình dùng cgroup namespace của host, không bật `privileged`, không chia sẻ
PID namespace và không sửa cấu hình Docker daemon. Khả năng thu thập đủ metrics
CPU/RAM/network/disk sẽ được kiểm chứng ở bước 7; không coi Compose hợp lệ là
bằng chứng metrics đã hoạt động. Nếu thiếu quyền, xem log trước khi thay đổi.

## Bước 6.1/8: build image monitoring

Sau khi người vận hành đã đồng ý phạm vi quan sát host, build image trước.
Lệnh này chỉ build service monitoring; chưa chạy service hoặc mount host vào
container monitoring. Log dùng thư mục reports đã có trong project.

Chạy trên terminal SSH Ubuntu:

```bash
cd "$HOME/lapstore/ops/monitoring"
set -o pipefail
unset GRAFANA_PASSWORD MONITORING_IMAGE

MONITORING_BUILD_LOG="$HOME/lapstore/reports/monitoring-build-$(date -u +%Y%m%dT%H%M%SZ).log"

if docker compose --progress plain -p lapstore-monitoring \
  --env-file .env -f compose.yml build --pull monitoring \
  2>&1 | tee "$MONITORING_BUILD_LOG"; then
  echo 'MONITORING_BUILD=OK'
else
  echo 'MONITORING_BUILD=FAIL'
fi
```

Build tải source/assets/Go theo `source-lock.json`, xác minh SHA256, áp dụng
dependency pins và kiểm tra binary/cấu hình/runtime. Cần có dòng
`MONITORING_BUILD=OK` trước khi tiếp tục.
Nếu FAIL, giữ log để chẩn đoán; chưa chạy container.

Sau build là kiểm tra cấu hình bằng binary trong image, quét Trivy rồi mới
khởi chạy. Build thành công chưa chứng minh runtime hoặc security gate đã đạt.

## Bước 6.2/8: kiểm tra cấu hình trong image vừa build

Sau khi build báo OK, kiểm tra cấu hình Prometheus và Blackbox bằng chính
binary đã cài trong image. Container kiểm tra chạy tạm thời, không có network,
không mount host hoặc volume và được xóa sau khi kết thúc. Không dùng
`docker compose run` ở bước này để tránh kế thừa các mount quan sát host.
Supervisor/Grafana và khả năng thu thập metrics sẽ được kiểm chứng khi chạy
stack sau security gate.

```bash
cd "$HOME/lapstore/ops/monitoring"
set -o pipefail

MONITORING_IMAGE_ID="$(docker image inspect lapstore-monitoring:1.0.0 --format '{{.Id}}')"

docker run --rm --network none --read-only --user 10001:10001 \
  --entrypoint /bin/sh "$MONITORING_IMAGE_ID" -ec '
    promtool check config /etc/lapstore/prometheus.yml
    blackbox_exporter --config.file=/etc/lapstore/blackbox.yml --config.check
    echo "MONITORING_CONFIG=OK"
  ' 2>&1 | tee "$HOME/lapstore/reports/monitoring-config-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Cần thấy `MONITORING_CONFIG=OK`. Nếu có lỗi, chưa tiếp tục quét/khởi chạy;
dùng log vừa lưu để chẩn đoán. Bước tiếp theo là xuất đúng image ID để quét
Trivy và chặn nếu có phát hiện HIGH/CRITICAL; chưa có scan PASS được xác nhận.

## Bước 6.3/8: quét Trivy trước khi khởi chạy

Sau khi cấu hình báo OK, xuất đúng image/config ID local thành archive để quét.
Scanner chỉ được mount file archive đọc-only và file JSON kết quả; không có
Docker socket, .env hoặc thư mục host khác. Các file báo cáo dùng reports đã
có, không tạo thêm thư mục server. Scanner có giới hạn CPU/RAM riêng.

```bash
(
  set -euo pipefail
  umask 077
  cd "$HOME/lapstore/ops/monitoring"

  MONITORING_IMAGE_ID="$(docker image inspect lapstore-monitoring:1.0.0 --format '{{.Id}}')"
  MONITORING_SCAN="$HOME/lapstore/reports/monitoring-scan-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  TRIVY_IMAGE='aquasec/trivy@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222'

  printf '%s\n' "$MONITORING_IMAGE_ID" > "$MONITORING_SCAN.image-id.txt"
  docker image save --output "$MONITORING_SCAN.tar" "$MONITORING_IMAGE_ID"
  : > "$MONITORING_SCAN.json"

  MONITORING_SCAN_EXIT=0
  docker run --rm --cpus 1 --memory 1536m --memory-swap 2g \
    --user "$(id -u):$(id -g)" -e GOMEMLIMIT=1GiB \
    --mount "type=bind,src=$MONITORING_SCAN.tar,dst=/image.tar,readonly" \
    --mount "type=bind,src=$MONITORING_SCAN.json,dst=/report.json" \
    "$TRIVY_IMAGE" image --cache-dir /tmp/trivy-cache \
    --input /image.tar --scanners vuln,secret --severity HIGH,CRITICAL \
    --exit-code 1 --timeout 15m --no-progress \
    --format json --output /report.json \
    2>&1 | tee "$MONITORING_SCAN.log" || MONITORING_SCAN_EXIT=$?

  printf '%s\n' "$MONITORING_SCAN_EXIT" > "$MONITORING_SCAN.exit-code.txt"
  rm -- "$MONITORING_SCAN.tar"
  printf 'REPORT=%s\n' "$MONITORING_SCAN.json"
  if [ "$MONITORING_SCAN_EXIT" -eq 0 ]; then
    echo 'MONITORING_SCAN=PASS'
  else
    echo 'MONITORING_SCAN=FAIL'
  fi
)
```

Archive `.tar` là file tạm do khối lệnh vừa tạo và được xóa sau lần quét;
image local cùng JSON/log/image ID/exit code vẫn được giữ. Nếu lệnh xuất archive
bị gián đoạn, giữ nguyên file để xử lý có mục tiêu, không dọn Docker toàn host.
Cache scanner nằm bên trong container tạm, tự mất khi container được xóa.

Ngưỡng chặn là HIGH/CRITICAL, không bỏ qua lỗ hổng chưa có bản sửa. PASS chỉ khi
scanner kết thúc thành công với mã 0; lỗi tải DB, OOM, hết thời gian hoặc lỗi
phân tích cũng chặn bước chạy. Báo cáo JSON ghi kết quả của image đã xuất,
không phải của image khác đang chạy trên server.

Nếu FAIL, giữ báo cáo và log để phân biệt lỗi scanner với các phát hiện. Chưa
dùng `up` hoặc hạ ngưỡng bỏ qua kết quả. Nếu PASS, bước tiếp theo sẽ dùng đúng
image ID đã ghi để khởi chạy riêng Compose project lapstore-monitoring.

## Bước 6.4/8: khởi chạy đúng image đã quét

Sau Trivy PASS và khi quyền quan sát host đã được chấp nhận, chạy khối lệnh
dưới trên server. Khối lệnh chọn báo cáo mới nhất theo tên timestamp do bước
6.3 tạo, yêu cầu exit code 0 và dùng image ID tương ứng. Không build hoặc pull.
Compose tạo một container monitoring và hai named volume riêng, nối vào network
live đã có; không khởi động lại container ứng dụng hoặc MySQL.

```bash
(
  set -euo pipefail
  cd "$HOME/lapstore/ops/monitoring"
  unset GRAFANA_PASSWORD MONITORING_IMAGE

  shopt -s nullglob
  SCAN_RESULTS=( "$HOME"/lapstore/reports/monitoring-scan-*.exit-code.txt )
  if [ "${#SCAN_RESULTS[@]}" -eq 0 ]; then
    echo 'Khong tim thay bao cao quet.'; exit 1
  fi
  SCAN_RESULT="${SCAN_RESULTS[-1]}"
  if [ "$(cat "$SCAN_RESULT")" != 0 ]; then
    echo 'Lan quet moi nhat chua PASS.'; exit 1
  fi

  export MONITORING_IMAGE="$(cat "${SCAN_RESULT%.exit-code.txt}.image-id.txt")"
  [[ "$MONITORING_IMAGE" =~ ^sha256:[a-f0-9]{64}$ ]]
  docker image inspect "$MONITORING_IMAGE" >/dev/null

  docker compose -p lapstore-monitoring --env-file .env -f compose.yml \
    up -d --no-build --pull never --wait --wait-timeout 180 monitoring

  docker compose -p lapstore-monitoring --env-file .env -f compose.yml ps
  MONITORING_CID="$(docker compose -p lapstore-monitoring --env-file .env -f compose.yml ps -q monitoring)"
  [ "$(docker inspect --format '{{.Image}}' "$MONITORING_CID")" = "$MONITORING_IMAGE" ]
  echo 'SCANNED_IMAGE_RUNNING=OK'

  docker compose -p lapstore-monitoring --env-file .env -f compose.yml \
    exec -T monitoring supervisorctl -c /etc/supervisor/lapstore.conf status

  curl -fsS --max-time 10 -w '\n' http://127.0.0.1:5202/api/health
  curl -fsS --max-time 10 -w '\n' http://127.0.0.1:5203/-/ready
)
```

Kết quả cần có container healthy, SCANNED_IMAGE_RUNNING=OK, bốn chương trình
cadvisor/blackbox/prometheus/grafana RUNNING, Grafana database ok và Prometheus
ready. Đây là kiểm tra khởi động; chưa chứng minh các probe và metrics container
đã đủ dữ liệu. Bước 7 kiểm tra targets, truy vấn metrics và mở dashboard.

Nếu up báo lỗi hoặc hết thời gian chờ, đọc log riêng monitoring trước khi sửa:

```bash
cd "$HOME/lapstore/ops/monitoring"
docker compose -p lapstore-monitoring --env-file .env -f compose.yml \
  logs --tail 80 monitoring
```

## Bước 7/8: mở dashboard và xác minh dữ liệu

Người vận hành đã báo khởi chạy và kiểm tra ở bước 6.4 đều PASS. Bước này
kiểm tra targets và dữ liệu thực tế; chưa coi container healthy là đủ bằng chứng.
Nếu mới khởi chạy, đợi khoảng hai phút để có mẫu cho các truy vấn rate.

Trên máy Windows cá nhân, mở một cửa sổ PowerShell mới, chạy:

```powershell
$LapStoreSshTarget = Read-Host 'Nhap dia chi SSH dang dung (user@host)'
ssh -N -o ExitOnForwardFailure=yes `
  -L 127.0.0.1:5202:127.0.0.1:5202 `
  -L 127.0.0.1:5203:127.0.0.1:5203 $LapStoreSshTarget
```

Giá trị SSH nhập tương tác không được ghi vào note hoặc source. Giữ cửa sổ
này mở trong khi xem dashboard; ssh -N không mở shell nên không hiện dấu nhắc
sau khi kết nối là bình thường. Nếu báo port đang dùng, gửi lỗi để đổi cổng
local, không dừng tiến trình khác trên máy. Không cần thay cổng/domain website.

Trên trình duyệt máy cá nhân, mở:

- Grafana: `http://127.0.0.1:5202`, đăng nhập admin và mật khẩu Grafana đã đặt.
- Dashboard có sẵn: `http://127.0.0.1:5202/d/lapstore-monitoring`.
- Prometheus targets: `http://127.0.0.1:5203/targets`.

Prometheus có năm targets: prometheus, cadvisor, blackbox và hai endpoint của
job lapstore (internal/public). Tất cả cần UP. Scrape UP chỉ chứng minh lấy
được kết quả từ exporter; kết quả probe website còn phải kiểm tra riêng.

Trên dashboard chọn Last 15 minutes và kiểm tra:

- Website khỏe mạnh: internal và public đều UP; HTTP status đều 200.
- Có thời gian phản hồi cho hai route.
- CPU và RAM có series tên container LapStore, đặc biệt các container live.
- Quan sát cả network/disk; nếu ô nào No data, ghi tên ô để chẩn đoán. Không
  diễn giải No data thành bằng 0. CPU bằng 0 khi ít hoạt động vẫn có thể hợp lệ.

Người vận hành đã xác nhận năm targets đều UP và các phần trên dashboard có
metrics. Đây là xác nhận người dùng, trợ lý chưa trực tiếp xem screenshot/API
trên server. Bước 8 lưu bằng chứng và kiểm tra persistence của riêng monitoring.
Backup MySQL vẫn để sau khi hoàn thành monitoring như thứ tự đã thống nhất.

## Bước 8/8: persistence và bằng chứng

Trước bài thử, chụp dashboard đang có metrics và trang năm targets UP. Trong
Grafana vào Dashboards → New → New folder, tạo `LapStore Persistence Test`.
Đây là thư mục phân loại trong Grafana, không phải thư mục filesystem Linux;
nó là dấu hiệu dữ liệu tự tạo trong database Grafana, khác dashboard provision
từ image có thể tự xuất hiện lại dù volume đã mất.

Chạy trên terminal SSH server. Khối lệnh chỉ tạo lại service monitoring bằng
đúng image đang chạy, giữ hai named volume. Monitoring gián đoạn ngắn; các
container website/MySQL không bị khởi động lại. File bằng chứng nằm trong
reports đã có, không tạo thêm thư mục host.

```bash
(
  set -euo pipefail
  umask 077
  cd "$HOME/lapstore/ops/monitoring"
  unset GRAFANA_PASSWORD MONITORING_IMAGE

  CHECK="$HOME/lapstore/reports/monitoring-persistence-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  CID_BEFORE="$(docker compose -p lapstore-monitoring --env-file .env -f compose.yml ps -q monitoring)"
  export MONITORING_IMAGE="$(docker inspect --format '{{.Image}}' "$CID_BEFORE")"
  printf '%s\n' "$MONITORING_IMAGE" > "$CHECK.image-id.txt"
  HISTORY_TIME="$(( $(date +%s) - 30 ))"
  printf '%s\n' "$HISTORY_TIME" > "$CHECK.query-time.txt"

  history_query() {
    curl -fsS --max-time 15 -G http://127.0.0.1:5203/api/v1/query \
      --data-urlencode 'query=up{job="prometheus"}' \
      --data-urlencode "time=$HISTORY_TIME"
  }
  history_query > "$CHECK.before.json"

  docker compose -p lapstore-monitoring --env-file .env -f compose.yml \
    up -d --no-deps --force-recreate --no-build --pull never \
    --wait --wait-timeout 180 monitoring

  CID_AFTER="$(docker compose -p lapstore-monitoring --env-file .env -f compose.yml ps -q monitoring)"
  [ "$CID_BEFORE" != "$CID_AFTER" ]
  [ "$(docker inspect --format '{{.Image}}' "$CID_AFTER")" = "$MONITORING_IMAGE" ]
  history_query > "$CHECK.after.json"

  python3 - "$CHECK.before.json" "$CHECK.after.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    before = json.load(f)
with open(sys.argv[2]) as f:
    after = json.load(f)
assert before['status'] == after['status'] == 'success'
assert len(before['data']['result']) == 1, 'No historical sample before recreation'
assert before['data'] == after['data'], 'Historical sample changed or missing'
print('PROMETHEUS_PERSISTENCE=PASS')
PY

  curl -fsS --max-time 15 http://127.0.0.1:5203/api/v1/targets > "$CHECK.targets.json"
  printf '%s\n' "$CID_BEFORE" "$CID_AFTER" > "$CHECK.container-ids.txt"
  echo "EVIDENCE=$CHECK"
)
```

Truy vấn hai lần cùng một thời điểm trước khi tạo lại container; kết quả có
dữ liệu và giống nhau chứng minh lịch sử Prometheus còn được đọc từ volume.
Sau đó refresh Grafana, kiểm tra `LapStore Persistence Test` vẫn tồn tại và
chụp bằng chứng; đây là phần kiểm tra persistence Grafana thủ công. Kiểm tra
lại năm targets UP và dashboard tiếp tục nhận metrics. Không dùng down -v.

Người vận hành đã báo các kiểm tra vẫn PASS, đủ metrics và
`PROMETHEUS_PERSISTENCE=PASS`. File JSON/log và screenshot thực tế cần giữ
trong hồ sơ bàn giao; xem [VALIDATION.md](VALIDATION.md) về phạm vi xác nhận.
Còn commit/push thay đổi monitoring và tài liệu lên branch hiện tại; không
đưa .env, note private hoặc file chứa secret lên Git. Backup MySQL là phần kế tiếp.

## Trạng thái và bước kế tiếp

Đã chuẩn bị Dockerfile, cấu hình dịch vụ, dashboard và Compose. Quy trình
triển khai là build → kiểm tra cấu hình bằng binary → Trivy scan → chạy
container, sau khi thống nhất quyền quan sát host. Kết quả thực hiện từng
đợt được lưu riêng trong reports; README mô tả quy trình, không thay thế bằng
chứng thực tế.

Tài liệu tham chiếu:

- [Chạy cAdvisor trong Docker](https://github.com/google/cadvisor/blob/v0.60.6/docs/running.md)
- [Compose services và bind mounts](https://docs.docker.com/reference/compose-file/services/)
- [Cấu hình Grafana](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/)
- [Promtool check config](https://prometheus.io/docs/prometheus/latest/command-line/promtool/)
- [Blackbox config.check trong phiên bản sử dụng](https://github.com/prometheus/blackbox_exporter/blob/v0.29.1/main.go)
- [Trivy: quét image archive](https://trivy.dev/docs/latest/target/container_image/)
- [Trivy: các cờ quét image](https://trivy.dev/docs/latest/references/configuration/cli/trivy_image/)
