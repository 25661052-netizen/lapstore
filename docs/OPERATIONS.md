# Phần nâng cao: backup và monitoring

Các file trong `ops/` không cần để chạy web hoặc CI. Chỉ bật sau khi runtime
`lapstore-live` đã chạy, vì mạng ngoài `lapstore-live_default` phải tồn tại.
Chạy từ source nằm ổn định trên server, không dùng runner checkout làm nơi giữ backup.

## Bật

Thêm `GRAFANA_PASSWORD=<mật khẩu riêng>` vào `.env` runtime; Docker Compose CD bỏ qua
biến không dùng này. Sau đó:

```bash
docker compose -p lapstore-ops --env-file /home/you/lapstore-runtime/.env -f ops/compose.yml up -d
```

Mặc định: Grafana localhost:3001, Prometheus localhost:9090, không mở ra Internet.
Grafana username admin, password ở biến trên. Datasource Prometheus đã được provision.
Import file `ops/dashboard.json` qua Dashboards → New → Import để xem dashboard mẫu.

cAdvisor được cố định phiên bản 0.60.6. Các image monitoring còn lại dùng tag latest để tiện bắt đầu lab. Trước khi dùng lâu dài,
ghi lại phiên bản/digest đã thử và pin trong ops/compose.yml; chúng không thuộc image
ứng dụng được CI build/scan/push. Không tuyên bố mọi image hạ tầng đều đã được Trivy quét.

## Backup

Container backup dùng MySQL official image, không cần Dockerfile mới. Kết nối `db`
qua mạng live, chạy mysqldump ngay khi khởi động rồi mỗi 24 giờ, giữ 7 file thành
công gần nhất trong `ops/backups` bằng bind mount. Nếu dump lỗi, không xóa bản cũ.
Đây là logical full backup, không có PITR/binlog hay scheduler đúng giờ cố định.

```bash
docker compose -p lapstore-ops --env-file /home/you/lapstore-runtime/.env -f ops/compose.yml logs backup
ls ops/backups
```

Dump có dữ liệu cửa hàng; không commit/publish. Bản sao trên cùng server không chống
được mất cả máy/ổ đĩa. Sao chép ra vị trí độc lập khi cần bảo vệ dữ liệu thật.

Để kiểm tra restore, dùng **database local lab** qua compose.yml, không dùng DB live:

```bash
# Chỉ trên local stack có dữ liệu được phép ghi đè; thay file bằng bản backup thật.
docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u lapstore lapstore' < ops/backups/lapstore-TIMESTAMP.sql
```

Refresh web, query SQL và đối chiếu sản phẩm với thời điểm backup. Lệnh trên có thể
ghi đè bảng trong database đích. Tự kiểm chứng restore mới được coi backup sử dụng được.

## Monitoring

Blackbox Exporter gọi `/health` qua gateway; Prometheus thu thập 5 giây/lần; Grafana
vẽ trạng thái, HTTP code, thời gian phản hồi và tỷ lệ thành công. Database lỗi làm
/health trả 503, probe báo fail. Chỉ `up` của exporter không đủ biết ứng dụng khỏe;
dashboard dùng `probe_success`.

Các truy vấn:

```promql
probe_success{job="lapstore"}
probe_http_status_code{job="lapstore"}
probe_duration_seconds{job="lapstore"}
100 * avg_over_time(probe_success{job="lapstore"}[1h])
```

### cAdvisor — tài nguyên từng container

cAdvisor đọc thông tin Docker/cgroup trên Linux server. Prometheus thu thập từ
`cadvisor:8080/metrics` mỗi 10 giây; Grafana hiển thị CPU, RAM working set, network
nhận/gửi và disk đọc/ghi. Blackbox vẫn kiểm tra website qua /health như trước.
cAdvisor không publish cổng ra host; Prometheus truy cập bằng mạng nội bộ của ops.

Cấu hình này dành cho Docker Engine rootful trên Linux với data root mặc định
`/var/lib/docker`, có `/dev/kmsg`. cAdvisor dùng privileged và mount thông tin host
để quan sát container, nên chỉ chạy image tin cậy trên server lab. Mount `:ro`
không biến Docker socket thành API chỉ đọc. Không thêm `:Z`/`:z` lên thư mục gốc
hoặc `/sys` trên CentOS/SELinux. Với Docker rootless, data root khác hoặc Docker
Desktop, cần điều chỉnh theo môi trường; Docker Desktop chỉ quan sát Linux VM,
không phải toàn bộ tài nguyên Windows.

Cập nhật sau khi thay các file ops trên server:

```bash
docker compose -p lapstore-ops --env-file /home/you/lapstore-runtime/.env -f ops/compose.yml up -d cadvisor
docker compose -p lapstore-ops --env-file /home/you/lapstore-runtime/.env -f ops/compose.yml restart prometheus
```

Nếu chưa chạy ops lần nào, dùng lệnh `up -d` toàn bộ stack ở đầu tài liệu. Import
lại `ops/dashboard.json` trong Grafana, chọn overwrite dashboard cùng UID. Tên mới
là **LapStore — Website & Containers**; vẫn giữ bốn biểu đồ availability cũ.

Kiểm tra trong Prometheus localhost:9090 → Status → Targets: `cadvisor` phải UP.
Đợi khoảng 2 phút để biểu đồ rate có đủ dữ liệu, rồi kiểm tra:

```promql
up{job="cadvisor"}
container_memory_working_set_bytes{job="cadvisor",container_label_com_docker_compose_project="lapstore-live"}
100 * sum by (name) (rate(container_cpu_usage_seconds_total{job="cadvisor",image!="",name!="",container_label_com_docker_compose_project=~"lapstore.*"}[2m]))
```

Biểu đồ tài nguyên lọc các project bắt đầu bằng `lapstore` và phân biệt tên từng
container: blue, green, MySQL, gateway, registry, ops. Nếu project của bạn đặt tên
khác, sửa bộ lọc trong dashboard. Nhãn Compose project/service được cho phép xuất
ra metrics; các label Docker khác không được thu để giảm dữ liệu không cần thiết.
CPU 100% nghĩa là một core, có thể vượt 100% khi dùng nhiều core. RAM hiển thị bytes,
không tính phần trăm vì source không đặt giới hạn memory cho từng container.

Disk I/O phụ thuộc kernel, cgroup và storage driver; có thể không có series trên
một số máy. Dashboard giữ **No data**, không giả thành 0. Nếu target UP nhưng không
thấy app/MySQL, kiểm tra log cAdvisor, Docker data root, mount/cgroup và nhãn
`container_label_com_docker_compose_project`; UP chỉ cho biết scrape thành công.

Không có alert gửi ra ngoài được cấu hình sẵn. Dữ liệu Grafana/Prometheus nằm trong
named volumes. Tham khảo: https://github.com/google/cadvisor và
https://github.com/google/cadvisor/blob/master/docs/storage/prometheus.md

## Vận hành thường ngày

- Không dùng docker compose down -v hoặc docker system prune trên live khi cần giữ
  dữ liệu/image rollback.
- `cd/init.sh` không cập nhật password database đã tồn tại. Đổi .env không tự đổi
  tài khoản MySQL; phải lập kế hoạch đổi cả phía database và app.
- `compose.deploy.yml`/schema runtime được cố định. Sửa hạ tầng hoặc migration cần
  kiểm tra tương thích riêng; release script sẽ từ chối nếu chúng khác source.
- Log `CRITICAL` khi phục hồi thất bại phải xử lý trên server; không có hệ thống HA.
- Rollback chỉ khôi phục app; phục hồi dữ liệu phải dùng backup/restore riêng.
