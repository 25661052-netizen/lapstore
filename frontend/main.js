'use strict';
const $ = (selector) => document.querySelector(selector);
const state = { products: [], category: 'all', query: '', sort: 'new', deleteId: null, cart: {} };
try { const c = JSON.parse(localStorage.getItem('lapstore-cart') || '{}'); if (c && typeof c === 'object' && !Array.isArray(c)) state.cart = c; } catch { /* Storage may be disabled. */ }
const money = (n) => new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND', maximumFractionDigits: 0 }).format(n);
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const imageFor = (p) => '/assets/laptop-' + ({ 'Gaming': 'dark', 'Đồ họa': 'purple', 'Học tập': 'sand', 'Văn phòng': 'blue' }[p.category] || 'blue') + '.svg';
let toastTimer;
function toast(message) { $('#toast').textContent = message; $('#toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 3200); }
async function api(path = '', options = {}) {
  const response = await fetch('/api/products' + path, { ...options, headers: { 'Content-Type': 'application/json', ...options.headers }, signal: AbortSignal.timeout(10000) });
  if (!response.ok) { const body = await response.json().catch(() => ({})); throw new Error(body.error || 'Không thể kết nối cửa hàng.'); }
  return response.status === 204 ? null : response.json();
}
async function loadProducts() {
  try { state.products = await api(); renderProducts(); renderAdmin(); syncCart(); }
  catch (error) { $('#products').innerHTML = '<div class="empty">Không tải được sản phẩm. Hãy kiểm tra ứng dụng và database.<br><button class="button secondary" id="retry">Thử lại</button></div>'; $('#result-count').textContent = 'Mất kết nối'; $('#retry').onclick = loadProducts; toast(error.message); }
}
function renderProducts() {
  const list = state.products.filter((p) => (state.category === 'all' || p.category === state.category) && p.name.toLocaleLowerCase('vi').includes(state.query.toLocaleLowerCase('vi')));
  list.sort((a, b) => state.sort === 'price-asc' ? a.price - b.price : state.sort === 'price-desc' ? b.price - a.price : state.sort === 'name' ? a.name.localeCompare(b.name, 'vi') : b.id - a.id);
  $('#result-count').textContent = list.length + ' sản phẩm';
  $('#products').innerHTML = list.length ? list.map((p) => `<article class="product-card"><button class="product-image" data-detail="${p.id}" aria-label="Xem ${escapeHtml(p.name)}"><span class="category-pill">${escapeHtml(p.category)}</span><img src="${imageFor(p)}" alt="Minh họa ${escapeHtml(p.name)}" loading="lazy"></button><div class="product-info"><span class="product-category">LAPBOOK COLLECTION</span><button class="product-title" data-detail="${p.id}">${escapeHtml(p.name)}</button><span class="stock ${p.quantity ? '' : 'out'}">${p.quantity ? 'Còn ' + p.quantity + ' sản phẩm' : 'Tạm hết hàng'}</span><div class="price-row"><strong class="price">${money(p.price)}</strong><button class="add-cart" data-add="${p.id}" aria-label="Thêm ${escapeHtml(p.name)} vào giỏ" ${p.quantity ? '' : 'disabled'}>+</button></div></div></article>`).join('') : '<div class="empty">Chưa có laptop phù hợp. Thử danh mục hoặc từ khóa khác.</div>';
}
function renderAdmin() {
  $('#stat-products').textContent = state.products.length;
  $('#stat-stock').textContent = state.products.reduce((sum, p) => sum + p.quantity, 0);
  $('#stat-empty').textContent = state.products.filter((p) => !p.quantity).length;
  $('#admin-rows').innerHTML = state.products.length ? state.products.map((p) => `<tr><td>#${p.id}</td><td><strong>${escapeHtml(p.name)}</strong></td><td>${escapeHtml(p.category)}</td><td>${p.quantity}</td><td>${money(p.price)}</td><td><button class="table-action" data-edit="${p.id}">Sửa</button><button class="table-action delete" data-delete="${p.id}">Xóa</button></td></tr>`).join('') : '<tr><td colspan="6">Chưa có sản phẩm. Thêm laptop đầu tiên.</td></tr>';
}
function chooseCategory(category) { state.category = category; document.querySelectorAll('.filter').forEach((button) => { const active = button.dataset.category === category; button.classList.toggle('active', active); button.setAttribute('aria-pressed', String(active)); }); renderProducts(); }
function viewAdmin(admin) { $('#shop-view').hidden = admin; $('#admin-view').hidden = !admin; $('#shop-nav').classList.toggle('active', !admin); $('#admin-nav').classList.toggle('active', admin); window.scrollTo({ top: 0 }); }
function editProduct(id) {
  const p = state.products.find((item) => item.id === id);
  $('#product-form').reset(); $('#form-error').textContent = '';
  $('#product-id').value = p?.id || ''; $('#form-title').textContent = p ? 'Sửa sản phẩm' : 'Thêm sản phẩm';
  if (p) { $('#product-name').value = p.name; $('#product-category').value = p.category; $('#product-quantity').value = p.quantity; $('#product-price').value = p.price; }
  $('#product-dialog').showModal();
}
function syncCart() {
  for (const [id, count] of Object.entries(state.cart)) { const p = state.products.find((item) => item.id === Number(id)); if (!p || !p.quantity || !Number.isSafeInteger(count) || count < 1) delete state.cart[id]; else state.cart[id] = Math.min(count, p.quantity); }
  try { localStorage.setItem('lapstore-cart', JSON.stringify(state.cart)); } catch { /* Cart still works in memory. */ }
  $('#cart-count').textContent = Object.values(state.cart).reduce((sum, n) => sum + n, 0);
  let total = 0;
  $('#cart-items').innerHTML = Object.entries(state.cart).map(([id, count]) => { const p = state.products.find((item) => item.id === Number(id)); total += p.price * count; return `<div class="cart-item"><img src="${imageFor(p)}" alt=""><div><strong>${escapeHtml(p.name)}</strong><p>${money(p.price)}</p><div class="cart-controls"><button data-minus="${id}" aria-label="Giảm số lượng">−</button><span>${count}</span><button data-add="${id}" aria-label="Tăng số lượng">+</button></div></div><button class="icon-button" data-remove="${id}" aria-label="Xóa khỏi giỏ">×</button></div>`; }).join('') || '<p class="empty">Giỏ hàng đang trống.<br>Khám phá một chiếc laptop bạn thích.</p>';
  $('#cart-total').textContent = money(total);
}
function addCart(id) { const p = state.products.find((item) => item.id === id); if (!p || !p.quantity) return; if ((state.cart[id] || 0) >= p.quantity) return toast('Đã đạt số lượng tồn kho.'); state.cart[id] = (state.cart[id] || 0) + 1; syncCart(); toast('Đã thêm vào giỏ hàng.'); }
function showDetail(id) { const p = state.products.find((item) => item.id === id); if (!p) return; $('#detail-content').innerHTML = `<img class="detail-image" src="${imageFor(p)}" alt="Minh họa ${escapeHtml(p.name)}"><h2>${escapeHtml(p.name)}</h2><p class="muted">${escapeHtml(p.category)} · Mã sản phẩm #${p.id}</p><div class="detail-meta"><strong class="price">${money(p.price)}</strong><span class="stock ${p.quantity ? '' : 'out'}">${p.quantity ? 'Còn ' + p.quantity + ' sản phẩm' : 'Tạm hết hàng'}</span></div><button class="button primary full" data-add="${p.id}" ${p.quantity ? '' : 'disabled'}>Thêm vào giỏ hàng ＋</button>`; $('#detail-dialog').showModal(); }
$('#shop-nav').onclick = () => viewAdmin(false); $('#admin-nav').onclick = () => viewAdmin(true);
$('#add-product').onclick = () => editProduct(); $('#open-cart').onclick = () => { syncCart(); $('#cart-dialog').showModal(); };
$('#search').oninput = (e) => { state.query = e.target.value.trim(); renderProducts(); }; $('#sort').onchange = (e) => { state.sort = e.target.value; renderProducts(); };
$('#work-filter').onclick = () => { chooseCategory('Văn phòng'); $('#collection').scrollIntoView(); };
document.addEventListener('click', (e) => {
  const button = e.target.closest('button'); if (!button) return;
  if (button.classList.contains('close-dialog')) button.closest('dialog').close();
  if (button.dataset.category) chooseCategory(button.dataset.category);
  if (button.dataset.add) addCart(Number(button.dataset.add));
  if (button.dataset.detail) showDetail(Number(button.dataset.detail));
  if (button.dataset.edit) editProduct(Number(button.dataset.edit));
  if (button.dataset.delete) { state.deleteId = Number(button.dataset.delete); $('#delete-description').textContent = state.products.find((p) => p.id === state.deleteId).name; $('#delete-dialog').showModal(); }
  if (button.dataset.remove) { delete state.cart[button.dataset.remove]; syncCart(); }
  if (button.dataset.minus) { state.cart[button.dataset.minus]--; syncCart(); }
});
$('#product-form').onsubmit = async (e) => {
  e.preventDefault(); const id = $('#product-id').value;
  const body = { name: $('#product-name').value.trim(), category: $('#product-category').value, quantity: Number($('#product-quantity').value), price: Number($('#product-price').value) };
  $('#save-product').disabled = true; $('#form-error').textContent = '';
  try { await api(id ? '/' + id : '', { method: id ? 'PUT' : 'POST', body: JSON.stringify(body) }); $('#product-dialog').close(); await loadProducts(); toast(id ? 'Đã cập nhật sản phẩm.' : 'Đã thêm sản phẩm.'); }
  catch (error) { $('#form-error').textContent = error.message; }
  finally { $('#save-product').disabled = false; }
};
$('#confirm-delete').onclick = async () => { $('#confirm-delete').disabled = true; try { await api('/' + state.deleteId, { method: 'DELETE' }); $('#delete-dialog').close(); await loadProducts(); toast('Đã xóa sản phẩm.'); } catch (error) { toast(error.message); } finally { $('#confirm-delete').disabled = false; } };
loadProducts();
