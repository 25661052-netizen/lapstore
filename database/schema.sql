CREATE TABLE IF NOT EXISTS products (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  category VARCHAR(40) NOT NULL,
  quantity INT UNSIGNED NOT NULL DEFAULT 0,
  price DECIMAL(12,0) UNSIGNED NOT NULL,
  CHECK (quantity <= 1000000),
  CHECK (price <= 999999999)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Sản phẩm và mức giá minh họa cho bài lab, không phải báo giá bán hàng.
INSERT INTO products (name, category, quantity, price) VALUES
('LapBook Everyday 14', 'Học tập', 18, 12990000),
('LapBook Office 15', 'Văn phòng', 12, 16490000),
('LapBook Play 15', 'Gaming', 6, 24990000),
('LapBook Studio 16', 'Đồ họa', 8, 32990000),
('LapBook Air 14', 'Văn phòng', 20, 21990000),
('LapBook Pro 14', 'Đồ họa', 10, 27990000);
