# Thiết lập CI/CD

## Bước 1 — CI trước

Đưa toàn bộ source vào repository GitHub, gồm `.github/workflows/ci-cd.yml`.
Tạo repository variable `ENABLE_DELIVERY=false` tại Settings → Secrets and variables
→ Actions → Variables. Chưa có biến cũng đồng nghĩa chưa bật push/deploy.

Push `main` hoặc mở PR tới `main` sẽ chạy CI trên Ubuntu của GitHub:
secret scan → npm ci → unit test → Docker build một lần → Trivy image → Compose
app/MySQL riêng → API CRUD → báo cáo → dọn volume CI. PR không có job Delivery.
Trivy HIGH hoặc CRITICAL (kể cả chưa có bản vá) làm job fail. Secret phát hiện làm
job fail. Bước sau không chạy khi bước trước lỗi. Các `|| true` chỉ dùng thu log/dọn
phiên đăng nhập, không dùng bỏ qua test/scan/deploy.

Ảnh app được quét và kiểm thử chính là ảnh được chuyển sang Delivery. Không build
lại trên server. Dockerfile npm ci --omit=dev khác CI npm ci: CI có thể cần test tools.

## Bước 2 — Chuẩn bị Linux x64 server

Cần Docker Engine, Compose v2 có `--wait`, curl, Python 3, OpenSSL, Bash và flock
(gói util-linux). Cài Docker theo hướng dẫn chính thức cho distro của bạn.
Runner user phải chạy được `docker info` và ghi được runtime.

Tạo registry theo REGISTRY.md. Tạo runtime từ source bằng **cùng user chạy runner**:

```bash
bash cd/init.sh /home/you/lapstore-runtime
```

Thay `/home/you` bằng thư mục thật. Đường dẫn phải nằm ngoài source và thư mục `_work`
của runner. Script tạo mật khẩu MySQL ngẫu nhiên, không cần tự đưa password DB lên
GitHub: runtime đọc `.env` tại server; CI tự sinh password riêng.

GitHub repository → Settings → Actions → Runners → New self-hosted runner → Linux
x64. Thực hiện đúng các lệnh/token hiển thị trong GitHub, thêm nhãn tùy chỉnh
**lapstore-delivery** và cài runner chạy như service. Không dùng token ví dụ từ tài
liệu. Runner chủ động kết nối GitHub; workflow này không dùng inbound SSH.

Nên dùng repository lab riêng; chỉ code tin cậy ở main/tag mới được chạy Delivery
vì runner có quyền Docker trên server. Bảo vệ main bằng PR review/CI theo nhu cầu.

## Bước 3 — Variables/Secrets

| Loại | Tên | Ví dụ/ý nghĩa |
|---|---|---|
| Variable | `ENABLE_DELIVERY` | `false` lúc thử CI; `true` khi sẵn sàng push/deploy |
| Variable | `REGISTRY_HOST` | `registry.lapstore.internal:5443` |
| Variable | `REGISTRY_IMAGE` | `registry.lapstore.internal:5443/lapstore/app` |
| Variable | `DEPLOY_DIR` | `/home/you/lapstore-runtime` |
| Secret | `REGISTRY_USER` | Username đã tạo bằng registry/setup.sh |
| Secret | `REGISTRY_PASSWORD` | Password registry tương ứng |

Biến ở **repository Variables**, không đặt riêng trong một GitHub Environment;
workflow hiện tại không khai báo environment. Không điền `https://` vào REGISTRY_HOST.
Runner và Docker daemon phải phân giải hostname registry và tin CA nội bộ.

## Bước 4 — Deploy và rollback

Bật ENABLE_DELIVERY=true và push commit mới lên main. Delivery nhận đúng image từ
CI, login, push rồi lấy digest. Script khởi tạo DB/gateway lần đầu, chạy slot blue;
lần sau chạy slot còn lại rồi chuyển traffic. Mở http://localhost:8080 trên server.
Runtime có GATEWAY_BIND/GATEWAY_PORT trong `.env`; mở LAN bằng 0.0.0.0 nếu cần demo
nội bộ. Không dùng cùng port 3000 với local stack.

Chạy thủ công: Actions → LapStore CI/CD → Run workflow → branch main → action deploy.
Vẫn cần ENABLE_DELIVERY=true và CI đạt. Rollback: chọn action rollback trên main;
CI được bỏ qua, không login/push/pull registry; dùng image previous còn tại server.
Rollback vẫn chạy khi ENABLE_DELIVERY=false. Phải có ít nhất hai image khác nhau
đã deploy thành công. Không xóa image cũ bằng prune trước khi thử.

Hai lớp khóa: GitHub concurrency cho job Delivery và flock trong script trên host.
Job đang deploy không bị tự hủy bởi commit mới. GitHub có thể thay thế run đang
pending trong concurrency group; không dùng số run làm danh sách release bảo đảm.

Nếu deploy mới lỗi, script trả exit khác 0, chuyển/giữ traffic ở current và kiểm tra
lại bản cũ. Vì vậy workflow đỏ dù rollback cứu ứng dụng thành công. Nếu rollback
cũng lỗi, log thông báo CRITICAL, cần xử lý thủ công; không giả vờ deployment xanh.

## Git/version/release

Làm việc ở `feature/...`, mở PR vào main. Khi sẵn sàng phát hành:

```bash
git switch main
git pull --ff-only
git tag v1.0.0
git push origin v1.0.0
```

Tag theo vMAJOR.MINOR.PATCH, phải trỏ commit đã thuộc main. Không dùng lại tag cũ.
Tạo GitHub Release từ tag ở trang Releases, ghi thay đổi và bằng chứng test. Workflow
không tự tạo Release. Tăng `package.json`/lock bằng `npm version ... --no-git-tag-version`
khi cập nhật phiên bản ứng dụng. `APP_VERSION` trong /health chứa digest đang chạy,
không phải version đọc từ package.json, để đối chiếu deployment chính xác.

## Báo cáo

| Artifact | Nội dung |
|---|---|
| `ci-reports` | unit-test.log, docker-build.log, secrets.json, trivy.json, api-test.log, containers.log |
| `lapstore-image` | Image tar đã kiểm tra; chỉ khi bật delivery, giữ 1 ngày |
| `delivery-reports` | deploy/rollback.log, image.txt, deployment.txt, downtime.csv và log container |

Bước chưa chạy thì báo cáo tương ứng chưa có, ví dụ broken build không sinh Trivy
image report. Reports lưu 14 ngày trên GitHub; runtime cũng giữ báo cáo theo thời
điểm. Download evidence về trước khi hết hạn. Artifact có thể chứa log ứng dụng;
không thêm mật khẩu vào output của ứng dụng.

`downtime.csv` được đo qua gateway mỗi khoảng 0,2 giây, timeout request 3 giây.
Không có lỗi trong mẫu đo là bằng chứng cho khoảng đo đó, không chứng minh tuyệt
đối không mất bất kỳ request nào. Deploy đầu tiên chưa có bản cũ nên không có
CSV so sánh downtime trước/sau; thực hiện drill trên lần nâng cấp thứ hai trở đi.

Tham khảo: https://docs.github.com/en/actions ; https://docs.docker.com/compose/ ;
https://trivy.dev/latest/docs/ ; https://nginx.org/en/docs/control.html
