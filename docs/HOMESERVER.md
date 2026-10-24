# Triển khai LapStore qua SSH trên Ubuntu homeserver

Hướng dẫn dành cho homeserver **đã có Ubuntu, Docker Engine và Docker Compose**.
Máy Windows giữ source và dùng Git để đẩy thay đổi; homeserver chạy container.
Hoàn thành từng bước và đối chiếu kết quả trước khi chuyển sang bước tiếp theo.

## 0. Thứ tự thực hiện và trạng thái source

| Bước | Công việc | Điều kiện hoàn thành |
|---|---|---|
| 1 | Đưa source lên GitHub, tạm tắt delivery | Có repository và CI bắt đầu chạy |
| 2 | SSH, kiểm tra môi trường và clone source | Docker hoạt động, xác định CPU và port |
| 3 | Chạy ứng dụng + MySQL trên stack lab | Hai container healthy, CRUD hoạt động |
| 4 | Chạy unit/API test | Có log test đạt với MySQL thật |
| 5 | Chứng minh persistence | Đủ bằng chứng down/up và down -v/up |
| 6 | Chạy private registry | TLS/auth đúng, docker login thành công |
| 7 | Khởi tạo runtime và self-hosted runner | Runtime độc lập, runner Idle |
| 8 | Hoàn tất CI và bật delivery | Test/scan đạt, deploy đúng digest |
| 9 | Deploy hai phiên bản, rollback và đo downtime | Hai digest khác nhau, dữ liệu được giữ |
| 10 | Bật backup và thử restore | Có dump thật, restore thành công ở lab |
| 11 | Triển khai monitoring gộp một container | Bốn chương trình hoạt động trong một container |
| 12 | Hoàn tất sáu Defense Drill và bàn giao | Có kết quả thực tế, log/ảnh/artifact |

Source có frontend, API, MySQL, workflow và script blue-green. Đường dẫn đọc
Compose nguồn trong `cd/init.sh` và `cd/common.sh` đã được sửa thành
`cd/compose.deploy.yml`; bản sao tại runtime vẫn là `compose.deploy.yml`.

**Monitoring gộp dùng `ops/monitoring/compose.yml`**, project `lapstore-monitoring`.
Xem [runbook monitoring](../ops/monitoring/README.md) và
[kết quả kiểm chứng](../ops/monitoring/VALIDATION.md). `ops/compose.yml` vẫn giữ
cấu hình bốn service cũ để tham khảo; không dùng để bật monitoring gộp.
Thứ tự thực hiện hiện tại là monitoring trước, container backup/restore sau.

Mục tiêu sau khi gộp và đã có hai slot ứng dụng là **7 container thường trực**:
`blue`, `green`, `db`, `gateway`, `registry`, `backup`, `monitoring`.
Lần deploy đầu chỉ một slot app thì là 6. Stack lab, container test và container
helper chỉ chạy trong quá trình kiểm tra, cần dừng khi kiểm tra số lượng cuối.

Mặc định truy cập qua SSH tunnel. Chưa cần domain, public registry hoặc mở port
router. Nếu cần đưa website lên Internet, phải bổ sung phương án HTTPS và xác thực
quản trị vì API CRUD hiện chưa có đăng nhập.

## 1. Tạo repository và đưa source lên GitHub

Trên GitHub, tạo repository trống tên `lapstore`; dùng repository private cho lab
homeserver này. Không chọn tạo sẵn README, license hoặc .gitignore vì source đã có.
Quyền private không thay thế kiểm tra code trước khi merge vào main.

Trong repository, mở **Settings → Secrets and variables → Actions → Variables**,
tạo repository variable `ENABLE_DELIVERY` có giá trị `false`. Chưa đặt biến cũng
chưa bật delivery, nhưng đặt rõ giúp dễ kiểm soát.

Tại PowerShell trên Windows:

```powershell
Set-Location 'C:\baitap_HCE\AO_HOA\LapStore-source\lapstore'
git init -b main
git config core.autocrlf false
git status --short
```

Nếu Git yêu cầu thông tin tác giả, đặt tên/email của bạn bằng `git config user.name`
và `git config user.email`. Sau đó kiểm tra `.gitignore` và danh sách trước commit:

```powershell
git add .
git diff --cached --stat
git diff --cached --name-only
```

Không đưa `.env`, password, registry certificates/private keys, backup hoặc token
vào commit. Các thư mục nhạy cảm của project đã có trong `.gitignore`.
`reports/local-unit.tap` đang bị ignore theo thiết kế; lưu kết quả chạy mới làm
artifact/evidence thay vì coi file có sẵn là kết quả trên homeserver.

