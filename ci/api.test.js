const { test } = require('node:test');
const assert = require('node:assert/strict');
// Chỉ chạy trên stack kiểm thử riêng: test tạo và xóa một sản phẩm của chính nó.
const base = (process.env.BASE_URL || 'http://127.0.0.1:3000').replace(/\/$/, '');
const request = (path, method = 'GET', body) => fetch(base + path, {
  method, headers: { 'Content-Type': 'application/json' },
  body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(10000)
});
test('HTTP + MySQL: health, Create → Read → Update → Delete và dữ liệu sai', async () => {
  let id;
  try {
    const health = await request('/health'); assert.equal(health.status, 200);
    assert.equal((await health.json()).database, 'connected');
    const original = { name: 'CI laptop ' + Date.now(), category: 'Học tập', quantity: 3, price: 12000000 };
    const created = await request('/api/products', 'POST', original); assert.equal(created.status, 201);
    const p = await created.json(); id = p.id; assert.ok(Number.isInteger(id));
    assert.deepEqual(p, { id, ...original });
    const read = await request('/api/products/' + id); assert.equal(read.status, 200); assert.deepEqual(await read.json(), p);
    const updated = { ...original, name: "CI 'quoted' laptop", quantity: 7, price: 15000000 };
    const update = await request('/api/products/' + id, 'PUT', updated); assert.equal(update.status, 200); assert.deepEqual(await update.json(), { id, ...updated });
    const list = await request('/api/products'); assert.ok((await list.json()).some((item) => item.id === id && item.quantity === 7));
    const invalid = await request('/api/products/' + id, 'PUT', { ...updated, quantity: -1 }); assert.equal(invalid.status, 400);
    assert.equal((await (await request('/api/products/' + id)).json()).quantity, 7);
    assert.equal((await request('/api/products/' + id, 'DELETE')).status, 204);
    assert.equal((await request('/api/products/' + id)).status, 404);
    assert.equal((await request('/api/products/' + id, 'DELETE')).status, 404);
    id = undefined;
  } finally { if (id) await request('/api/products/' + id, 'DELETE'); }
});
