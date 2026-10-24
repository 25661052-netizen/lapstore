# Kết quả monitoring LapStore — 24/10/2026

Monitoring gộp đã được triển khai và người vận hành xác nhận các kết quả dưới.
Trợ lý chuẩn bị source, runbook và kiểm tra tĩnh local; không SSH hoặc trực
tiếp thực thi build/scan trên server. Các kết quả server trong bảng là xác
nhận của người vận hành, chưa được đối chiếu độc lập với toàn bộ JSON/log.

| Hạng mục | Kết quả được báo |
| --- | --- |
| Build image `security.1` | OK |
| Trivy trên image mới | PASS với gate HIGH/CRITICAL, scanner vuln và secret |
| Khởi chạy đúng image đã quét | Các kiểm tra startup đều PASS |
| Supervisor | cAdvisor, Blackbox, Prometheus, Grafana RUNNING |
| Health | Container healthy, Grafana khỏe, Prometheus ready |
| Prometheus targets | 5 targets đều UP |
| Dashboard | Các phần đều có metrics |
| Recreate container monitoring | Các kiểm tra vẫn PASS, metrics tiếp tục hoạt động |
| Lịch sử Prometheus | `PROMETHEUS_PERSISTENCE=PASS` |

Persistence truy vấn `up{job="prometheus"}` tại cùng một thời điểm trước khi
recreate, yêu cầu trước đó có một series và kết quả sau giống hệt. Container
ID phải đổi, image ID giữ nguyên và hai named volume được giữ. Đây là kiểm
chứng dữ liệu lịch sử Prometheus, không chỉ truy vấn dữ liệu mới sau restart.

Runbook cũng hướng dẫn kiểm tra thư mục tự tạo `LapStore Persistence Test`
trong Grafana. Người dùng báo các bước vẫn PASS nhưng chưa cung cấp xác nhận
riêng về thư mục; không suy ra persistence database Grafana chỉ từ dashboard
provisioned xuất hiện lại.

## Bằng chứng cần giữ

Các file sinh trên server trong `$HOME/lapstore/reports`:

- `monitoring-build-*.log`: log build.
- `monitoring-scan-*.json`, `.log`, `.exit-code.txt`, `.image-id.txt`: scan image mới.
- `monitoring-persistence-*.before.json`, `.after.json`, `.query-time.txt`:
  cùng truy vấn lịch sử trước/sau recreate.
- `monitoring-persistence-*.container-ids.txt`, `.image-id.txt`, `.targets.json`:
  định danh container/image và targets sau recreate.
- Screenshot dashboard có số liệu, năm targets UP và trạng thái thử Grafana.

Các đường dẫn scan/image ID và file bằng chứng thực tế chưa được gửi lại cho
trợ lý. Không tạo số liệu dung lượng image, thời gian build hoặc số CVE độc
lập khi chưa có báo cáo. Scan FAIL cũ trên Debian là bằng chứng trước sửa,
không phải kết quả của image mới đã được báo PASS. Các phép thử gây lỗi tiến
trình con/Supervisor và healthcheck riêng chưa có kết quả thực thi được báo.

## Hiện trạng và việc tiếp theo

- Project `lapstore-monitoring`, một service/container.
- Grafana `127.0.0.1:5202`, Prometheus `127.0.0.1:5203`.
- Hai volume riêng: `lapstore-monitoring_prometheus_data`,
  `lapstore-monitoring_grafana_data`.
- Source/assets/Go được khóa trong `source-lock.json`; app Dockerfile không đổi.
- Chốt Git và hồ sơ bằng chứng; container backup MySQL cùng bài restore là
  phần nâng cao tiếp theo, chưa được tính hoàn thành.