Thay URL ví dụ bằng repository vừa tạo:

```powershell
git commit -m "chore: initialize LapStore deployment project"
git remote add origin https://github.com/OWNER/lapstore.git
git push -u origin main
```

Dùng đăng nhập GitHub do Git/Git Credential Manager mở ra; không chèn token vào
URL repository. Nếu repository đã được khởi tạo Git, dùng cấu hình hiện có thay
vì lặp lại phần tạo mới.

Mở tab **Actions**. Push đầu tiên chạy CI; delivery chưa chạy. CI có thể cần sửa
dependency/base image nếu Trivy phát hiện HIGH/CRITICAL. Giữ nguyên security gate.

**Kết quả cần có:** repository chứa cả `.github/workflows/ci-cd.yml`, `cd/`, `ops/`,
`database/` và frontend/backend; delivery vẫn tắt.

## 2. SSH và chuẩn bị thư mục trên homeserver

Tại Windows, thay `USER_HOMESERVER` và `IP_HOMESERVER` bằng tài khoản/địa chỉ thực:

```powershell
ssh USER_HOMESERVER@IP_HOMESERVER
```

Các lệnh Bash dưới đây chạy **trong phiên SSH**:

```bash
uname -m
docker version
docker compose version
docker info --format 'RootDir={{.DockerRootDir}} Architecture={{.Architecture}} Security={{json .SecurityOptions}}'
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
ss -ltn
command -v git curl openssl python3 flock
```

Kiểm tra các port host 3000, 8080, 3001, 9090, 5204 chưa bị dịch vụ khác chiếm.
Không dừng dịch vụ khác chỉ để lấy port; nếu có xung đột thì đổi port của LapStore
và các lệnh tunnel/test tương ứng.

- `x86_64` phù hợp workflow hiện tại (`linux`, `x64`, `lapstore-delivery`).
- Nếu là `aarch64`, phần lab có thể chạy image ARM64 nếu image hỗ trợ, nhưng phải
  chỉnh kiến trúc build và runner trước bước delivery. Chỉ đổi nhãn runner không
  biến image amd64 đã build thành image ARM64.
- Nếu `docker info` báo permission denied, xác định quyền socket. Dùng cùng một
  tài khoản Linux có quyền chạy Docker cho bước này và cho runner; không cài lại
  Docker chỉ vì lỗi quyền.
- cAdvisor hiện nhắm Docker rootful Linux với data root `/var/lib/docker`. Nếu
  host dùng rootless hoặc data root khác, cần điều chỉnh bước 11.

Tạo bố cục thư mục:

```bash
mkdir -p "$HOME/projects" "$HOME/lapstore-evidence"
export LAPSTORE_SRC="$HOME/projects/lapstore"
export DEPLOY_DIR="$HOME/lapstore-runtime"
export EVIDENCE_DIR="$HOME/lapstore-evidence"
```

| Đường dẫn | Công dụng |
|---|---|
| `$HOME/projects/lapstore` | Clone ổn định để thao tác, chạy registry/ops |
| `$HOME/lapstore-runtime` | Cấu hình, secrets, proxy, state và log live |
| `$HOME/actions-runner-lapstore` | GitHub runner và checkout tự động trong `_work` |
| `$HOME/lapstore-evidence` | Bằng chứng test và triển khai |

Các biến `export` chỉ tồn tại trong phiên SSH hiện tại. Khi mở phiên SSH mới, đặt
lại chúng trước khi chạy các lệnh dùng biến.

Với repository private, chuẩn bị SSH key riêng của server trước khi clone.
Tạo key lần đầu; nếu file cùng tên đã có, dùng key hiện có thay vì ghi đè:

```bash
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keygen -t ed25519 -C lapstore-homeserver -f "$HOME/.ssh/id_ed25519_lapstore"
cat "$HOME/.ssh/id_ed25519_lapstore.pub"
```

Chép **public key** vừa in ra. Trên repository GitHub, mở **Settings → Deploy keys
→ Add deploy key**, đặt tên `lapstore-homeserver-source` và dán public key; không
bật **Allow write access** vì clone ổn định chỉ cần đọc source. Private key không
được đưa lên GitHub hoặc vào chat.

Kiểm tra kết nối rồi clone; thay `OWNER` bằng tài khoản/tổ chức của repository:

