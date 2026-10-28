import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { db } from '../db.js';
import {
  HttpError, auth, serializeShops, serializeOneShop, serializeOrders, publicUser, publicUsers, localDate, isHHMM, requireInt,
} from '../util.js';

// หลังบ้านของ "แอดมินศูนย์อาหาร"
const r = Router();
r.use(auth('admin'));

// ---------- ภาพรวม ----------
r.get('/summary', async (req, res) => {
  const days = Math.min(Math.max(Number(req.query.days) || 7, 1), 60);
  const today = localDate();
  const dates = [];
  for (let i = days - 1; i >= 0; i--) dates.push(localDate(new Date(Date.now() - i * 86400000)));

  const [daily, byShop, todayRow, topItems, shopCounts, students] = await Promise.all([
    db.all(
      `SELECT order_date AS date, COUNT(*) AS orders, COALESCE(SUM(total), 0) AS revenue
       FROM orders WHERE order_date >= ? AND status != 'cancelled' GROUP BY order_date`,
      dates[0],
    ),
    db.all(
      `SELECT s.id, s.code, s.name, COUNT(o.id) AS orders, COALESCE(SUM(o.total), 0) AS revenue
       FROM shops s LEFT JOIN orders o ON o.shop_id = s.id AND o.order_date >= ? AND o.status != 'cancelled'
       GROUP BY s.id ORDER BY revenue DESC`,
      dates[0],
    ),
    db.get(
      `SELECT COUNT(*) AS orders, COALESCE(SUM(CASE WHEN status != 'cancelled' THEN total END), 0) AS revenue,
              SUM(status IN ('pending','accepted','cooking','ready')) AS active
       FROM orders WHERE order_date = ?`,
      today,
    ),
    db.all(
      `SELECT oi.name, s.name AS shop_name, SUM(oi.qty) AS qty
       FROM order_items oi JOIN orders o ON o.id = oi.order_id JOIN shops s ON s.id = o.shop_id
       WHERE o.order_date >= ? AND o.status != 'cancelled'
       GROUP BY oi.name, s.id ORDER BY qty DESC LIMIT 5`,
      dates[0],
    ),
    db.get('SELECT COUNT(*) AS shops, COALESCE(SUM(is_open = 1), 0) AS shops_open FROM shops'),
    db.get(`SELECT COUNT(*) AS n FROM users WHERE role = 'student'`),
  ]);
  const byDate = Object.fromEntries(daily.map((d) => [d.date, d]));

  res.json({
    today: { date: today, orders: todayRow.orders, revenue: todayRow.revenue, active: todayRow.active || 0 },
    counts: { shops: shopCounts.shops, shops_open: shopCounts.shops_open, students: students.n },
    daily: dates.map((d) => ({ date: d, orders: byDate[d]?.orders || 0, revenue: byDate[d]?.revenue || 0 })),
    by_shop: byShop,
    top_items: topItems,
  });
});

// ---------- ร้านค้า ----------
function validateShop(b, partial) {
  const out = {};
  const str = (k, max, required) => {
    if (b[k] === undefined) { if (required && !partial) throw new HttpError(400, `กรุณากรอก ${k}`); return; }
    const v = String(b[k]).trim();
    if (required && !v) throw new HttpError(400, `กรุณากรอก ${k}`);
    out[k] = v.slice(0, max);
  };
  str('name', 80, true);
  str('code', 2, true);
  str('category', 40, true);
  str('description', 300, false);
  if (out.code) { out.code = out.code.toUpperCase(); if (!/^[A-Z]{1,2}$/.test(out.code)) throw new HttpError(400, 'รหัสคิวต้องเป็นตัวอักษรอังกฤษ 1-2 ตัว'); }
  for (const k of ['open_time', 'close_time']) {
    if (b[k] !== undefined) { if (!isHHMM(b[k])) throw new HttpError(400, `${k} ต้องเป็นรูปแบบ HH:MM`); out[k] = b[k]; }
  }
  for (const k of ['prep_min', 'prep_max']) if (b[k] !== undefined) out[k] = requireInt(b[k], k);
  if (b.is_open !== undefined) out.is_open = b.is_open ? 1 : 0;
  if (b.image_url !== undefined) out.image_url = b.image_url ? String(b.image_url) : null;
  return out;
}

