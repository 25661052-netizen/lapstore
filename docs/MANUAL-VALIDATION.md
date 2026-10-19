# Kiểm chứng thủ công LapStore

Cập nhật: **19/10/2026**. Báo cáo ghi nhận kết quả trên homeserver và phân biệt
kết quả đã xác nhận với bước đang chạy. Cấu hình có trong source chưa được tính
là bằng chứng chạy thành công.

## Phạm vi hiện tại

Thực hiện thủ công cho ứng dụng frontend/API/MySQL, Docker, quét bảo mật,
private registry và quản lý phiên bản Git. Chỉ thay đổi file và tài nguyên Docker
thuộc project LapStore khi cần cho các nội dung này.

**Loại khỏi phạm vi:** CI/CD, self-hosted runner, monitoring và container backup.
Không chạy workflow, khởi tạo runner hoặc bật các stack bị loại. Nếu một bước
phụ thuộc các thành phần này, dừng và báo rõ phụ thuộc trước khi thực hiện.

Ứng dụng lab dùng host port `127.0.0.1:5200`, chuyển tới port `3000` trong
container. Private registry dùng `registry.lapstore.internal:5204`, bind loopback.
Không ghi tài khoản SSH, địa chỉ truy cập server hoặc thông tin đăng nhập trong
báo cáo này.

## Kết quả đã ghi nhận

| Nội dung | Trạng thái | Bằng chứng và giới hạn |
|---|---|---|
| Source được đưa lên GitHub | Đã xác nhận | Người dùng xác nhận push source; chưa kết luận branch/tag/release đã hoàn tất |
| Ứng dụng và MySQL trên stack lab | PASS | App public đã được cập nhật bằng digest, healthy; MySQL giữ nguyên container và dữ liệu |
| Unit/HTTP test | PASS — 13/13 | Output kiểm thử thực tế do người dùng cung cấp |
| API CRUD với MySQL thật | PASS — 1/1 | Kiểm thử tạo, đọc, sửa, xóa đạt; đây là một bài integration test |
| Persistence: `down` rồi `up` | PASS | Người dùng xác nhận dữ liệu không đổi; chưa đính kèm raw SQL vào đợt báo cáo này |
| Persistence: `down -v` rồi `up` | PASS | Output cho thấy sản phẩm demo mất, sáu sản phẩm seed có ID 1–6 xuất hiện lại |
| Tiếng Việt trong dữ liệu seed | Người dùng xác nhận đã sửa | Cần giữ kết quả kiểm tra dữ liệu sau sửa trong hồ sơ bàn giao |
| Registry TLS/auth và đăng nhập | PASS bước thiết lập | Audit trước ghi nhận HTTP `401` khi chưa xác thực, `200` khi xác thực đúng; kết quả push/pull được ghi riêng bên dưới |
| App chạy non-root | PASS — UID `1000` | Bằng chứng runtime đã ghi nhận trong audit trước, tách biệt với lần scan hiện tại |
| Docker network, volume và bind mount | PASS bước kiểm tra cấu hình runtime | Audit trước xác nhận network project, named volume MySQL và schema bind mount read-only |

`down` giữ named volume nên dữ liệu được gắn lại khi chạy tiếp. `down -v` xóa
named volume của stack lab; MySQL khởi tạo lại từ bind mount `database/schema.sql`.
Hai bài persistence đã hoàn tất, không cần lặp lại thao tác xóa volume để bổ sung
các bằng chứng còn thiếu.

## Đợt kiểm chứng bảo mật đang thực hiện

Thư mục trên server, tính từ root project:

```text
reports/manual-20261019T072949Z/
├── source/     # Snapshot source dùng để quét
├── cache/      # Cache riêng của Trivy cho đợt này
└── evidence/   # JSON, log và thông tin kiểm chứng
```

Các file của đợt này nằm trên server; đường dẫn trong báo cáo chưa có nghĩa là
đã tải hoặc đính kèm chúng vào source bàn giao.

Snapshot lấy nội dung hiện tại của các file Git đang theo dõi trong working tree.
Các file vận hành bị Git ignore như `.env`, note cá nhân, registry auth/certs
không được đưa vào snapshot. Cần đối chiếu danh sách source mới chưa được Git
theo dõi trước khi chốt phạm vi quét.

Scanner đã được ghi nhận chạy phiên bản **Trivy 0.76.0**, khóa bằng image digest:

```text
aquasec/trivy@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222
```

