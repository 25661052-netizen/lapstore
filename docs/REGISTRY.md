# Registry riêng trên cùng Linux server với runner

Thiết kế tối giản: CNCF Distribution `registry:3`, TLS bằng CA nội bộ, bcrypt
htpasswd, named volume. Endpoint: `registry.lapstore.internal:5443`.
Bind localhost nên GitHub-hosted CI không truy cập trực tiếp; job Delivery chạy
trên self-hosted runner cùng máy sẽ nhận artifact image và push vào registry.

## Cài đặt

Chạy từ source trên server (user có quyền Docker):

```bash
bash registry/setup.sh
```

Nhập username/password; ghi lại mật khẩu để thêm GitHub Secret sau. Script không
in mật khẩu. Không commit `registry/auth` hoặc `registry/certs`.

Thêm một dòng vào `/etc/hosts` trên server bằng `sudoedit /etc/hosts`:

```text
127.0.0.1 registry.lapstore.internal
```

Trust CA cho Docker (chạy từ thư mục source):

```bash
sudo mkdir -p /etc/docker/certs.d/registry.lapstore.internal:5443
sudo cp registry/certs/ca.crt /etc/docker/certs.d/registry.lapstore.internal:5443/ca.crt
```

Trust CA cho host cũng cần để các Docker CLI dùng TLS trực tiếp:

```bash
# Ubuntu/Debian
sudo cp registry/certs/ca.crt /usr/local/share/ca-certificates/lapstore-registry.crt
sudo update-ca-certificates
# CentOS: thay hai dòng trên bằng:
# sudo cp registry/certs/ca.crt /etc/pki/ca-trust/source/anchors/lapstore-registry.crt
# sudo update-ca-trust
```

```bash
docker compose -p lapstore-registry -f registry/compose.yml up -d
curl --cacert registry/certs/ca.crt -I https://registry.lapstore.internal:5443/v2/
docker login registry.lapstore.internal:5443
```

Curl chưa đăng nhập trả **401** là đúng. `docker login` phải thành công sau khi nhập
tài khoản. Nếu Docker chưa nhận CA, khởi động lại Docker vào lúc không có dịch vụ
cần duy trì. Không đặt registry thành insecure chỉ để bỏ qua TLS.

Trong GitHub: `REGISTRY_HOST=registry.lapstore.internal:5443`,
`REGISTRY_IMAGE=registry.lapstore.internal:5443/lapstore/app`.
Username/password đưa vào Secrets, không vào source. Không cần tạo project Harbor
vì bản này dùng Distribution; namespace `lapstore/app` được tạo khi push.

## Quản lý image

- Push main dùng tag riêng theo commit/run/attempt, release dùng `vX.Y.Z`.
- Workflow kiểm tra tag release tồn tại trước khi push. Distribution bản đơn giản
  không cưỡng chế immutable tag phía server; không tự push đè tag đã phát hành.
- Container chạy bằng digest, nên việc đổi một tag không thay image đang chạy.
- Registry volume và runtime MySQL volume độc lập. Không chạy down -v trên registry
  nếu còn cần các image.
- Tài khoản htpasswd ở đây chưa tách quyền push/pull theo repository. Muốn RBAC
  nâng cao dùng Harbor hoặc token authorization service, không tuyên bố demo có RBAC.
- CA/certificate sinh có hạn 365 ngày; giữ khóa kín và chủ động gia hạn.

Tham khảo chính thức: https://distribution.github.io/distribution/about/deploying/