r.get('/shops', async (_req, res) => {
  const [shops, menuCounts, owners] = await Promise.all([
    db.all('SELECT * FROM shops ORDER BY code'),
    db.all('SELECT shop_id, COUNT(*) AS n FROM menu_items GROUP BY shop_id'),
    db.all(`SELECT id, username, name, shop_id FROM users WHERE role = 'vendor' AND shop_id IS NOT NULL`),
  ]);
  const menuBy = new Map(menuCounts.map((m) => [m.shop_id, m.n]));
  const serialized = await serializeShops(shops);
  res.json(serialized.map((s) => ({
    ...s,
    menu_count: menuBy.get(s.id) ?? 0,
    owners: owners.filter((o) => o.shop_id === s.id).map(({ id, username, name }) => ({ id, username, name })),
  })));
});

r.post('/shops', async (req, res) => {
  const v = validateShop(req.body || {}, false);
  if (await db.get('SELECT 1 FROM shops WHERE code = ?', v.code)) throw new HttpError(409, `รหัสคิว ${v.code} ถูกใช้แล้ว`);
  const keys = Object.keys(v);
  const info = await db.run(`INSERT INTO shops (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`, ...keys.map((k) => v[k]));
  res.status(201).json(await serializeOneShop(await db.get('SELECT * FROM shops WHERE id = ?', info.lastInsertRowid)));
});

r.patch('/shops/:id', async (req, res) => {
  const id = requireInt(req.params.id, 'id');
  if (!(await db.get('SELECT 1 FROM shops WHERE id = ?', id))) throw new HttpError(404, 'ไม่พบร้านนี้');
  const v = validateShop(req.body || {}, true);
  if (v.code && await db.get('SELECT 1 FROM shops WHERE code = ? AND id != ?', v.code, id)) throw new HttpError(409, `รหัสคิว ${v.code} ถูกใช้แล้ว`);
  const keys = Object.keys(v);
  if (keys.length) await db.run(`UPDATE shops SET ${keys.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`, ...keys.map((k) => v[k]), id);
  res.json(await serializeOneShop(await db.get('SELECT * FROM shops WHERE id = ?', id)));
});

r.delete('/shops/:id', async (req, res) => {
  const id = requireInt(req.params.id, 'id');
  if (await db.get('SELECT 1 FROM orders WHERE shop_id = ? LIMIT 1', id)) {
    throw new HttpError(409, 'ร้านนี้มีประวัติออเดอร์แล้ว ลบไม่ได้ — ให้ปิดร้านแทน');
  }
  if (!(await db.get('SELECT 1 FROM shops WHERE id = ?', id))) throw new HttpError(404, 'ไม่พบร้านนี้');
  // ลบ/ปลดข้อมูลที่ผูกกับร้านเอง (ไม่พึ่ง foreign key cascade)
  await db.batch([
    { sql: 'DELETE FROM favorites WHERE menu_item_id IN (SELECT id FROM menu_items WHERE shop_id = ?)', args: [id] },
    { sql: 'DELETE FROM menu_items WHERE shop_id = ?', args: [id] },
    { sql: 'UPDATE users SET shop_id = NULL WHERE shop_id = ?', args: [id] },
    { sql: 'DELETE FROM shops WHERE id = ?', args: [id] },
  ]);
  res.json({ ok: true });
});

// ---------- ผู้ใช้ ----------
r.get('/users', async (req, res) => {
  const role = String(req.query.role || '');
  const q = String(req.query.q || '').trim();
  const where = [];
  const params = [];
  if (['student', 'vendor', 'admin'].includes(role)) { where.push('role = ?'); params.push(role); }
  if (q) { where.push('(username LIKE ? OR name LIKE ? OR email LIKE ?)'); params.push(`%${q}%`, `%${q}%`, `%${q}%`); }
  const rows = await db.all(`SELECT * FROM users ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY role, username LIMIT 500`, ...params);
  res.json(await publicUsers(rows));
});