Phiên bản này được đối chiếu với [release official v0.76.0](https://github.com/aquasecurity/trivy/releases/tag/v0.76.0)
và [hướng dẫn image official](https://trivy.dev/docs/latest/getting-started/installation/).
**Chưa xác minh chữ ký mật mã Cosign/Sigstore** của scanner. Digest và phiên bản
được lưu để đối chiếu chính xác image đã dùng; bước xác minh chữ ký chưa được tính
là hoàn thành. Xem [quy trình xác minh của Trivy](https://trivy.dev/docs/latest/getting-started/signature-verification/).

Image baseline trước khi cập nhật public được xuất để quét theo Docker image/config ID:

```text
sha256:a7909c78cdaa4222fb1ba483914fa683e3cb03bd42de4a731e014703c758f8fc
```

Đây là image/config ID cục bộ. Manifest digest của ứng viên trong private registry
được ghi riêng bên dưới sau khi push/pull và đối chiếu. Trivy quét image archive
bằng `--input`, không được cấp Docker socket.

### Kết quả baseline và các image ứng viên

Source secret scan đã hoàn tất: JSON hợp lệ, **TOTAL_SECRETS = 0**, Trivy exit
**`0`**. Image baseline dựa trên **Debian 12.15** có **571 finding HIGH/CRITICAL**,
chưa đạt ngưỡng phát hành:

| Nhóm | HIGH | CRITICAL | Có bản sửa | Chưa có bản sửa | Tổng |
|---|---:|---:|---:|---:|---:|
| Gói hệ điều hành | 546 | 21 | 67 | 500 | 567 |
| npm đi kèm image | 4 | 0 | 3 | 1 | 4 |
| **Tổng** | **550** | **21** | **70** | **501** | **571** |

Không có finding trong dependency ứng dụng. Bốn finding npm ở bảng thuộc npm
đi kèm image; đây là kết quả quét gói phần mềm, không phải số CVE duy nhất.

Kết quả quét và kiểm thử các image đã build trong đợt này:

| Image | Docker image Size (byte) | HIGH | CRITICAL | Trivy exit | Kiểm thử runtime |
|---|---:|---:|---:|---:|---|
| Baseline `node:24`, Debian 12.15 | 1.152.982.514 | 550 | 21 | `1` | Image public trước khi cập nhật |
| Bookworm slim | 237.854.050 | 60 | 4 | `1` | 14/14 test PASS |
| Trixie slim | Chưa ghi nhận | 43 | 0 | `1` | Chưa kiểm thử runtime; cả 43 finding chưa có bản sửa |
| **Alpine 3.24.2 — ứng viên cuối** | **179.488.125** | **0** | **0** | **`0`** | **14/14 test PASS trên đúng image ứng viên** |

Bookworm và Trixie chưa đạt ngưỡng HIGH/CRITICAL. Alpine đã build, khởi động,
quét và kiểm thử thành công, các bước đều exit `0`; JSON Trivy hợp lệ xác nhận
0 HIGH và 0 CRITICAL ở các target OS và Node.js. Không dùng `--ignore-unfixed`
và không hạ severity để đạt kết quả này.

### Dockerfile cuối và bằng chứng ứng viên Alpine

Dockerfile hiện dùng base được khóa digest:

```text
node:24-alpine@sha256:44fce696f38ba8c987c4db89954051000bbd05ffd8d8659ba15ed4a8602e937f
```

Ứng viên giữ Dockerfile single-stage, đặt `NODE_ENV=production` và chạy bằng
`USER node`. File dependency được COPY trước để chạy `npm ci --omit=dev`; npm,
yarn và cache không cần cho lệnh khởi động `node app.js` được loại trong cùng
bước RUN. Sau đó chỉ COPY `app.js`, `db.js` và `frontend/` vào image. Cách này giữ
frontend/API chung một image và giảm các gói không cần thiết trong runtime.

Image/config ID của ứng viên Alpine đã được scan và test:

```text
sha256:b009ff89d16f41b031df8587b1744b2ce573f0519414768018db8c62cdc6d4ec
```

Kiểm thử dùng đúng image ID này và database riêng của stack `lapstore-verify`.
Kết quả: 14/14 test PASS, runtime UID `1000`, frontend `GET /` trả HTTP `200` và
nội dung chứa `LapStore`.

Alpine dùng musl; Debian dùng glibc theo [tài liệu Node image official](https://github.com/nodejs/docker-node/blob/main/README.md).
Việc chuyển sang musl đã được kiểm thử với dependency hiện tại của LapStore.
Dependency bổ sung sau này, đặc biệt module native, cần được kiểm thử lại.

Artifact dưới `reports/manual-20261019T072949Z/evidence/`:

| File | Nội dung |
|---|---|
| `candidate-trivy.json` | Kết quả Bookworm slim: 60 HIGH, 4 CRITICAL |
| `candidate-tests.log` | Kiểm thử Bookworm slim: 14/14 PASS |
| `trixie-trivy.json` | Kết quả Trixie slim: 43 HIGH, 0 CRITICAL |
| `alpine-trivy.json` | Kết quả Alpine: 0 HIGH, 0 CRITICAL |
| `alpine-tests.log` | Kiểm thử ứng viên Alpine: 14/14 PASS |
| `alpine-runtime.log` | Kiểm chứng runtime ứng viên, UID và frontend |
| `alpine-image.txt` | Thông tin image ứng viên Alpine |

### Private registry và kiểm chứng chạy bằng digest

Đã push image ứng viên với tag sau, exit `0`:

```text
registry.lapstore.internal:5204/lapstore/app:1.0.0-manual.1
```

Manifest digest ghi nhận từ registry:

```text
registry.lapstore.internal:5204/lapstore/app@sha256:0308fc09891f56add9646bcd53d25c1fd1991f24e2ea45cf7d00a00b00d0492d
```

Pull bằng digest hoàn tất với exit `0`; image/config ID sau pull khớp chính xác
ứng viên Alpine đã scan/test. Compose kiểm chứng riêng đã khởi động app bằng
digest này, image ID runtime khớp và health trả HTTP `200`. Bài kiểm tra chạy trên
host port `5205`, tách khỏi ứng dụng public ở port `5200`.

Cấu hình đăng nhập registry tạm thời đặt trong thư mục báo cáo của project đã
được logout sau khi sử dụng. Không ghi credentials trong báo cáo.

Artifact bổ sung dưới cùng thư mục `evidence/`:

| File | Nội dung |
|---|---|
| `registry-push.log`, `registry-push.exit` | Kết quả push, exit `0` |
| `registry-pull.log`, `registry-pull.exit` | Kết quả pull bằng digest, exit `0` |
| `registry-image-digest.txt` | Manifest digest của image trong registry |
| `digest-match.txt` | Đối chiếu image ID sau pull với ứng viên đã scan/test |
| `digest-up.log`, `digest-up.exit` | Khởi động Compose kiểm chứng bằng digest, exit `0` |
| `digest-runtime.txt` | Image ID runtime và kiểm tra health |

### Cập nhật ứng dụng public — đã hoàn tất

Người dùng đã đồng ý cập nhật. Ứng dụng ở host port `5200` hiện chạy manifest
digest `sha256:0308fc09891f56add9646bcd53d25c1fd1991f24e2ea45cf7d00a00b00d0492d`,
image/config ID khớp Alpine đã scan/test:

```text
sha256:b009ff89d16f41b031df8587b1744b2ce573f0519414768018db8c62cdc6d4ec
```

Chỉ đổi `APP_IMAGE` trong `.env`, giữ bản trước tại
`reports/manual-20261019T072949Z/public-before.env` với quyền `600`. Bản này chứa
cấu hình riêng và được loại khỏi bundle bàn giao. Lệnh cập nhật chỉ thay app:

```bash
docker compose -p lapstore-lab --env-file .env -f compose.yml \
  up -d --no-deps --no-build --pull never --wait app
```

Không sử dụng script CD. Sau cập nhật, app healthy, health và frontend trả HTTP
`200`; container ID MySQL không đổi. Hai JSON danh sách sản phẩm trước/sau khớp
chính xác, cùng sáu sản phẩm.

Đã đo HTTP tới `http://127.0.0.1:5200` trong lần cập nhật:

| Chỉ số | Kết quả |
|---|---|
| Khoảng đo theo giờ Việt Nam | 19/10/2026, 14:52:10.265809 → 14:53:51.192434 (`UTC+07:00`) |
| Timestamp UTC trong artifact | `2026-10-19T07:52:10.265809+00:00` → `2026-10-19T07:53:51.192434+00:00` |
| Thời lượng | 100,927 giây |
| Chu kỳ probe mục tiêu | 0,2 giây |
| Số mẫu | 505 |
| Mẫu thất bại | 2 |
| Khoảng cách lớn nhất giữa các mẫu thành công bao quanh lỗi | Khoảng 0,601 giây |

Kết quả ghi nhận gián đoạn khi thay container app trực tiếp, chưa đạt zero
downtime. Khoảng cách giữa mẫu thành công không phải thời lượng downtime chính
xác. Phép đo chỉ bao phủ localhost port `5200`; chưa đo xuyên qua Cloudflare,
chưa kiểm chứng blue-green hoặc hoàn tất đầy đủ Defense Drill 6.

Artifact public update dưới cùng thư mục `evidence/`:

| File | Nội dung |
|---|---|
| `public-update.log`, `public-update-status.txt` | Log và trạng thái cập nhật |
| `public-update-start.txt`, `public-update-end.txt` | Mốc bắt đầu/kết thúc cập nhật |
| `public-downtime.csv`, `public-downtime-summary.json` | Mẫu HTTP và thống kê |
| `public-products-before.json`, `public-products-after.json` | Đối chiếu sáu sản phẩm trước/sau |
| `public-db-check.txt` | Kiểm tra MySQL không bị thay container |
| `public-image-after.txt` | Image đang chạy sau cập nhật |
| `public-read-checks.txt`, `public-health-after.json` | Kiểm tra HTTP và health sau cập nhật |

| Hạng mục | Kết quả hiện tại | Điều kiện để chốt |
|---|---|---|
| Quét secret trong source snapshot | PASS — JSON hợp lệ, 0 secret, exit `0` | Phạm vi là source snapshot đã ghi nhận ở trên |
| Quét lỗ hổng image baseline | Chưa đạt — 571 HIGH/CRITICAL, exit `1` | Đã thay public sang Alpine đạt ngưỡng; baseline được giữ làm bằng chứng so sánh |
| Khắc phục và quét ứng viên | PASS — Alpine 0 HIGH, 0 CRITICAL, exit `0` | Có JSON hợp lệ; giữ nguyên ngưỡng và không bỏ qua finding chưa có bản sửa |
| Kiểm thử image ứng viên sau thay đổi | PASS — 14/14 | Đúng Alpine image ID, DB kiểm thử riêng và frontend HTTP `200` |
| Non-root | PASS — UID `1000` | Đã xác nhận ở audit trước và trên ứng viên Alpine |
| Network, named volume và bind mount | PASS từ audit trước | Giữ đúng phạm vi project khi kiểm thử hoặc chuyển image |
| Push/pull image ứng dụng qua registry | PASS — push/pull exit `0` | Đã lưu manifest digest; image ID sau pull khớp ứng viên đã scan/test |
| Chạy kiểm chứng riêng bằng manifest digest | PASS — image ID khớp, health HTTP `200` | Compose riêng ở host port `5205`, hoàn thành trước public update |
| Chuyển ứng dụng public sang image đã kiểm tra | PASS — đúng digest/image ID, healthy, frontend HTTP `200` | MySQL giữ nguyên container, sáu sản phẩm trước/sau khớp chính xác |
| Branch, SemVer, tag/release | Branch trên server `manual/image-hardening-20261019`; commit bàn giao được ghi tại `evidence/git-commit.txt`; image tag `1.0.0-manual.1` | Chưa push, tạo tag chính thức hoặc GitHub Release vì workflow hiện gắn main/tag |
| Defense Drill và downtime | Đã có phép đo public update: 505 mẫu, 2 lỗi; chưa hoàn tất sáu drill | Phạm vi localhost; chưa chứng minh zero downtime, blue-green hoặc đầy đủ Drill 6 |

## Dọn tài nguyên kiểm chứng

Đã dọn riêng stack `lapstore-verify`, gồm hai container, mạng Compose và volume
MySQL kiểm thử, bằng `down -v` sau khi đối chiếu nhãn project của volume. Lệnh trả
exit `0`; log tại `evidence/verify-cleanup.log`. Giữ nguyên `lapstore-lab`, private
registry, dữ liệu public và báo cáo; không dùng lệnh prune toàn host. Image cũ
vẫn được giữ để có thể quay lại khi cần.

## Quy tắc kết luận và bàn giao

- Chỉ đánh dấu PASS sau khi đối chiếu output thực tế. Số bài unit/API test là
  bằng chứng kiểm thử, không được cộng thành số yêu cầu đề bài hoàn thành.
- Exit `1` của Trivy có thể do finding hoặc lỗi scanner. Cần kiểm tra JSON/log;
  không hạ severity hoặc bỏ qua lỗi để ghi PASS.
- Ghi image ID, manifest digest, phiên bản scanner, exit code, thời điểm và tên
  artifact thực tế khi có kết quả. Security scan phản ánh database tại lần chạy.
- Hồ sơ bàn giao không chứa mật khẩu, private key hoặc dữ liệu đăng nhập. Các mục
  bị loại khỏi phạm vi và các mục chưa thực hiện phải giữ trạng thái rõ ràng.
