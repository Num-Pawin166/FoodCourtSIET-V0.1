import { Router } from 'express';
import { db } from '../db.js';
import {
  HttpError, auth, serializeOrder, serializeOrders, serializeOneShop, serializeMenuItem, NEXT_STATUS,
  localDate, isHHMM, requireInt,
} from '../util.js';
import { normalizePromptPayId } from '../promptpay.js';
import { rawImage, storeImage, sendImage, imageUrl } from '../images.js';

// หลังบ้านของ "ร้านค้า" — ทุก endpoint ผูกกับร้านของบัญชีที่ล็อกอิน
const r = Router();
r.use(auth('vendor'), async (req, _res, next) => {
  if (!req.user.shop_id) throw new HttpError(403, 'บัญชีนี้ยังไม่ได้ผูกกับร้านค้า');
  req.shop = await db.get('SELECT * FROM shops WHERE id = ?', req.user.shop_id);
  if (!req.shop) throw new HttpError(403, 'ไม่พบร้านของบัญชีนี้');
  next();
});

// ---------- ข้อมูลร้าน ----------
const shopForOwner = async (s) => ({ ...(await serializeOneShop(s)), promptpay_id: s.promptpay_id ?? null });

r.get('/shop', async (req, res) => res.json(await shopForOwner(req.shop)));

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
  if (b.promptpay_id !== undefined) {
    if (b.promptpay_id === null || String(b.promptpay_id).trim() === '') s.promptpay_id = null; // ปิดรับโอน
    else {
      s.promptpay_id = normalizePromptPayId(b.promptpay_id);
      if (!s.promptpay_id) throw new HttpError(400, 'หมายเลขพร้อมเพย์ต้องเป็นเบอร์มือถือ 10 หลัก หรือเลขบัตรประชาชน 13 หลัก');
    }
  }
  await db.run(
    `UPDATE shops SET description=?, is_open=?, open_time=?, close_time=?, prep_min=?, prep_max=?, promptpay_id=? WHERE id=?`,
    s.description, s.is_open, s.open_time, s.close_time, s.prep_min, s.prep_max, s.promptpay_id ?? null, s.id,
  );
  res.json(await shopForOwner(await db.get('SELECT * FROM shops WHERE id = ?', s.id)));
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

// รูปร้าน (แสดงในการ์ดร้านของแอปนักศึกษา) — เก็บเป็นรูปสาธารณะแบบเดียวกับรูปเมนู
r.post('/shop/image', rawImage, async (req, res) => {
  const imageId = await storeImage(req, 'menu');
  await db.batch([
    { sql: 'UPDATE shops SET image_url = ? WHERE id = ?', args: [imageUrl(imageId), req.shop.id] },
    ...imageDeletes(req.shop.image_url),
  ]);
  res.json(await shopForOwner(await db.get('SELECT * FROM shops WHERE id = ?', req.shop.id)));
});

r.delete('/shop/image', async (req, res) => {
  await db.batch([
    { sql: 'UPDATE shops SET image_url = NULL WHERE id = ?', args: [req.shop.id] },
    ...imageDeletes(req.shop.image_url),
  ]);
  res.json(await shopForOwner(await db.get('SELECT * FROM shops WHERE id = ?', req.shop.id)));
});

