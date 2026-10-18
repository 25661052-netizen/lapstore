const express = require('express');
const path = require('node:path');

const categories = ['Văn phòng', 'Học tập', 'Đồ họa', 'Gaming'];

function validateProduct(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return 'Dữ liệu sản phẩm không hợp lệ.';
  if (typeof body.name !== 'string' || !body.name.trim() || body.name.trim().length > 120)
    return 'Tên sản phẩm phải có từ 1 đến 120 ký tự.';
  if (!categories.includes(body.category)) return 'Danh mục không hợp lệ.';
  if (!Number.isInteger(body.quantity) || body.quantity < 0 || body.quantity > 1000000)
    return 'Số lượng phải là số nguyên từ 0 đến 1.000.000.';
  // Giá VND nguyên, tránh sai số tiền tệ trên JavaScript.
  if (!Number.isSafeInteger(body.price) || body.price < 0 || body.price > 999999999)
    return 'Giá phải là số nguyên từ 0 đến 999.999.999 đồng.';
  return null;
}

function createApp(repository) {
  const app = express();
  app.disable('x-powered-by');
  app.use((req, res, next) => {
    res.set({
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'same-origin',
      'Content-Security-Policy': "default-src 'self'; img-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
    });
    if (req.path.startsWith('/api/') || req.path === '/health') res.set('Cache-Control', 'no-store');
    next();
  });
  app.use(express.json({ limit: '16kb' }));
  app.get('/health', async (_req, res) => {
    try {
      await repository.health();
      res.json({ status: 'ok', database: 'connected', release: process.env.APP_VERSION || 'local' });
    } catch {
      res.status(503).json({ status: 'unhealthy', database: 'unavailable' });
    }
  });
  app.get('/api/products', async (_req, res) => res.json(await repository.list()));
  app.param('id', (req, res, next, value) => {
    const id = Number(value);
    if (!/^\d+$/.test(value) || !Number.isSafeInteger(id) || id < 1)
      return res.status(400).json({ error: 'ID không hợp lệ.' });
    req.productId = id;
    next();
  });
  app.get('/api/products/:id', async (req, res) => {
    const product = await repository.get(req.productId);
    if (!product) return res.status(404).json({ error: 'Không tìm thấy sản phẩm.' });
    res.json(product);
  });
  app.post('/api/products', async (req, res) => {
    const error = validateProduct(req.body);
    if (error) return res.status(400).json({ error });
    const product = await repository.create({ ...req.body, name: req.body.name.trim() });
    res.status(201).location(`/api/products/${product.id}`).json(product);
  });
  app.put('/api/products/:id', async (req, res) => {
    const error = validateProduct(req.body);
    if (error) return res.status(400).json({ error });
    const product = await repository.update(req.productId, { ...req.body, name: req.body.name.trim() });
    if (!product) return res.status(404).json({ error: 'Không tìm thấy sản phẩm.' });
    res.json(product);
  });
  app.delete('/api/products/:id', async (req, res) => {
    if (!await repository.remove(req.productId)) return res.status(404).json({ error: 'Không tìm thấy sản phẩm.' });
    res.status(204).end();
  });
  app.use('/api', (_req, res) => res.status(404).json({ error: 'API không tồn tại.' }));
  app.use(express.static(path.join(__dirname, 'frontend')));
  app.use((_req, res) => res.status(404).send('Không tìm thấy trang.'));
  app.use((error, _req, res, _next) => {
    if (error.type === 'entity.parse.failed') return res.status(400).json({ error: 'JSON không hợp lệ.' });
    if (error.type === 'entity.too.large') return res.status(413).json({ error: 'Dữ liệu quá lớn.' });
    console.error('Request failed:', error.code || error.name);
    res.status(500).json({ error: 'Không thể xử lý yêu cầu. Vui lòng thử lại.' });
  });
  return app;
}

if (require.main === module) {
  const db = require('./db');
  const server = createApp(db).listen(3000, '0.0.0.0', () => console.log('LapStore listening on :3000'));
  let stopping = false;
  const stop = () => {
    if (stopping) return;
    stopping = true;
    server.close(async () => { await db.close(); process.exit(0); });
    setTimeout(() => process.exit(1), 10000).unref();
  };
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
}
module.exports = { createApp, validateProduct, categories };
