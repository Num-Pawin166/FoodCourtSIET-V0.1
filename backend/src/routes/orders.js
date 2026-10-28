import { Router } from 'express';
import { db, transaction } from '../db.js';
import {
  HttpError, auth, serializeOrder, serializeOrders, pickupSlots, isShopOpenNow, localDate, requireInt,
} from '../util.js';

const r = Router();
r.use(auth('student', 'admin'));

// สร้างออเดอร์: { shop_id, items: [{ menu_item_id, qty }], pickup_time: "11:45", note }
r.post('/', async (req, res) => {
  const { shop_id, items, pickup_time, note = '' } = req.body || {};
  const shopId = requireInt(shop_id, 'shop_id');
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
      `INSERT INTO orders (queue_no, order_date, user_id, shop_id, pickup_time, note, total, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      queueNo, today, req.user.id, shopId, pickup_time, String(note).trim(), total, new Date().toISOString(),
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
