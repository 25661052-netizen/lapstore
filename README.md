# LapStore — web bán laptop và bài lab CI/CD

Source dành cho demo học tập: Node.js 24 + Express, frontend HTML/CSS/JavaScript,
MySQL 8.4. Một Dockerfile cho ứng dụng; `ci/` chứa test, `cd/` chứa triển khai.

Nếu triển khai qua SSH trên Ubuntu homeserver đã có Docker, làm theo
[hướng dẫn từng bước](docs/HOMESERVER.md): đưa source lên GitHub, chạy lab,
kiểm chứng persistence, dựng registry và bật CI/CD. Hướng dẫn cũng ghi rõ phần
monitoring gộp một container là bước cần triển khai tiếp; source hiện vẫn dùng
bốn container monitoring riêng.

## 1. Chạy web trên máy của bạn

Cài Docker Desktop (Windows 11, Linux containers/WSL2) hoặc Docker Engine +
Compose v2 trên Linux. Đảm bảo lệnh `docker compose version` chạy được.
Giải nén ZIP, mở terminal tại thư mục `lapstore` chứa Dockerfile.

```powershell
# PowerShell / Windows
Copy-Item .env.example .env
notepad .env
docker compose up -d --build --wait --wait-timeout 240
docker compose ps
```

Linux/Git Bash: dùng `cp .env.example .env` thay cho `Copy-Item`, rồi sửa `.env`.
Thay `DB_PASSWORD` và `MYSQL_ROOT_PASSWORD` bằng hai mật khẩu riêng (chỉ dùng chữ/số
cho dễ học cấu hình). Không để nguyên giá trị `replace_with_...`.
Có thể tạo mỗi mật khẩu bằng `openssl rand -hex 24` trên Linux.

Mở **http://localhost:3000**. MySQL tự tạo bảng và sáu laptop minh họa lần đầu.
Không cần cài Node.js trên host nếu chỉ chạy web bằng Docker.

- Khám phá: tìm kiếm, lọc danh mục, sắp xếp giá, xem chi tiết, giỏ hàng minh họa.
- Quản lý sản phẩm: thêm/sửa/xóa, xem số lượng và giá.
- Dữ liệu sản phẩm thực sự được lưu vào MySQL; giỏ hàng minh họa lưu ở trình duyệt.
- `GET /health`: kiểm tra đọc bảng `products`, không chỉ trả HTTP 200 cố định.
- Khi chạy trên VM/server, `localhost` là máy đó. Muốn truy cập từ Windows qua LAN,
  đặt `APP_BIND=0.0.0.0` trong `.env`, mở port 3000 cho mạng lab và chạy lại Compose.

CRUD quản trị chưa có đăng nhập theo phạm vi demo. Mặc định chỉ bind localhost.
Trước khi đưa lên Internet thực sự cần bổ sung xác thực quản trị và HTTPS cho web.
Không có thanh toán, đơn hàng, thông số kỹ thuật thương mại hoặc giá bán thật.

## 2. Dừng, xem log, kiểm tra dữ liệu

```bash
docker compose logs --tail 100 app db
docker compose down
docker compose up -d --wait --wait-timeout 240
```

Sản phẩm bạn đã thêm vẫn còn vì `mysql_data` là named volume.
`docker compose down -v` xóa volume và dữ liệu của stack đó. Chỉ thử lệnh này trên
lab local; hướng dẫn có đối chiếu dữ liệu tại [docs/PERSISTENCE.md](docs/PERSISTENCE.md).
Giữ nguyên thư mục/project name và mật khẩu khi kiểm tra down/up.

## 3. Kiểm thử bằng Node.js 24 trên host

```bash
npm ci
npm test
# Sau khi local Compose đã khỏe mạnh:
npm run test:api
```

`npm test`: logic validation và một số hành vi HTTP. `npm run test:api`: CRUD thật
qua HTTP; tạo sản phẩm riêng rồi xóa. Mặc định API là http://127.0.0.1:3000;
đổi bằng biến `BASE_URL` khi cần. Không có bước `npm run build` vì frontend thuần
và Node chạy trực tiếp; bước build của dự án là `docker build`.

