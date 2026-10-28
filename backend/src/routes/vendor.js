import { Router } from 'express';
import { db } from '../db.js';
import {
  HttpError, auth, serializeOrder, serializeOrders, serializeOneShop, serializeMenuItem, NEXT_STATUS,
  localDate, isHHMM, requireInt,
} from '../util.js';

// หลังบ้านของ "ร้านค้า" — ทุก endpoint ผูกกับร้านของบัญชีที่ล็อกอิน
const r = Router();
r.use(auth('vendor'), async (req, _res, next) => {
  if (!req.user.shop_id) throw new HttpError(403, 'บัญชีนี้ยังไม่ได้ผูกกับร้านค้า');
  req.shop = await db.get('SELECT * FROM shops WHERE id = ?', req.user.shop_id);
  if (!req.shop) throw new HttpError(403, 'ไม่พบร้านของบัญชีนี้');
  next();
});

// ---------- ข้อมูลร้าน ----------
r.get('/shop', async (req, res) => res.json(await serializeOneShop(req.shop)));

r.patch('/shop', async (req, res) => {
  const b = req.body || {};
  const s = { ...req.shop };
  if (b.description !== undefined) s.description = String(b.description).slice(0, 300);
  if (b.is_open !== undefined) s.is_open = b.is_open ? 1 : 0;
  if (b.open_time !== undefined) { if (!isHHMM(b.open_time)) throw new HttpError(400, 'เวลาเปิดไม่ถูกต้อง'); s.open_time = b.open_time; }
  if (b.close_time !== undefined) { if (!isHHMM(b.close_time)) throw new HttpError(400, 'เวลาปิดไม่ถูกต้อง'); s.close_time = b.close_time; }
  if (b.prep_min !== undefined) s.prep_min = requireInt(b.prep_min, 'prep_min');
  if (b.prep_max !== undefined) s.prep_max = requireInt(b.prep_max, 'prep_max');
  if (s.open_time >= s.close_time) throw new HttpError(400, 'เวลาเปิดต้องก่อนเวลาปิด');
  if (s.prep_min < 0 || s.prep_max < s.prep_min) throw new HttpError(400, 'เวลารอไม่ถูกต้อง');
  await db.run(
    `UPDATE shops SET description=?, is_open=?, open_time=?, close_time=?, prep_min=?, prep_max=? WHERE id=?`,
    s.description, s.is_open, s.open_time, s.close_time, s.prep_min, s.prep_max, s.id,
  );
  res.json(await serializeOneShop(await db.get('SELECT * FROM shops WHERE id = ?', s.id)));
});

// ---------- ออเดอร์ ----------
// GET /vendor/orders?scope=active|today
r.get('/orders', async (req, res) => {
  const rows = req.query.scope === 'today'
    ? await db.all('SELECT * FROM orders WHERE shop_id = ? AND order_date = ? ORDER BY id DESC', req.shop.id, localDate())
    : await db.all(`SELECT * FROM orders WHERE shop_id = ? AND status IN ('pending','accepted','cooking','ready') ORDER BY id`, req.shop.id);
  res.json(await serializeOrders(rows));
});

// PATCH /vendor/orders/:id/status { status, reason? }
r.patch('/orders/:id/status', async (req, res) => {
  const o = await db.get('SELECT * FROM orders WHERE id = ? AND shop_id = ?', requireInt(req.params.id, 'id'), req.shop.id);
  if (!o) throw new HttpError(404, 'ไม่พบออเดอร์นี้');
  const { status, reason } = req.body || {};
  if (!NEXT_STATUS[o.status].includes(status)) throw new HttpError(409, `เปลี่ยนสถานะจาก ${o.status} เป็น ${status} ไม่ได้`);
  const col = { accepted: 'accepted_at', cooking: 'cooking_at', ready: 'ready_at', completed: 'completed_at', cancelled: 'cancelled_at' }[status];
  // WHERE status = เดิม กันกรณีลูกค้ายกเลิกพร้อมกันพอดี
  const info = await db.run(
    `UPDATE orders SET status = ?, ${col} = ?, cancel_reason = COALESCE(?, cancel_reason) WHERE id = ? AND status = ?`,
    status, new Date().toISOString(), status === 'cancelled' ? String(reason || 'ร้านยกเลิกออเดอร์') : null, o.id, o.status,
  );
  if (!info.changes) throw new HttpError(409, 'ออเดอร์นี้ถูกเปลี่ยนสถานะไปแล้ว กรุณารีเฟรช');
  res.json(await serializeOrder(await db.get('SELECT * FROM orders WHERE id = ?', o.id)));
});