```bash
ssh -i "$HOME/.ssh/id_ed25519_lapstore" -o IdentitiesOnly=yes -T git@github.com
git -c core.sshCommand="ssh -i $HOME/.ssh/id_ed25519_lapstore -o IdentitiesOnly=yes" \
  clone git@github.com:OWNER/lapstore.git "$LAPSTORE_SRC"
git -C "$LAPSTORE_SRC" config core.sshCommand "ssh -i $HOME/.ssh/id_ed25519_lapstore -o IdentitiesOnly=yes"
cd "$LAPSTORE_SRC"
git log -1 --oneline
```

Lần kết nối đầu, đối chiếu host fingerprint theo hướng dẫn GitHub trước khi chấp
nhận. `ssh -T` thành công báo đã xác thực nhưng không cung cấp shell; exit code 1
trong trường hợp đó là bình thường. Nếu đặt passphrase, nhập khi SSH/Git hỏi.
Hướng dẫn: [kiểm tra SSH GitHub](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection),
[deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys).

Runtime và registry credentials không nằm trong thư mục `_work` của runner.
Runner có thể dọn checkout giữa các job; clone ổn định giữ cấu hình registry,
backup và các file bind mount không bị dọn theo job.

## 3. Build và chạy ứng dụng + MySQL

Chạy tại `$LAPSTORE_SRC`. Tạo `.env` lần đầu; đoạn này giữ nguyên file nếu đã có:

```bash
cd "$LAPSTORE_SRC"
if [ ! -f .env ]; then
  (
    umask 077
    printf 'DB_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'MYSQL_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'APP_IMAGE=lapstore:local\nAPP_BIND=127.0.0.1\nAPP_PORT=3000\n'
  ) > .env
fi
chmod 600 .env
docker compose -p lapstore-lab --env-file .env -f compose.yml config --quiet
docker compose -p lapstore-lab --env-file .env -f compose.yml up -d --build --wait --wait-timeout 240
docker compose -p lapstore-lab --env-file .env -f compose.yml ps
curl -fsS http://127.0.0.1:3000/health
```

Kỳ vọng hai service `app`, `db` healthy và `/health` trả
`{"status":"ok","database":"connected","release":"local"}`.
Nếu lỗi, đọc log trước khi chạy tiếp:

```bash
docker compose -p lapstore-lab --env-file .env -f compose.yml logs --tail 100 app db
```

Không dùng `docker compose config` không có `--quiet` khi chụp báo cáo, vì bản
cấu hình được render có thể chứa password.

Mở **một cửa sổ PowerShell khác** trên Windows, tạo tunnel:

```powershell
ssh -N -L 3000:127.0.0.1:3000 USER_HOMESERVER@IP_HOMESERVER
```

Giữ cửa sổ tunnel mở và truy cập `http://localhost:3000` trên Windows. `localhost`
ở URL lúc này được chuyển đến homeserver; không cần đổi `APP_BIND=0.0.0.0`.
Nếu port 3000 trên Windows đã bận, đổi phần đầu tunnel thành `-L 13000:127.0.0.1:3000`
và mở `http://localhost:13000`.

Thử trên giao diện: danh sách → chi tiết → thêm laptop → sửa tên/giá/tồn kho → xóa.
Kiểm tra tìm kiếm, danh mục và giỏ hàng; giỏ hàng chỉ lưu trong browser, không phải
dữ liệu MySQL.

Xác minh app chạy non-root:

```bash
docker compose -p lapstore-lab --env-file .env -f compose.yml exec -T app id
docker image inspect lapstore:local --format '{{.Config.User}}'
```

Kỳ vọng app có user `node`, UID khác 0. Chụp UI, trạng thái healthy và lưu kết quả:

```bash
curl -fsS http://127.0.0.1:3000/health -o "$EVIDENCE_DIR/lab-health.json"
docker compose -p lapstore-lab --env-file .env -f compose.yml ps > "$EVIDENCE_DIR/lab-containers.txt"
```

## 4. Chạy unit test và API test với MySQL thật

Không bắt buộc cài Node.js trên Ubuntu host. Container helper Node 24 dưới đây
copy đúng phần code cần test vào thư mục tạm, chạy test rồi tự xóa container.
Source mount chỉ đọc; `node_modules` không được ghi vào source.

```bash
cd "$LAPSTORE_SRC"
set -o pipefail
docker run --rm --network host \
  --mount "type=bind,src=$LAPSTORE_SRC,dst=/src,readonly" \
  --tmpfs /work:rw,exec,mode=1777 \
  -w /work -e BASE_URL=http://127.0.0.1:3000 \
  node:24 sh -lc 'cp /src/package.json /src/package-lock.json /src/app.js . && cp -r /src/ci /src/frontend . && npm ci && npm test && npm run test:api' \
  2>&1 | tee "$EVIDENCE_DIR/local-tests.log"
```

