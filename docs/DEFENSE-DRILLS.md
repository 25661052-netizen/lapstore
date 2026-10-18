# Sáu Defense Drill

Dùng repository/server lab riêng. Ghi thời điểm, commit, run ID, expected result,
actual result, ảnh/log/report cho từng tình huống. Chỉ đánh dấu PASS sau khi thực
hiện và đối chiếu. Các nhánh cố tình lỗi không merge vào main.

## 1. Broken build

Tạo nhánh `drill/broken-build`. Tạm thêm `RUN exit 1` vào Dockerfile, commit/push,
mở PR vào main. Kỳ vọng: unit test có thể đạt, Docker build đỏ, Trivy image/push/deploy
không chạy. Website runtime không đổi. Tải docker-build.log và chụp kết quả job.
Đóng PR, xóa nhánh thử khi đã lưu bằng chứng.

## 2. Vulnerable image

Tạo nhánh `drill/vulnerable-image`. Cài một dependency production cũ có lỗ hổng đã
biết, ví dụ `npm install --save-exact lodash@4.17.15`, commit cả package.json và lock.
Dependency này chỉ dùng trong nhánh drill, không thêm vào baseline.
Mở PR. Kỳ vọng Trivy image phát hiện HIGH/CRITICAL, exit 1, không push/deploy.
Đối chiếu package/version/severity trong trivy.json. Nếu database Trivy tại thời
điểm chạy không đưa ra HIGH/CRITICAL, case chưa đạt: chọn fixture được xác nhận
bằng báo cáo hiện tại. Không tắt scanner hoặc hạ ngưỡng chỉ để chứng minh case.

## 3. Registry unavailable

Điều kiện: runtime đang có bản khỏe mạnh; ENABLE_DELIVERY=true.
Trên server, dừng riêng registry:

```bash
docker compose -p lapstore-registry -f registry/compose.yml stop registry
```

Push một thay đổi hợp lệ lên main. CI đạt nhưng login/push ở Delivery phải lỗi.
Ứng dụng http://localhost:8080 vẫn hoạt động; /health vẫn có release cũ.
Khởi động lại registry sau thử:

```bash
docker compose -p lapstore-registry -f registry/compose.yml start registry
```

Lưu log Delivery và HTTP trước/trong/sau. Muốn thử lỗi pull trực tiếp, chạy deploy.sh
với digest mới chưa có local khi registry tắt; script phải thất bại trước chuyển traffic.

## 4. Failed deployment và tự phục hồi

CI bình thường sẽ chặn image có /health lỗi trước khi đến CD. Để kiểm tra cơ chế
CD độc lập, tạo **image lỗi có chủ ý trong lab** từ bản hiện tại, không qua release
pipeline. Không sửa Dockerfile chính. Chạy Bash trên server từ thư mục source:

```bash
DEPLOY_DIR=/home/you/lapstore-runtime
REGISTRY_IMAGE=registry.lapstore.internal:5443/lapstore/app
CURRENT=$(sed -n '2p' "$DEPLOY_DIR/state")
docker login registry.lapstore.internal:5443
printf 'FROM %s\nCMD ["node", "-e", "process.exit(1)"]\n' "$CURRENT" \
  | docker build -f - -t "$REGISTRY_IMAGE:drill-failed" .
docker push "$REGISTRY_IMAGE:drill-failed"
BAD=$(docker image inspect "$REGISTRY_IMAGE:drill-failed" --format '{{range .RepoDigests}}{{println .}}{{end}}' \
  | awk -v p="$REGISTRY_IMAGE@" 'index($0,p)==1 {print; exit}')
bash cd/deploy.sh "$BAD" "$DEPLOY_DIR"
```

Đổi DEPLOY_DIR theo máy. Kỳ vọng lệnh cuối trả nonzero, slot mới không khỏe, gateway
vẫn phục vụ release CURRENT, state không commit image lỗi. Báo cáo có lỗi và kết
quả giữ/khôi phục bản cũ. Xác nhận bằng `curl -fsS http://127.0.0.1:8080/health`.
Đây là cố tình bypass CI trong lab để thử failure handling, không phải luồng release.
Tag drill-failed không dùng làm release. Không xóa image current/previous để dọn drill.

## 5. Rollback production lab: v2 → v1

Deploy v1 thành công. Sửa một dòng giao diện, tăng version, commit và deploy v2
thành công. Hai bản phải có digest khác nhau. Ghi current/previous từ runtime state.

Actions → Run workflow → main → rollback. Hoặc trên server:

```bash
bash cd/rollback.sh /home/you/lapstore-runtime
curl -fsS http://127.0.0.1:8080/health
```

Kỳ vọng release trả về digest v1, giao diện đã đổi về v1, sản phẩm tạo khi v2 đang
chạy vẫn còn. Rollback image không rollback dữ liệu. Có thể tắt registry trước khi
rollback để chứng minh image cũ còn local; bật lại registry sau thử.

## 6. Đo downtime khi nâng cấp

Khi v1 đang khỏe, deploy một digest v2 khác. Script tự đo /health qua gateway từ
trước pull/chuyển traffic đến sau kiểm tra v2. Tải `downtime.csv` từ delivery-reports.
Muốn quan sát URL phía người dùng từ một máy khác, chạy thêm:

```bash
bash cd/monitor.sh http://SERVER_IP:8080/health reports/external-downtime.csv 180
```

Chỉ dùng SERVER_IP nếu đã mở gateway trong mạng lab. Đếm mẫu lỗi:

```bash
python3 - reports/downtime.csv <<'PY'
import csv,sys
rows=list(csv.DictReader(open(sys.argv[1])))
bad=[r for r in rows if r['http_status']!='200' or r['curl_exit']!='0']
print('Samples:',len(rows),'Failed:',len(bad))
print('Max latency:',max((float(r['latency_seconds']) for r in rows),default=0))
PY
```

Kỳ vọng có mẫu trước/trong/sau deployment, 0 lỗi trong khoảng đo và release cuối
là v2. Nếu có lỗi, ghi downtime đo được và điều tra; không đổi báo cáo thành 0.
Probe định kỳ không thấy mọi request của người dùng, không phải load test. Nâng
cấp đầu tiên chưa có dịch vụ cũ không được tính là zero-downtime release.

## Mẫu ghi kết quả

| Case | Commit/run ID | Kỳ vọng | Thực tế | Đường dẫn evidence | PASS/FAIL |
|---|---|---|---|---|---|
| Broken build | Điền sau khi chạy | Không push/deploy | Chưa chạy | — | Chưa đánh giá |
| Vulnerable image | | Gate chặn | Chưa chạy | — | Chưa đánh giá |
| Registry down | | Website cũ vẫn chạy | Chưa chạy | — | Chưa đánh giá |
| Deploy fail | | Khôi phục/giữ current | Chưa chạy | — | Chưa đánh giá |
| Rollback | | v2 → v1, DB còn | Chưa chạy | — | Chưa đánh giá |
| Downtime | | 0 lỗi trong mẫu đo | Chưa chạy | — | Chưa đánh giá |