// ---------- เมนู ----------
r.get('/menu', async (req, res) => {
  res.json((await db.all('SELECT * FROM menu_items WHERE shop_id = ? ORDER BY sort_order, id', req.shop.id)).map(serializeMenuItem));
});

function validateMenu(b, partial) {
  const out = {};
  if (b.name !== undefined || !partial) {
    if (!b.name || !String(b.name).trim()) throw new HttpError(400, 'กรุณากรอกชื่อเมนู');
    out.name = String(b.name).trim().slice(0, 80);
  }
  if (b.price !== undefined || !partial) {
    const p = Number(b.price);
    if (!Number.isInteger(p) || p < 0 || p > 10000) throw new HttpError(400, 'ราคาต้องเป็นจำนวนเต็ม 0-10000');
    out.price = p;
  }
  if (b.description !== undefined) out.description = String(b.description).slice(0, 200);
  if (b.is_available !== undefined) out.is_available = b.is_available ? 1 : 0;
  if (b.image_url !== undefined) out.image_url = b.image_url ? String(b.image_url) : null;
  if (b.sort_order !== undefined) out.sort_order = requireInt(b.sort_order, 'sort_order');
  return out;
}

r.post('/menu', async (req, res) => {
  const v = validateMenu(req.body || {}, false);
  const info = await db.run(
    `INSERT INTO menu_items (shop_id, name, description, price, is_available, image_url, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    req.shop.id, v.name, v.description ?? '', v.price, v.is_available ?? 1, v.image_url ?? null, v.sort_order ?? 0,
  );
  res.status(201).json(serializeMenuItem(await db.get('SELECT * FROM menu_items WHERE id = ?', info.lastInsertRowid)));
});

r.patch('/menu/:id', async (req, res) => {
  const id = requireInt(req.params.id, 'id');
  if (!(await db.get('SELECT 1 FROM menu_items WHERE id = ? AND shop_id = ?', id, req.shop.id))) throw new HttpError(404, 'ไม่พบเมนูนี้');
  const v = validateMenu(req.body || {}, true);
  const keys = Object.keys(v);
  if (keys.length) await db.run(`UPDATE menu_items SET ${keys.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`, ...keys.map((k) => v[k]), id);
  res.json(serializeMenuItem(await db.get('SELECT * FROM menu_items WHERE id = ?', id)));
});

r.delete('/menu/:id', async (req, res) => {
  const id = requireInt(req.params.id, 'id');
  if (!(await db.get('SELECT 1 FROM menu_items WHERE id = ? AND shop_id = ?', id, req.shop.id))) throw new HttpError(404, 'ไม่พบเมนูนี้');
  // ลบข้อมูลที่อ้างถึงเมนูนี้เอง (ไม่พึ่ง foreign key cascade ซึ่งอาจไม่เปิดบน Turso)
  await db.batch([
    { sql: 'DELETE FROM favorites WHERE menu_item_id = ?', args: [id] },
    { sql: 'UPDATE order_items SET menu_item_id = NULL WHERE menu_item_id = ?', args: [id] },
    { sql: 'DELETE FROM menu_items WHERE id = ?', args: [id] },
  ]);
  res.json({ ok: true });
});

// ---------- สรุปยอดวันนี้ ----------
r.get('/summary', async (req, res) => {
  const today = localDate();
  const [s, top] = await Promise.all([
    db.get(
      `SELECT COUNT(*) AS orders,
              COALESCE(SUM(CASE WHEN status != 'cancelled' THEN total END), 0) AS revenue,
              SUM(status = 'cancelled') AS cancelled,
              SUM(status IN ('pending','accepted','cooking')) AS in_progress
       FROM orders WHERE shop_id = ? AND order_date = ?`,
      req.shop.id, today,
    ),
    db.all(
      `SELECT oi.name, SUM(oi.qty) AS qty, SUM(oi.qty * oi.price) AS revenue
       FROM order_items oi JOIN orders o ON o.id = oi.order_id
       WHERE o.shop_id = ? AND o.order_date = ? AND o.status != 'cancelled'
       GROUP BY oi.name ORDER BY qty DESC LIMIT 5`,
      req.shop.id, today,
    ),
  ]);
  res.json({ date: today, orders: s.orders, revenue: s.revenue, cancelled: s.cancelled || 0, in_progress: s.in_progress || 0, top_items: top });
});

export default r;