Unit test dùng repository giả để kiểm tra validation/HTTP. API test gọi stack lab
đang chạy thật, tạo/sửa/xóa sản phẩm riêng và xác minh dữ liệu trả về. Không trỏ
API test vào runtime live.

**Kết quả cần có:** cả hai lệnh test đạt, không còn sản phẩm tạm của API test.
Nếu host không phải Linux hoặc không có network host phù hợp, cần đổi cách nối
container helper tới API; hướng dẫn này dành cho Ubuntu Docker Engine đã nêu.

## 5. Chứng minh persistence trên stack lab

Tạo sản phẩm dễ nhận ra bằng API, lưu phản hồi và danh sách trước khi dừng:

```bash
curl -fsS -X POST http://127.0.0.1:3000/api/products \
  -H 'Content-Type: application/json' \
  -d '{"name":"PERSISTENCE-DEMO-001","category":"Học tập","quantity":9,"price":12345000}' \
  -o "$EVIDENCE_DIR/persistence-created.json"
curl -fsS http://127.0.0.1:3000/api/products -o "$EVIDENCE_DIR/persistence-before.json"
docker compose -p lapstore-lab --env-file .env -f compose.yml down
docker compose -p lapstore-lab --env-file .env -f compose.yml up -d --wait --wait-timeout 240
curl -fsS http://127.0.0.1:3000/api/products -o "$EVIDENCE_DIR/persistence-after-down-up.json"
```

Đối chiếu UI/JSON: sản phẩm vẫn còn, giữ đúng ID, quantity và price.
Named volume `lapstore-lab_mysql_data` tồn tại sau `down` và được gắn lại khi `up`.

Phần tiếp theo **chỉ xóa dữ liệu của stack lab vừa tạo**. Giữ `-p lapstore-lab`,
không thay bằng `lapstore-live` hoặc `lapstore-registry`:

```bash
docker compose -p lapstore-lab --env-file .env -f compose.yml down -v
docker compose -p lapstore-lab --env-file .env -f compose.yml up -d --wait --wait-timeout 240
curl -fsS http://127.0.0.1:3000/api/products -o "$EVIDENCE_DIR/persistence-after-down-v-up.json"
```

Kỳ vọng `PERSISTENCE-DEMO-001` biến mất, sáu laptop seed xuất hiện lại. `down -v`
xóa named volume; bind mount `database/schema.sql` vẫn còn nên MySQL khởi tạo DB
mới từ file SQL. Lưu ảnh UI ở cả ba thời điểm. Xem [PERSISTENCE.md](PERSISTENCE.md).

Sau khi lưu bằng chứng, dừng stack lab để tập trung vào runtime live:

```bash
docker compose -p lapstore-lab --env-file .env -f compose.yml down
```

## 6. Dựng private registry TLS và đăng nhập

Chạy từ clone ổn định, thực hiện một lần:

```bash
cd "$LAPSTORE_SRC"
bash registry/setup.sh
```

Nhập username registry và password riêng theo yêu cầu script. Giữ password trong
trình quản lý mật khẩu để nhập vào GitHub Secrets ở bước 8; không gửi vào chat.

Chỉnh `/etc/hosts` trên **homeserver**:

```bash
sudoedit /etc/hosts
```

Thêm dòng sau nếu chưa có:

```text
127.0.0.1 registry.lapstore.internal
```

Trust CA cho Docker và Ubuntu, rồi chạy registry:

```bash
sudo mkdir -p /etc/docker/certs.d/registry.lapstore.internal:5204
sudo cp registry/certs/ca.crt /etc/docker/certs.d/registry.lapstore.internal:5204/ca.crt
sudo cp registry/certs/ca.crt /usr/local/share/ca-certificates/lapstore-registry.crt
sudo update-ca-certificates
docker compose -p lapstore-registry -f registry/compose.yml up -d
docker compose -p lapstore-registry -f registry/compose.yml ps
curl --cacert registry/certs/ca.crt -I https://registry.lapstore.internal:5204/v2/
docker login registry.lapstore.internal:5204
```

Curl chưa có credentials trả **401** là đúng; `docker login` phải thành công và
không báo lỗi certificate. Nếu Docker chưa nhận CA, xem [REGISTRY.md](REGISTRY.md)
trước khi cân nhắc restart daemon vì homeserver có thể đang chạy dịch vụ khác.

Registry bind loopback 5204. CI trên GitHub sẽ gửi image bằng artifact cho runner
trên homeserver; không cần public registry này để GitHub-hosted runner truy cập.

