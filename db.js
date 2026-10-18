const mysql = require('mysql2/promise');

// Ba giá trị cố định theo thiết kế demo. Mật khẩu lấy từ Compose.
const pool = mysql.createPool({
  host: 'db', database: 'lapstore', user: 'lapstore',
  password: process.env.DB_PASSWORD,
  waitForConnections: true, connectionLimit: 10,
  queueLimit: 50, connectTimeout: 5000, decimalNumbers: true
});

const columns = 'id, name, category, quantity, price';
module.exports = {
  async health() { await pool.query('SELECT id FROM products LIMIT 1'); },
  async list() {
    const [rows] = await pool.query(`SELECT ${columns} FROM products ORDER BY id DESC`);
    return rows;
  },
  async get(id) {
    const [rows] = await pool.execute(`SELECT ${columns} FROM products WHERE id = ?`, [id]);
    return rows[0] || null;
  },
  async create(p) {
    const [result] = await pool.execute(
      'INSERT INTO products (name, category, quantity, price) VALUES (?, ?, ?, ?)',
      [p.name, p.category, p.quantity, p.price]);
    return this.get(result.insertId);
  },
  async update(id, p) {
    const [result] = await pool.execute(
      'UPDATE products SET name = ?, category = ?, quantity = ?, price = ? WHERE id = ?',
      [p.name, p.category, p.quantity, p.price, id]);
    return result.affectedRows ? this.get(id) : null;
  },
  async remove(id) {
    const [result] = await pool.execute('DELETE FROM products WHERE id = ?', [id]);
    return result.affectedRows > 0;
  },
  close() { return pool.end(); }
};
