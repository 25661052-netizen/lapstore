# Báo cáo kiểm chứng bộ source

Ngày chuẩn bị: 18/10/2026. Kết quả dưới đây phân biệt rõ kiểm tra source với
kiểm tra hạ tầng. Môi trường tạo source không có Docker daemon.

| Nội dung | Kết quả thực tế |
|---|---|
| Cài từ package-lock bằng npm ci | Đạt trên Node 24.19.0, npm 11.9.0 |
| Unit/HTTP tests | 13/13 đạt; raw TAP ở reports/local-unit.tap |
| npm audit --omit=dev | 0 advisory tại thời điểm kiểm tra; không thay thế Trivy image |
| UI desktop 1440 px và mobile 390 px | Đã chạy Chromium: không tràn ngang, không pageerror |
| UI tìm kiếm, lọc, giỏ hàng | Đạt với repository giả lập trong bộ nhớ |
| UI tạo/sửa/xóa | Đạt với repository giả lập, không phải MySQL |
| YAML và bash syntax | Parse đạt cho cấu hình và script; chưa là bằng chứng runtime đúng |
| Docker Compose config | CLI v2.39.4 parse được local, deploy, registry, ops |
| Điều kiện Delivery | 12 tình huống kiểm tra đạt: flag, PR, main/tag, lỗi CI, rollback, cancel |
| cd/init.sh | Tạo secrets quyền 600, schema quyền 644; chạy lại không đổi password |
| Dockerfile | Một file; Node 24, npm ci --omit=dev, USER node |
| API integration với MySQL thật | Chưa chạy tại môi trường tạo source; chạy npm run test:api sau Compose |
| Docker build, image Trivy, registry TLS | Chưa chạy thực tế tại đây |
| Deploy/rollback bằng Docker | Chưa chạy thực tế tại đây |
| Persistence, sáu Defense Drill | Có quy trình; chưa có kết quả PASS thực tế |
| Backup/restore và Grafana | Có cấu hình; chưa kiểm chứng trên Docker thật |

Frontend được kiểm tra bằng server dùng cùng `createApp()` với repository tạm để
đánh giá UI/HTTP. Repository giả lập không nằm trong source phát hành; ứng dụng
thật luôn dùng db.js kết nối MySQL. Không có dữ liệu fallback giả nếu database lỗi.

GitHub CI sẽ tạo Trivy report và API integration report thật khi chạy thành công
đến các bước tương ứng. Không cung cấp Trivy report giả hay kết quả zero-downtime
chưa đo. Node 24 base image và vulnerability database thay đổi theo thời gian;
security gate có thể chặn release dù logic ứng dụng đúng.

## Đối chiếu yêu cầu ban đầu

| Domain/yêu cầu | File hoặc cách thực hiện |
|---|---|
| Git, branch, tag, SemVer, Release | docs/CICD.md, workflow tag validation; tạo GitHub Release thủ công |
| Docker non-root, lockfile, immutable deploy | Dockerfile, package-lock, deploy theo digest |
| Multi-stage ban đầu | Đã đổi sang single-stage theo lựa chọn đã chốt với người dùng |
| Registry riêng | registry/compose.yml, TLS/auth setup và docs/REGISTRY.md |
| Test/build/scan/push/deploy | .github/workflows/ci-cd.yml; 2 job |
| Health, blue-green, rollback | compose.deploy.yml, cd/*.sh, state ngoài workspace |
| Trivy, HIGH/CRITICAL, secrets gate | Workflow, artifact reports |
| Product ID/Name/Category/Quantity/Price CRUD | app.js, db.js, database/schema.sql, frontend/ |
| Docker network | Mạng mặc định theo project; ops kết nối mạng live có sẵn |
| Volume và bind mount | mysql_data và schema.sql bind mount |
| Persistence down/up, down -v | docs/PERSISTENCE.md |
| Rollback v2 → v1, sáu drills | docs/DEFENSE-DRILLS.md |
| Backup và monitoring nâng cao | ops/, docs/OPERATIONS.md |

Đây là bộ source triển khai được sau khi cấu hình môi trường, không phải xác nhận
production-ready hoặc xác nhận tất cả yêu cầu đã qua thử nghiệm trên máy của bạn.

## Cập nhật cAdvisor — 18/10/2026

Thêm cAdvisor 0.60.6 vào ops, target scrape nội bộ và 7 panel Grafana (CPU, RAM,
network nhận/gửi, disk đọc/ghi, trạng thái scrape). Giữ 4 panel website cũ.
Đã kiểm tra YAML/JSON, Compose config và tính thống nhất service/target/dashboard.
Chưa chạy cAdvisor trên Docker thật, chưa xác nhận availability của từng metric
trên kernel/storage driver của server. Hướng dẫn xác minh nằm trong OPERATIONS.md.