## 7. Tạo runtime live và self-hosted runner

Tạo runtime bằng cùng tài khoản Linux sẽ chạy runner:

```bash
cd "$LAPSTORE_SRC"
git pull --ff-only
bash cd/init.sh "$DEPLOY_DIR"
stat -c '%a %n' "$DEPLOY_DIR/.env" "$DEPLOY_DIR/database/schema.sql"
printf 'DEPLOY_DIR=%s\n' "$DEPLOY_DIR"
```

Kỳ vọng `.env` quyền 600, schema quyền 644. Lưu đường dẫn tuyệt đối in ra để nhập
GitHub Variable `DEPLOY_DIR`. Không dùng literal `$HOME` trong giá trị variable.
Script chỉ chuẩn bị file, chưa chạy container. Không dùng thư mục source hoặc
checkout `_work` làm runtime.

Trong GitHub: **Settings → Actions → Runners → New self-hosted runner → Linux → x64**.
Nếu bước 2 cho thấy ARM64, điều chỉnh kiến trúc workflow/image trước khi đăng ký
runner dùng cho delivery.

Trên homeserver:

```bash
mkdir -p "$HOME/actions-runner-lapstore"
cd "$HOME/actions-runner-lapstore"
```

Chạy nguyên các lệnh download, kiểm tra checksum và giải nén mà GitHub đang hiển
thị. Dùng bản runner hiện tại từ trang đó, không dùng một URL/token ví dụ cũ.
Chạy lệnh `./config.sh` do GitHub cung cấp; khi hỏi thêm labels, nhập
**lapstore-delivery**. Giữ các labels mặc định `self-hosted`, `linux`, `x64`.
Đặt tên runner `lapstore-homeserver` để dễ nhận ra.

Sau khi config thành công, cài service bằng chính tài khoản hiện tại:

```bash
sudo ./svc.sh install "$USER"
sudo ./svc.sh start
sudo ./svc.sh status
```

Kỳ vọng GitHub hiển thị runner **Idle**. Runner tự kết nối ra GitHub, không cần
GitHub SSH vào homeserver hoặc mở cổng SSH thêm trên router. Service runner chạy
trên host, không phải container thường trực thứ tám.

Hướng dẫn chính thức: [thêm runner](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners),
[cài service](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/configure-the-application).

## 8. Hoàn tất CI, cấu hình delivery và deploy lần đầu

Trong **Settings → Secrets and variables → Actions**, nhập các mục sau:

| Loại | Tên | Giá trị |
|---|---|---|
| Variable | `ENABLE_DELIVERY` | Giữ `false` cho đến khi CI đạt và runner Idle |
| Variable | `REGISTRY_HOST` | `registry.lapstore.internal:5204` |
| Variable | `REGISTRY_IMAGE` | `registry.lapstore.internal:5204/lapstore/app` |
| Variable | `DEPLOY_DIR` | Đường dẫn tuyệt đối ở bước 7, ví dụ `/home/youruser/lapstore-runtime` |
| Secret | `REGISTRY_USER` | Username đã tạo ở bước 6 |
| Secret | `REGISTRY_PASSWORD` | Password tương ứng |

Không thêm `https://` vào `REGISTRY_HOST`; DB passwords được quản lý riêng ở
runtime server, không cần đưa chúng vào GitHub Secrets cho workflow hiện tại.

Kiểm tra job CI trên GitHub theo đúng thứ tự:

1. Quét secret trong source.
2. `npm ci` và unit/HTTP tests.
3. Build image ứng dụng một lần.
4. Trivy quét image, chặn HIGH/CRITICAL.
5. Chạy chính image đó với MySQL trong Compose riêng của CI.
6. API test CRUD thật và lưu báo cáo.

Nếu bước nào lỗi, đọc artifact/log tương ứng rồi sửa source và push lại.
Không bỏ qua lỗi Trivy/test để bật deployment.

Khi CI đạt, registry sẵn sàng và runner Idle, đổi `ENABLE_DELIVERY=true`.
Mở **Actions → LapStore CI/CD → Run workflow → main → action deploy**.
Lần chạy manual này vẫn chạy CI rồi mới delivery; không bỏ qua kiểm tra.

Delivery load image đã kiểm tra, push registry, lấy digest, pull digest về runtime,
khởi động MySQL và slot blue, kiểm tra health rồi đưa Nginx vào phục vụ.

Kiểm tra trên homeserver:

