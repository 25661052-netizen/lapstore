const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createApp, validateProduct } = require('../app');
const valid = { name: 'Laptop test', category: 'Văn phòng', quantity: 2, price: 21000000 };

test('sản phẩm hợp lệ, bao gồm tồn kho và giá bằng 0', () => {
  assert.equal(validateProduct(valid), null);
  assert.equal(validateProduct({ ...valid, quantity: 0, price: 0 }), null);
});
for (const [name, value] of Object.entries({
  'thiếu tên': { ...valid, name: ' ' }, 'tên quá dài': { ...valid, name: 'a'.repeat(121) },
  'danh mục sai': { ...valid, category: 'server' }, 'tồn kho âm': { ...valid, quantity: -1 },
  'tồn kho lẻ': { ...valid, quantity: 1.5 }, 'giá âm': { ...valid, price: -1 },
  'giá là chuỗi': { ...valid, price: '100' }, 'giá quá lớn': { ...valid, price: 1e12 },
  'body rỗng': null, 'body là mảng': []
})) test('từ chối ' + name, () => assert.equal(typeof validateProduct(value), 'string'));

test('HTTP: 503 khi database lỗi; không lộ lỗi SQL ra client', async (t) => {
  const repo = { health: async () => { throw new Error('private connection string'); }, list: async () => { throw new Error('private SQL'); } };
  const server = createApp(repo).listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const health = await fetch(base + '/health'); assert.equal(health.status, 503);
  assert.equal((await health.json()).database, 'unavailable');
  const list = await fetch(base + '/api/products'); assert.equal(list.status, 500);
  assert.ok(!(await list.text()).includes('private'));
});
test('HTTP: ID sai, JSON sai và dữ liệu sai không được ghi vào repository', async (t) => {
  let writes = 0;
  const server = createApp({ create: async () => { writes++; } }).listen(0, '127.0.0.1');
  await once(server, 'listening'); t.after(() => new Promise((resolve) => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(base + '/api/products/1%20OR%201=1')).status, 400);
  assert.equal((await fetch(base + '/api/products', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{oops' })).status, 400);
  assert.equal((await fetch(base + '/api/products', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })).status, 400);
  assert.equal(writes, 0);
  assert.equal((await fetch(base + '/api/missing')).status, 404);
  const page = await fetch(base); assert.equal(page.status, 200);
  assert.match(page.headers.get('content-security-policy'), /frame-ancestors 'none'/);
  assert.ok((await page.text()).includes('LapStore'));
});
