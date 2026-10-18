# Chứng minh persistence

Chỉ chạy trên stack local trong thư mục source `lapstore`, không dùng runtime
`lapstore-live`. Lệnh down -v thực sự xóa database của stack đang chọn.

## A. Chuẩn bị dữ liệu dễ nhận ra

```bash
docker compose up -d --build --wait --wait-timeout 240
```

Mở web localhost:3000 → Quản lý sản phẩm → thêm laptop tên **PERSISTENCE-DEMO-001**,
danh mục Học tập, số lượng 9, giá 12.345.000. Ghi lại ID và chụp màn hình.

Xem trực tiếp database, lệnh Bash/Git Bash/WSL:

```bash
docker compose exec db sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u lapstore lapstore -e "SELECT * FROM products;"'
```

Nếu đang dùng PowerShell và gặp lỗi dấu nháy, vào `docker compose exec db sh`,
rồi chạy bên trong container:

```sh
MYSQL_PWD="$MYSQL_PASSWORD" mysql -u lapstore lapstore -e 'SELECT * FROM products;'
exit
```

## B. Down/up không mất dữ liệu

```bash
docker compose down
docker compose up -d --wait --wait-timeout 240
```

Refresh web và query SQL lại. Laptop PERSISTENCE-DEMO-001 vẫn có đúng ID, số lượng,
giá. `down` xóa container và mạng của project, không xóa named volume mặc định.
`up` tạo container MySQL mới và gắn lại dữ liệu cũ từ volume.

## C. Down -v xóa dữ liệu

```bash
docker compose down -v
docker compose up -d --wait --wait-timeout 240
```

Laptop PERSISTENCE-DEMO-001 biến mất. Sáu laptop mẫu xuất hiện trở lại vì MySQL tạo
database trống và chạy schema.sql từ đầu. Không dùng sự có mặt của laptop mẫu để
kết luận dữ liệu cũ vẫn còn. Giỏ hàng trình duyệt không phải bằng chứng MySQL còn dữ liệu.

## D. Volume và bind mount

| Mount | Vai trò | Khi down -v |
|---|---|---|
| `mysql_data:/var/lib/mysql` | Named volume chứa bảng/dữ liệu thật | Bị xóa |
| `./database/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro` | File khởi tạo, bind mount chỉ đọc | File source còn nguyên |

Compose dùng project name để đặt tên volume. Nếu đổi thư mục hoặc dùng `-p` khác,
bạn có thể nhìn thấy database mới vì đang dùng volume khác; đó không phải down
làm mất volume cũ. Đổi password `.env` không tự đổi password trong database đã có.

Lưu bằng chứng trước/down-up/down-v-up vào một báo cáo riêng. Đây là thao tác người
học cần tự thực hiện, chưa được đánh dấu đạt trong ZIP.
