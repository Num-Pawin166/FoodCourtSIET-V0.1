import { Router } from 'express';
import { db } from '../db.js';
import { HttpError, auth, serializeShops, serializeOneShop, serializeMenuItem, pickupSlots, requireInt } from '../util.js';

const r = Router();

r.get('/categories', async (_req, res) => {
  const rows = await db.all('SELECT DISTINCT category FROM shops ORDER BY category');
  res.json(rows.map((x) => x.category));
});

// GET /shops?q=ข้าว&category=เส้น  (ค้นหาทั้งชื่อร้านและชื่อเมนู)
r.get('/shops', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const category = String(req.query.category || '').trim();
  const where = [];
  const params = [];
  if (category) { where.push('s.category = ?'); params.push(category); }
  if (q) {
    where.push(`(s.name LIKE ? OR s.description LIKE ? OR EXISTS (SELECT 1 FROM menu_items m WHERE m.shop_id = s.id AND m.name LIKE ?))`);
    params.push(`%${q}%`, `%${q}%`, `%${q}%`);
  }
  const rows = await db.all(
    `SELECT s.* FROM shops s ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY s.is_open DESC, s.code`,
    ...params,
  );
  res.json(await serializeShops(rows));
});

r.get('/shops/:id', async (req, res) => {
  const id = requireInt(req.params.id, 'id');
  const [shop, menu] = await Promise.all([
    db.get('SELECT * FROM shops WHERE id = ?', id),
    db.all('SELECT * FROM menu_items WHERE shop_id = ? ORDER BY sort_order, id', id),
  ]);
  if (!shop) throw new HttpError(404, 'ไม่พบร้านนี้');
  res.json({ ...(await serializeOneShop(shop)), menu: menu.map(serializeMenuItem), pickup_slots: pickupSlots(shop) });
});

r.get('/shops/:id/slots', async (req, res) => {
  const shop = await db.get('SELECT * FROM shops WHERE id = ?', requireInt(req.params.id, 'id'));
  if (!shop) throw new HttpError(404, 'ไม่พบร้านนี้');
  res.json(pickupSlots(shop));
});

// ---------- เมนูโปรด ----------
r.get('/favorites', auth(), async (req, res) => {
  const rows = await db.all(
    `SELECT m.*, s.name AS shop_name FROM favorites f
     JOIN menu_items m ON m.id = f.menu_item_id JOIN shops s ON s.id = m.shop_id
     WHERE f.user_id = ? ORDER BY f.created_at DESC`,
    req.user.id,
  );
  res.json(rows.map((m) => ({ ...serializeMenuItem(m), shop_name: m.shop_name })));
});

r.put('/favorites/:menuItemId', auth(), async (req, res) => {
  const id = requireInt(req.params.menuItemId, 'menuItemId');
  if (!(await db.get('SELECT 1 FROM menu_items WHERE id = ?', id))) throw new HttpError(404, 'ไม่พบเมนูนี้');
  await db.run('INSERT OR IGNORE INTO favorites (user_id, menu_item_id) VALUES (?, ?)', req.user.id, id);
  res.json({ ok: true });
});

r.delete('/favorites/:menuItemId', auth(), async (req, res) => {
  await db.run('DELETE FROM favorites WHERE user_id = ? AND menu_item_id = ?', req.user.id, requireInt(req.params.menuItemId, 'menuItemId'));
  res.json({ ok: true });
});

export default r;