async function checkShopForRole(role, shopId) {
  if (role !== 'vendor') return null;
  const id = requireInt(shopId, 'shop_id');
  if (!(await db.get('SELECT 1 FROM shops WHERE id = ?', id))) throw new HttpError(400, 'กรุณาเลือกร้านของบัญชีร้านค้า');
  return id;
}

r.post('/users', async (req, res) => {
  const { username, name, password, role = 'student', shop_id, faculty } = req.body || {};
  if (!username || !name || !password) throw new HttpError(400, 'กรุณากรอกชื่อผู้ใช้ ชื่อ และรหัสผ่าน');
  if (!['student', 'vendor', 'admin'].includes(role)) throw new HttpError(400, 'role ไม่ถูกต้อง');
  if (String(password).length < 4) throw new HttpError(400, 'รหัสผ่านต้องมีอย่างน้อย 4 ตัวอักษร');
  if (await db.get('SELECT 1 FROM users WHERE username = ?', String(username).trim())) throw new HttpError(409, 'ชื่อผู้ใช้นี้มีอยู่แล้ว');
  const info = await db.run(
    'INSERT INTO users (username, name, password_hash, role, shop_id, faculty) VALUES (?, ?, ?, ?, ?, ?)',
    String(username).trim(), String(name).trim(), bcrypt.hashSync(String(password), 10), role,
    await checkShopForRole(role, shop_id), faculty ? String(faculty) : 'SIET - KMITL',
  );
  res.status(201).json(await publicUser(await db.get('SELECT * FROM users WHERE id = ?', info.lastInsertRowid)));
});

r.patch('/users/:id', async (req, res) => {
  const id = requireInt(req.params.id, 'id');
  const u = await db.get('SELECT * FROM users WHERE id = ?', id);
  if (!u) throw new HttpError(404, 'ไม่พบผู้ใช้นี้');
  const b = req.body || {};
  const role = b.role ?? u.role;
  if (!['student', 'vendor', 'admin'].includes(role)) throw new HttpError(400, 'role ไม่ถูกต้อง');
  if (id === req.user.id && (role !== 'admin' || b.is_active === false)) throw new HttpError(400, 'ไม่สามารถลดสิทธิ์หรือระงับบัญชีตัวเองได้');
  const next = {
    name: b.name !== undefined ? String(b.name).trim() : u.name,
    role,
    shop_id: role === 'vendor' ? await checkShopForRole(role, b.shop_id ?? u.shop_id) : null,
    faculty: b.faculty !== undefined ? String(b.faculty) : u.faculty,
    is_active: b.is_active !== undefined ? (b.is_active ? 1 : 0) : u.is_active,
    password_hash: b.password ? bcrypt.hashSync(String(b.password), 10) : u.password_hash,
  };
  if (!next.name) throw new HttpError(400, 'กรุณากรอกชื่อ');
  await db.run('UPDATE users SET name=?, role=?, shop_id=?, faculty=?, is_active=?, password_hash=? WHERE id=?',
    next.name, next.role, next.shop_id, next.faculty, next.is_active, next.password_hash, id);
  res.json(await publicUser(await db.get('SELECT * FROM users WHERE id = ?', id)));
});

// ---------- ออเดอร์ทั้งหมด ----------
r.get('/orders', async (req, res) => {
  const where = [];
  const params = [];
  if (req.query.shop_id) { where.push('shop_id = ?'); params.push(requireInt(req.query.shop_id, 'shop_id')); }
  if (req.query.status) { where.push('status = ?'); params.push(String(req.query.status)); }
  if (req.query.date) { where.push('order_date = ?'); params.push(String(req.query.date)); }
  const rows = await db.all(`SELECT * FROM orders ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY id DESC LIMIT 200`, ...params);
  res.json(await serializeOrders(rows));
});

export default r;