```bash
curl -fsS http://127.0.0.1:8080/health
docker ps --filter label=com.docker.compose.project=lapstore-live
cat "$DEPLOY_DIR/state"
curl -fsS http://127.0.0.1:8080/health -o "$EVIDENCE_DIR/live-v1-health.json"
cp "$DEPLOY_DIR/state" "$EVIDENCE_DIR/live-v1-state.txt"
```

Kỳ vọng `release` là chuỗi `registry.lapstore.internal:5204/lapstore/app@sha256:...`,
trùng current image trong state và `image.txt` ở artifact Delivery. State không
chứa DB password nhưng vẫn lưu evidence nội bộ.

Mở tunnel thứ hai từ Windows để truy cập live:

```powershell
ssh -N -L 8080:127.0.0.1:8080 USER_HOMESERVER@IP_HOMESERVER
```

Mở `http://localhost:8080`. Lần deploy đầu có `db`, `blue`, `gateway` cùng registry;
chưa có green và chưa bật backup/monitoring. Xem thêm [CICD.md](CICD.md).

## 9. Phiên bản thứ hai, rollback và đo downtime

Trên Windows, làm thay đổi nhỏ có thể nhìn thấy ở giao diện, không sửa schema/Compose
trong bài thử này. Làm qua branch rồi PR vào main:

```powershell
git switch -c feature/demo-v2
# Chỉnh một dòng giao diện để nhận biết phiên bản mới.
npm.cmd version patch --no-git-tag-version
git add frontend/index.html package.json package-lock.json
git commit -m "feat: mark second demo release"
git push -u origin feature/demo-v2
```

Lệnh `npm.cmd version` cần Node/npm trên Windows và chỉ cập nhật metadata phiên
bản; các bài test của project vẫn dùng Node 24 trong CI/container. Nếu Windows
không có npm, thay lệnh này bằng cập nhật version giống nhau ở `package.json`,
version đầu `package-lock.json` và `packages[""].version` trong lock (ví dụ từ
`1.0.0` thành `1.0.1`).

PR chạy CI; merge khi đạt. Push vào main tự chạy CI và delivery. Có thể dùng
`v1.0.0` và `v1.0.1` làm hai bản trong bài **v1 → v2 → v1**; tên v1/v2 ở đây chỉ
hai lần phát hành. Chọn tăng major/minor/patch theo mức thay đổi thực tế.

Sau delivery thứ hai, lưu health/state trước khi rollback:

```bash
curl -fsS http://127.0.0.1:8080/health -o "$EVIDENCE_DIR/live-v2-health.json"
cp "$DEPLOY_DIR/state" "$EVIDENCE_DIR/live-v2-state.txt"
docker ps --filter label=com.docker.compose.project=lapstore-live
```

Xác nhận có hai digest khác nhau, hai slot app chạy và UI mới đang được phục vụ.
Tạo một sản phẩm `ROLLBACK-DATA-001` qua UI ở phiên bản mới, ghi lại ID/giá/tồn kho.

Tải artifact `delivery-reports` của lần nâng cấp. File `downtime.csv` phải có mẫu
trước/trong/sau chuyển traffic. Script đo qua gateway khoảng 0,2 giây/lần, timeout
3 giây; deploy đầu không có CSV so sánh vì chưa có phiên bản cũ.

Rollback: **Actions → Run workflow → main → action rollback**. Hoặc CLI từ clone
ổn định có script cùng phiên bản:

```bash
cd "$LAPSTORE_SRC"
git pull --ff-only
bash cd/rollback.sh "$DEPLOY_DIR"
curl -fsS http://127.0.0.1:8080/health -o "$EVIDENCE_DIR/live-after-rollback-health.json"
cp "$DEPLOY_DIR/state" "$EVIDENCE_DIR/live-after-rollback-state.txt"
```

Kỳ vọng release/UI trở về bản trước nhưng sản phẩm `ROLLBACK-DATA-001` vẫn còn.
Rollback đổi image app, không khôi phục database. Không prune image previous;
manual rollback dùng image còn trên host và không cần registry hoạt động.