## 4. Bắt đầu CI/CD

1. Tạo repository GitHub riêng và đưa source lên `main` (kể cả các file `.github/`).
2. Xem [docs/CICD.md](docs/CICD.md); đặt `ENABLE_DELIVERY=false` để thử CI.
3. Cài registry theo [docs/REGISTRY.md](docs/REGISTRY.md).
4. Chuẩn bị Linux x64 server, runner nhãn `lapstore-delivery`, runtime riêng.
5. Cấu hình Variables/Secrets rồi bật `ENABLE_DELIVERY=true`.
6. Push bản mới → test → build image → Trivy → test API → push → blue-green.
7. Chạy các tình huống tại [docs/DEFENSE-DRILLS.md](docs/DEFENSE-DRILLS.md).

Workflow có **2 job**, các Actions được khóa SHA, ứng dụng được deploy bằng digest.
PR chỉ chạy CI. Biến delivery tắt không ngăn rollback thủ công trên `main`.

## 5. Source nằm ở đâu?

| Đường dẫn | Vai trò |
|---|---|
| `app.js` | Server, frontend tĩnh, API CRUD, validation, health |
| `db.js` | Pool MySQL và SQL có tham số |
| `frontend/` | Trang web, CSS, JavaScript, hình SVG tự chứa |
| `database/schema.sql` | Bảng và dữ liệu minh họa khi database trống |
| `Dockerfile` | Một image ứng dụng, Node 24, npm ci, user node |
| `compose.yml` | Local/CI: app + MySQL, mạng mặc định, volume và bind mount |
| `cd/compose.deploy.yml` | CD: blue + green + Nginx + MySQL dùng chung |
| `ci/unit.test.js`, `ci/api.test.js` | Test code và test API |
| `cd/init.sh` | Chuẩn bị thư mục runtime, mật khẩu riêng trên server |
| `cd/deploy.sh`, `cd/rollback.sh` | Triển khai hoặc quay về image trước |
| `cd/common.sh` | Hàm dùng chung: state, health, chuyển proxy, khóa thao tác |
| `cd/monitor.sh` | Đo HTTP status/lỗi/độ trễ liên tục ra CSV |
| `.github/workflows/ci-cd.yml` | Điều phối CI/CD |
| `registry/` | Registry riêng: TLS, mật khẩu, volume image |
| `ops/` | Backup + Blackbox/cAdvisor/Prometheus/Grafana tùy chọn |
| `docs/` | Kiến trúc, pipeline, persistence, drill, vận hành |
| `reports/` | Báo cáo phát sinh khi test/deploy; không commit dữ liệu chạy |

Dockerfile single-stage được giữ theo lựa chọn đã chốt, thay cho yêu cầu multi-stage
ban đầu. MySQL, Nginx, registry và monitoring dùng image có sẵn, không thêm Dockerfile.

Image ứng dụng dùng Node 24 Alpine khóa bằng digest, chỉ chứa source cần chạy.
Sau `npm ci`, npm/Yarn được gỡ khỏi runtime; app khởi động bằng `node app.js`.
Chạy các lệnh npm trên máy phát triển hoặc helper Node riêng theo hướng dẫn test.

## 6. Trạng thái kiểm chứng

Kết quả thực tế trên homeserver ngày 19/10/2026 nằm tại
[docs/MANUAL-VALIDATION.md](docs/MANUAL-VALIDATION.md), gồm scan image, test với MySQL
và các phần đang được giữ lại để học triển khai.

Xem [docs/VALIDATION.md](docs/VALIDATION.md) để phân biệt kết quả đã chạy và phần
phải xác nhận trên Docker/server của bạn. Source có triển khai các bước, nhưng ZIP
không phải bằng chứng sáu drill đã đạt. Trivy có thể chặn build nếu image hiện tại
còn HIGH/CRITICAL; phải đọc báo cáo và sửa, không tự bỏ security gate.

Các dịch vụ lab dùng máy của bạn. GitHub-hosted runner/artifact và Docker Hub có
quota theo tài khoản; không giả định sử dụng vô hạn miễn phí.