// ---------- การชำระเงิน ----------
// PATCH /vendor/orders/:id/payment { action: 'confirm' | 'reject', reason? }
r.patch('/orders/:id/payment', async (req, res) => {
  const o = await db.get('SELECT * FROM orders WHERE id = ? AND shop_id = ?', requireInt(req.params.id, 'id'), req.shop.id);
  if (!o) throw new HttpError(404, 'ไม่พบออเดอร์นี้');
  const { action, reason } = req.body || {};
  if (action === 'confirm') {
    // ยืนยันได้ทั้งออเดอร์โอน (หลังดูสลิป) และออเดอร์จ่ายที่ร้าน (รับเงินสดแล้ว)
    if (o.payment_status === 'paid') throw new HttpError(409, 'ยืนยันรับเงินไปแล้ว');
    await db.run(`UPDATE orders SET payment_status = 'paid', paid_at = ?, payment_note = NULL WHERE id = ?`, new Date().toISOString(), o.id);
  } else if (action === 'reject') {
    if (o.payment_method !== 'promptpay' || o.payment_status !== 'slip_uploaded') throw new HttpError(409, 'ไม่มีสลิปที่รอตรวจ');
    await db.run(`UPDATE orders SET payment_status = 'rejected', payment_note = ? WHERE id = ?`,
      String(reason || 'สลิปไม่ถูกต้อง กรุณาแนบใหม่').slice(0, 200), o.id);
  } else {
    throw new HttpError(400, 'action ต้องเป็น confirm หรือ reject');
  }
  res.json(await serializeOrder(await db.get('SELECT * FROM orders WHERE id = ?', o.id)));
});

r.get('/orders/:id/slip', async (req, res) => {
  const o = await db.get('SELECT slip_image_id FROM orders WHERE id = ? AND shop_id = ?', requireInt(req.params.id, 'id'), req.shop.id);
  if (!o?.slip_image_id) throw new HttpError(404, 'ไม่พบสลิป');
  await sendImage(res, o.slip_image_id, 'slip');
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
  const m = await db.get('SELECT image_url FROM menu_items WHERE id = ? AND shop_id = ?', id, req.shop.id);
  if (!m) throw new HttpError(404, 'ไม่พบเมนูนี้');
  // ลบข้อมูลที่อ้างถึงเมนูนี้เอง (ไม่พึ่ง foreign key cascade ซึ่งอาจไม่เปิดบน Turso)
  await db.batch([
    { sql: 'DELETE FROM favorites WHERE menu_item_id = ?', args: [id] },
    { sql: 'UPDATE order_items SET menu_item_id = NULL WHERE menu_item_id = ?', args: [id] },
    { sql: 'DELETE FROM menu_items WHERE id = ?', args: [id] },
    ...imageDeletes(m.image_url),
  ]);
  res.json({ ok: true });
});

// รูปเมนู: POST /vendor/menu/:id/image (body = ไฟล์รูป) / DELETE เพื่อลบรูป
const menuImageId = (url) => Number(/^\/api\/images\/(\d+)$/.exec(url || '')?.[1]) || null;
const imageDeletes = (url) => (menuImageId(url) ? [{ sql: `DELETE FROM images WHERE id = ? AND kind = 'menu'`, args: [menuImageId(url)] }] : []);

r.post('/menu/:id/image', rawImage, async (req, res) => {
  const id = requireInt(req.params.id, 'id');
  const m = await db.get('SELECT image_url FROM menu_items WHERE id = ? AND shop_id = ?', id, req.shop.id);
  if (!m) throw new HttpError(404, 'ไม่พบเมนูนี้');
  const imageId = await storeImage(req, 'menu');
  await db.batch([
    { sql: 'UPDATE menu_items SET image_url = ? WHERE id = ?', args: [imageUrl(imageId), id] },
    ...imageDeletes(m.image_url),
  ]);
  res.json(serializeMenuItem(await db.get('SELECT * FROM menu_items WHERE id = ?', id)));
});

r.delete('/menu/:id/image', async (req, res) => {
  const id = requireInt(req.params.id, 'id');
  const m = await db.get('SELECT image_url FROM menu_items WHERE id = ? AND shop_id = ?', id, req.shop.id);
  if (!m) throw new HttpError(404, 'ไม่พบเมนูนี้');
  await db.batch([
    { sql: 'UPDATE menu_items SET image_url = NULL WHERE id = ?', args: [id] },
    ...imageDeletes(m.image_url),
  ]);
  res.json(serializeMenuItem(await db.get('SELECT * FROM menu_items WHERE id = ?', id)));
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