Đếm lỗi trong CSV bằng đoạn Python ở [Defense Drill 6](DEFENSE-DRILLS.md#6-đo-downtime-khi-nâng-cấp).
Ghi số mẫu, số lỗi và độ trễ cao nhất. Nếu số lỗi là 0, kết luận đúng là **không
ghi nhận lỗi trong khoảng đo**, không phải chứng minh tuyệt đối mọi request đều
không bị gián đoạn.

## 10. Backup định kỳ và restore ở lab

Thêm password Grafana ngẫu nhiên vào runtime nếu chưa có. Biến này cần cả khi chỉ
bật backup, vì Compose hiện tại kiểm tra biến bắt buộc ở toàn bộ cấu hình:

```bash
if ! grep -q '^GRAFANA_PASSWORD=' "$DEPLOY_DIR/.env"; then
  printf 'GRAFANA_PASSWORD=%s\n' "$(openssl rand -hex 24)" >> "$DEPLOY_DIR/.env"
fi
chmod 600 "$DEPLOY_DIR/.env"
cd "$LAPSTORE_SRC"
docker compose -p lapstore-ops --env-file "$DEPLOY_DIR/.env" -f ops/compose.yml config --quiet
docker compose -p lapstore-ops --env-file "$DEPLOY_DIR/.env" -f ops/compose.yml up -d backup
docker compose -p lapstore-ops --env-file "$DEPLOY_DIR/.env" -f ops/compose.yml logs --tail 50 backup
ls -lh ops/backups/
```

Backup dùng network live đã tồn tại, kết nối MySQL live và dump ngay lúc khởi động,
sau đó mỗi 24 giờ; giữ 7 bản thành công mới nhất. Nếu đang dump, đợi log `Backup OK`
và file `.sql` hoàn chỉnh; file `.tmp` chưa phải backup dùng để restore.

Kiểm tra restore vào **stack lab**, không ghi đè MySQL live. Chọn một file backup
thật từ danh sách, thay tên ví dụ dưới đây:

```bash
docker compose -p lapstore-lab --env-file .env -f compose.yml up -d --no-build --wait --wait-timeout 240
BACKUP_FILE='ops/backups/lapstore-YYYYMMDDTHHMMSS.sql'
test -s "$BACKUP_FILE"
docker compose -p lapstore-lab --env-file .env -f compose.yml exec -T db \
  sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u lapstore lapstore' < "$BACKUP_FILE"
curl -fsS http://127.0.0.1:3000/api/products -o "$EVIDENCE_DIR/restore-lab-products.json"
```

Chỉ chạy lệnh import sau khi `test -s` thành công. So sánh sản phẩm ở lab với dữ
liệu tại thời điểm backup, chụp UI/SQL rồi dừng lab:

```bash
docker compose -p lapstore-lab --env-file .env -f compose.yml down
```

Backup trên cùng ổ đĩa chưa bảo vệ khỏi mất cả server; nếu cần giữ dữ liệu thật,
thêm bản sao ở nơi độc lập. Xem [OPERATIONS.md](OPERATIONS.md).

## 11. Monitoring gộp một container

Monitoring hiện dùng Compose riêng tại [ops/monitoring/compose.yml](../ops/monitoring/compose.yml),
project `lapstore-monitoring`. Làm theo [runbook monitoring](../ops/monitoring/README.md)
để build, quét, khởi chạy, truy cập dashboard và kiểm tra persistence.
Không dùng cấu hình bốn container cũ trong `ops/compose.yml` để bật stack này.

Theo xác nhận của người vận hành ngày 24/10/2026: build OK, Trivy PASS, bốn
chương trình RUNNING, năm targets UP, các phần dashboard có metrics và
`PROMETHEUS_PERSISTENCE=PASS` sau recreate. Phạm vi bằng chứng và các điểm chưa
được xác nhận riêng nằm tại [VALIDATION.md](../ops/monitoring/VALIDATION.md).

Grafana ở `127.0.0.1:5202`, Prometheus ở `127.0.0.1:5203`; truy cập qua SSH
tunnel theo runbook. cAdvisor và Blackbox chỉ lắng nghe loopback bên trong
container. Supervisor nằm cùng container, không tạo container Supervisor riêng.

Source/assets/Go khóa version/hash trong `source-lock.json`. Dockerfile
monitoring là single-stage riêng; Dockerfile ứng dụng vẫn single-stage chung
frontend/backend và app chạy non-root. Các tiến trình Grafana, Prometheus,
Blackbox dùng user riêng; Supervisor/cAdvisor dùng root cho phạm vi quan sát host
đã được người vận hành chấp nhận. Compose không bật privileged hoặc host PID.

Hai named volume monitoring được giữ khi recreate. Container backup/restore
MySQL tiếp tục thực hiện sau phần monitoring; không tính dump migration thủ
công là đã hoàn thành backup định kỳ.

## 12. Defense Drill, version/release và hồ sơ bàn giao

Thực hiện đủ sáu bài theo [DEFENSE-DRILLS.md](DEFENSE-DRILLS.md). Chỉ thử trên các
thành phần lab của LapStore; không dừng Docker daemon hoặc dịch vụ homeserver khác.

| Drill | Cách thực hiện | Điều kiện phải quan sát |
|---|---|---|
| Broken build | Branch riêng, thêm `RUN exit 1`, mở PR | Build fail; không push/deploy; live giữ nguyên |
| Vulnerable image | Branch riêng với dependency có HIGH/CRITICAL được Trivy xác nhận | Gate fail có báo cáo package/version/severity |
| Registry unavailable | Dừng riêng service registry, push thay đổi hợp lệ | CI đạt, Delivery login/push fail; live vẫn khỏe; bật registry lại |
| Failed deployment | Build image lỗi có chủ ý theo lệnh trong tài liệu drill | Deploy nonzero; state không commit image lỗi; bản cũ vẫn phục vụ |
| Rollback v2 → v1 | Hai release có digest khác nhau, chạy rollback | Health/UI về v1; dữ liệu tạo tại v2 vẫn còn |
| Downtime | Lấy CSV của lần nâng cấp thứ hai trở đi | Có mẫu đủ giai đoạn, báo đúng số lỗi/latency thực tế |

Hai branch cố tình lỗi đầu tiên không merge vào main. Không tạo báo cáo PASS nếu
chưa chạy; nếu scanner hiện tại không đánh HIGH/CRITICAL cho fixture thì chọn
fixture khác có bằng chứng, không hạ ngưỡng scan.

Để có quản lý Git hoàn chỉnh, làm việc qua `feature/...` → PR → main. Khi tạo tag,
chọn phiên bản tương ứng `package.json` và lock. PowerShell lấy version từ package
hiện tại để tránh tạo nhầm tag của bản trước:

```powershell
git switch main
git pull --ff-only
$lapstoreTag = 'v' + (Get-Content -Raw package.json | ConvertFrom-Json).version
git tag $lapstoreTag
git push origin $lapstoreTag
```

Chỉ dùng ví dụ này khi phiên bản/tag phù hợp và chưa tồn tại; không di chuyển tag
đã phát hành. Tag cũng kích hoạt pipeline nếu delivery đang bật, nên chờ các bài
thử cần current/previous cố định hoàn tất trước khi tạo thêm release. Tạo GitHub
Release thủ công từ tag, ghi thay đổi và đính kèm evidence đã chọn.

Hồ sơ bàn giao cần có:

- Repository, branch/PR, tag/release và version nhất quán.
- Dockerfile app, Compose local/live/registry/ops và sơ đồ ở [ARCHITECTURE.md](ARCHITECTURE.md).
- Workflow, registry TLS/auth, script deploy/rollback và hướng dẫn này.
- `ci-reports`: unit/API logs, Docker build log, secrets scan, Trivy JSON, container logs.
- `delivery-reports`: image digest, deploy/rollback log, CSV downtime và kết quả kiểm tra release.
- Evidence persistence, sáu drill, backup/restore và monitoring nếu làm phần nâng cao.
- Bảng ghi expected/actual/PASS/FAIL, commit SHA, run ID, thời điểm và đường dẫn evidence.

Artifact CI/Delivery giữ 14 ngày theo workflow; image tar chuyển job giữ 1 ngày.
Tải báo cáo cần bàn giao trước khi hết hạn. Không đưa password/private key/backup
database vào repository hay release công khai. Dùng [VALIDATION.md](VALIDATION.md)
để phân biệt kiểm tra source có sẵn với kết quả vừa chạy thực tế trên homeserver.

## Xử lý lỗi thường gặp

| Hiện tượng | Kiểm tra tiếp |
|---|---|
| `docker: permission denied` | Quyền Docker của đúng user SSH/service runner; không cài lại Docker |
| Port already allocated | `ss -ltn`, đổi port LapStore/tunnel; giữ nguyên dịch vụ khác |
| MySQL access denied sau sửa .env | Volume cũ giữ password cũ; sửa .env không tự đổi tài khoản MySQL |
| Registry x509/unknown authority | Hostname, `/etc/hosts`, CA của host và Docker |
| Delivery queued | Runner Idle và đủ labels; CI đạt; ENABLE_DELIVERY=true |
| `exec format error` | Kiến trúc image build không khớp CPU homeserver |
| Không có previous image để rollback | Cần ít nhất hai release khác digest thành công và còn image local |
| Runtime config/schema khác source | Có thay đổi hạ tầng/schema; cần migration riêng, không bỏ kiểm tra bằng cách copy đè |
| Không có số liệu container | Kiểm tra quyền/mount/cgroup/data root và series thực tế, không chỉ target UP |
| Web lỗi trong lúc nâng cấp | Giữ log/state/CSV; kiểm tra bản đang phục vụ qua health release trước khi thao tác tiếp |
