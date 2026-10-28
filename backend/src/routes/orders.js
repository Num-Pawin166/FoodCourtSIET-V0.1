import { Router } from 'express';
import { db, transaction } from '../db.js';
import {
  HttpError, auth, serializeOrder, serializeOrders, pickupSlots, isShopOpenNow, localDate, requireInt,
} from '../util.js';
import { promptPayPayload, maskPromptPayId } from '../promptpay.js';
import { rawImage, storeImage, sendImage } from '../images.js';

const r = Router();
r.use(auth('student', 'admin'));

// สร้างออเดอร์: { shop_id, items: [{ menu_item_id, qty }], pickup_time: "11:45", note, payment_method: "cash"|"promptpay" }
r.post('/', async (req, res) => {
  const { shop_id, items, pickup_time, note = '', payment_method = 'cash' } = req.body || {};
  const shopId = requireInt(shop_id, 'shop_id');
  if (!['cash', 'promptpay'].includes(payment_method)) throw new HttpError(400, 'วิธีชำระเงินไม่ถูกต้อง');
  if (!Array.isArray(items) || items.length === 0) throw new HttpError(400, 'ตะกร้าว่าง');
  if (String(note).length > 200) throw new HttpError(400, 'หมายเหตุยาวเกิน 200 ตัวอักษร');

  // รวมรายการซ้ำ และดึงราคาจากฐานข้อมูลเสมอ (ไม่เชื่อราคาจากแอป)
  const qtyById = new Map();
  for (const it of items) {
    const id = requireInt(it.menu_item_id, 'menu_item_id');
    const qty = requireInt(it.qty, 'qty');
    if (qty < 1 || qty > 20) throw new HttpError(400, 'จำนวนต่อเมนูต้องอยู่ระหว่าง 1-20');
    qtyById.set(id, (qtyById.get(id) || 0) + qty);
  }

  const orderId = await transaction(async (tx) => {
    const shop = await tx.get('SELECT * FROM shops WHERE id = ?', shopId);
    if (!shop) throw new HttpError(404, 'ไม่พบร้านนี้');
    if (!isShopOpenNow(shop)) throw new HttpError(409, 'ร้านปิดอยู่ ไม่สามารถสั่งได้ในขณะนี้');
    if (!pickupSlots(shop).includes(pickup_time)) throw new HttpError(409, 'เวลารับอาหารนี้ไม่ว่างแล้ว กรุณาเลือกใหม่');
    if (payment_method === 'promptpay' && !shop.promptpay_id) throw new HttpError(409, 'ร้านนี้ยังไม่รับโอนพร้อมเพย์ กรุณาเลือกจ่ายที่ร้าน');

    const ids = [...qtyById.keys()];
    const menu = await tx.all(
      `SELECT * FROM menu_items WHERE shop_id = ? AND id IN (${ids.map(() => '?').join(', ')})`, shopId, ...ids,
    );
    const lines = ids.map((id) => {
      const m = menu.find((x) => x.id === id);
      if (!m) throw new HttpError(400, 'มีเมนูที่ไม่อยู่ในร้านนี้');
      if (!m.is_available) throw new HttpError(409, `"${m.name}" หมดแล้ว`);
      return { m, qty: qtyById.get(id) };
    });
    const total = lines.reduce((s, l) => s + l.m.price * l.qty, 0);

    // เลขคิวรีเซ็ตรายวันแยกร้าน — นับใน transaction เดียวกับ insert กันเลขซ้ำ
    const today = localDate();
    const seq = (await tx.get('SELECT COUNT(*) AS n FROM orders WHERE shop_id = ? AND order_date = ?', shopId, today)).n + 1;
    const queueNo = `${shop.code}-${String(seq).padStart(3, '0')}`;
    const info = await tx.run(
      `INSERT INTO orders (queue_no, order_date, user_id, shop_id, pickup_time, note, total, created_at, payment_method)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      queueNo, today, req.user.id, shopId, pickup_time, String(note).trim(), total, new Date().toISOString(), payment_method,
    );
    for (const { m, qty } of lines) {
      await tx.run('INSERT INTO order_items (order_id, menu_item_id, name, price, qty) VALUES (?, ?, ?, ?, ?)',
        info.lastInsertRowid, m.id, m.name, m.price, qty);
    }
    return info.lastInsertRowid;
  });

  res.status(201).json(await serializeOrder(await db.get('SELECT * FROM orders WHERE id = ?', orderId)));
});

// GET /orders?scope=active|history
r.get('/', async (req, res) => {
  const scope = req.query.scope === 'history' ? 'history' : 'active';
  const statuses = scope === 'active'
    ? `('pending','accepted','cooking','ready')`
    : `('completed','cancelled')`;
  const rows = await db.all(
    `SELECT * FROM orders WHERE user_id = ? AND status IN ${statuses} ORDER BY created_at DESC LIMIT 50`, req.user.id,
  );
  res.json(await serializeOrders(rows));
});

async function ownOrder(req) {
  const o = await db.get('SELECT * FROM orders WHERE id = ?', requireInt(req.params.id, 'id'));
  if (!o || (o.user_id !== req.user.id && req.user.role !== 'admin')) throw new HttpError(404, 'ไม่พบออเดอร์นี้');
  return o;
}

r.get('/:id', async (req, res) => res.json(await serializeOrder(await ownOrder(req))));

// ---------- ชำระเงิน (PromptPay + แนบสลิป) ----------
// GET /orders/:id/payment → ข้อมูลสำหรับแสดง QR
r.get('/:id/payment', async (req, res) => {
  const o = await ownOrder(req);
  const shop = await db.get('SELECT name, promptpay_id FROM shops WHERE id = ?', o.shop_id);
  const needsQr = o.payment_method === 'promptpay' && o.payment_status !== 'paid' && o.status !== 'cancelled';
  res.json({
    order_id: o.id, queue_no: o.queue_no, amount: o.total, shop_name: shop.name,
    method: o.payment_method, status: o.payment_status, note: o.payment_note, has_slip: !!o.slip_image_id,
    promptpay_masked: maskPromptPayId(shop.promptpay_id),
    qr_payload: needsQr && shop.promptpay_id ? promptPayPayload(shop.promptpay_id, o.total) : null,
  });
});

// POST /orders/:id/slip  (body = ไฟล์รูปสลิป) — แนบใหม่ทับของเดิมได้จนกว่าร้านจะยืนยัน
r.post('/:id/slip', rawImage, async (req, res) => {
  const o = await ownOrder(req);
  if (o.payment_method !== 'promptpay') throw new HttpError(409, 'ออเดอร์นี้เลือกจ่ายที่ร้าน');
  if (o.status === 'cancelled') throw new HttpError(409, 'ออเดอร์นี้ถูกยกเลิกแล้ว');
  if (o.payment_status === 'paid') throw new HttpError(409, 'ร้านยืนยันรับเงินแล้ว');
  const imageId = await storeImage(req, 'slip');
  const old = o.slip_image_id;
  await db.run(
    `UPDATE orders SET slip_image_id = ?, payment_status = 'slip_uploaded', payment_note = NULL WHERE id = ?`, imageId, o.id,
  );
  if (old) await db.run(`DELETE FROM images WHERE id = ? AND kind = 'slip'`, old);
  res.json(await serializeOrder(await db.get('SELECT * FROM orders WHERE id = ?', o.id)));
});

r.get('/:id/slip', async (req, res) => {
  const o = await ownOrder(req);
  if (!o.slip_image_id) throw new HttpError(404, 'ยังไม่ได้แนบสลิป');
  await sendImage(res, o.slip_image_id, 'slip');
});

// ลูกค้ายกเลิกได้เฉพาะตอนร้านยังไม่รับออเดอร์
r.post('/:id/cancel', async (req, res) => {
  const o = await ownOrder(req);
  // เงื่อนไข status = 'pending' อยู่ใน UPDATE ด้วย กันร้านรับออเดอร์พร้อมกันพอดี
  const info = await db.run(
    `UPDATE orders SET status = 'cancelled', cancel_reason = 'ลูกค้ายกเลิก', cancelled_at = ? WHERE id = ? AND status = 'pending'`,
    new Date().toISOString(), o.id,
  );
  if (!info.changes) throw new HttpError(409, 'ร้านรับออเดอร์แล้ว ไม่สามารถยกเลิกได้');
  res.json(await serializeOrder(await db.get('SELECT * FROM orders WHERE id = ?', o.id)));
});

export default r;
