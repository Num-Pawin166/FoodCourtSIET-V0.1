import jwt from 'jsonwebtoken';
import { db } from './db.js';

export const JWT_SECRET = process.env.JWT_SECRET || 'foodcourt-siet-dev-secret';
export const TZ = 'Asia/Bangkok';

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ---------- เวลา (ยึดเวลาไทยเสมอ ไม่ขึ้นกับเครื่อง server) ----------
const dateFmt = new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' });
const timeFmt = new Intl.DateTimeFormat('en-GB', { timeZone: TZ, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });

export const localDate = (d = new Date()) => dateFmt.format(d);           // 2026-10-19
export const localTime = (d = new Date()) => timeFmt.format(d);           // 11:45
export const toMinutes = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
export const fromMinutes = (min) => `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`;
export const isHHMM = (s) => typeof s === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(s);

/** ISO (UTC) ของเวลาเที่ยงคืนวันที่ 1 ของเดือนปัจจุบันตามเวลาไทย */
export function startOfMonthIso(d = new Date()) {
  const [y, m] = localDate(d).split('-');
  return new Date(`${y}-${m}-01T00:00:00+07:00`).toISOString();
}
export function startOfDayIso(dateStr = localDate()) {
  return new Date(`${dateStr}T00:00:00+07:00`).toISOString();
}

/** "?, ?, ?" สำหรับ IN (...) */
export const placeholders = (arr) => arr.map(() => '?').join(', ');

// ---------- auth ----------
export function signToken(user) {
  return jwt.sign({ sub: user.id, role: user.role }, JWT_SECRET, { expiresIn: '30d' });
}

export function auth(...roles) {
  return async (req, _res, next) => {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw new HttpError(401, 'กรุณาเข้าสู่ระบบ');
    let payload;
    try {
      payload = jwt.verify(token, JWT_SECRET);
    } catch {
      throw new HttpError(401, 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
    }
    const user = await db.get('SELECT * FROM users WHERE id = ?', payload.sub);
    if (!user || !user.is_active) throw new HttpError(401, 'บัญชีนี้ถูกระงับหรือไม่มีอยู่');
    if (roles.length && !roles.includes(user.role)) throw new HttpError(403, 'ไม่มีสิทธิ์เข้าถึง');
    req.user = user;
    next();
  };
}

export async function publicUsers(users) {
  const shopIds = [...new Set(users.map((u) => u.shop_id).filter(Boolean))];
  const shops = shopIds.length ? await db.all(`SELECT id, name FROM shops WHERE id IN (${placeholders(shopIds)})`, ...shopIds) : [];
  const byId = new Map(shops.map((s) => [s.id, s]));
  return users.map((u) => ({
    id: u.id, username: u.username, name: u.name, role: u.role, email: u.email ?? null,
    faculty: u.faculty, is_active: !!u.is_active, shop: byId.get(u.shop_id) ?? null, created_at: u.created_at,
  }));
}
export async function publicUser(u) {
  return u ? (await publicUsers([u]))[0] : null;
}

// ---------- ร้าน / เมนู ----------
export const ACTIVE_STATUSES = ['pending', 'accepted', 'cooking'];
export const STATUS_LABEL = {
  pending: 'รอร้านรับออเดอร์',
  accepted: 'ร้านรับออเดอร์แล้ว',
  cooking: 'กำลังทำอาหาร',
  ready: 'พร้อมรับอาหาร',
  completed: 'รับอาหารแล้ว',
  cancelled: 'ยกเลิก',
};

/** Map<shop_id, จำนวนคิวที่ยังไม่เสร็จวันนี้> — query เดียวสำหรับทุกร้าน */
export async function queueCounts() {
  const rows = await db.all(
    `SELECT shop_id, COUNT(*) AS n FROM orders WHERE order_date = ? AND status IN ('pending','accepted','cooking') GROUP BY shop_id`,
    localDate(),
  );
  return new Map(rows.map((r) => [r.shop_id, r.n]));
}

/** ร้านเปิดอยู่จริงหรือไม่ = สวิตช์เปิดร้าน + อยู่ในเวลาทำการ */
export function isShopOpenNow(shop, now = new Date()) {
  if (!shop.is_open) return false;
  const t = toMinutes(localTime(now));
  return t >= toMinutes(shop.open_time) && t < toMinutes(shop.close_time);
}

export function serializeShop(s, queue = new Map()) {
  return {
    id: s.id, code: s.code, name: s.name, description: s.description, category: s.category,
    open_time: s.open_time, close_time: s.close_time, prep_min: s.prep_min, prep_max: s.prep_max,
    is_open: !!s.is_open, open_now: isShopOpenNow(s), image_url: s.image_url,
    queue_count: queue.get(s.id) ?? 0,
  };
}
export async function serializeShops(shops) {
  const queue = await queueCounts();
  return shops.map((s) => serializeShop(s, queue));
}
export async function serializeOneShop(s) {
  return (await serializeShops([s]))[0];
}

export function serializeMenuItem(m) {
  return {
    id: m.id, shop_id: m.shop_id, name: m.name, description: m.description, price: m.price,
    is_available: !!m.is_available, image_url: m.image_url, sort_order: m.sort_order,
  };
}

/** ช่วงเวลารับอาหาร: ทุก 15 นาที เริ่มหลังเวลาเตรียมขั้นต่ำ ไม่เกินเวลาปิดร้าน (สูงสุด 9 ช่อง) */
export function pickupSlots(shop, now = new Date()) {
  if (!shop.is_open) return [];
  const open = toMinutes(shop.open_time);
  const close = toMinutes(shop.close_time);
  const earliest = Math.max(toMinutes(localTime(now)) + shop.prep_min, open);
  let t = Math.ceil(earliest / 15) * 15;
  const slots = [];
  while (t <= close && slots.length < 9) {
    slots.push(fromMinutes(t));
    t += 15;
  }
  return slots;
}

// ---------- ออเดอร์ ----------
/** แปลงหลายออเดอร์ด้วย query จำนวนคงที่ (ไม่ยิงทีละออเดอร์ — สำคัญเมื่อ DB อยู่บน cloud) */
export async function serializeOrders(orders) {
  if (!orders.length) return [];
  const ids = orders.map((o) => o.id);
  const shopIds = [...new Set(orders.map((o) => o.shop_id))];
  const userIds = [...new Set(orders.map((o) => o.user_id))];
  const active = orders.filter((o) => ACTIVE_STATUSES.includes(o.status));
  const dates = [...new Set(active.map((o) => o.order_date))];

  const [items, shops, users, queue] = await Promise.all([
    db.all(`SELECT order_id, menu_item_id, name, price, qty FROM order_items WHERE order_id IN (${placeholders(ids)}) ORDER BY id`, ...ids),
    db.all(`SELECT id, name, code FROM shops WHERE id IN (${placeholders(shopIds)})`, ...shopIds),
    db.all(`SELECT id, name, username FROM users WHERE id IN (${placeholders(userIds)})`, ...userIds),
    active.length
      ? db.all(
        `SELECT id, shop_id, order_date FROM orders WHERE status IN ('pending','accepted','cooking')
         AND order_date IN (${placeholders(dates)}) AND shop_id IN (${placeholders(shopIds)})`,
        ...dates, ...shopIds,
      )
      : [],
  ]);

  const itemsBy = new Map();
  for (const i of items) {
    if (!itemsBy.has(i.order_id)) itemsBy.set(i.order_id, []);
    itemsBy.get(i.order_id).push({ menu_item_id: i.menu_item_id, name: i.name, price: i.price, qty: i.qty });
  }
  const shopBy = new Map(shops.map((s) => [s.id, s]));
  const userBy = new Map(users.map((u) => [u.id, u]));

  return orders.map((o) => {
    const lines = itemsBy.get(o.id) || [];
    const queueAhead = ACTIVE_STATUSES.includes(o.status)
      ? queue.filter((q) => q.shop_id === o.shop_id && q.order_date === o.order_date && q.id < o.id).length
      : 0;
    return {
      id: o.id, queue_no: o.queue_no, status: o.status, status_label: STATUS_LABEL[o.status],
      shop: shopBy.get(o.shop_id) ?? null, user: userBy.get(o.user_id) ?? null,
      items: lines, item_count: lines.reduce((s, i) => s + i.qty, 0),
      pickup_time: o.pickup_time, note: o.note, total: o.total, cancel_reason: o.cancel_reason,
      queue_ahead: queueAhead,
      created_at: o.created_at, accepted_at: o.accepted_at, cooking_at: o.cooking_at,
      ready_at: o.ready_at, completed_at: o.completed_at, cancelled_at: o.cancelled_at,
    };
  });
}
export async function serializeOrder(o) {
  return (await serializeOrders([o]))[0];
}

/** การเปลี่ยนสถานะที่อนุญาต (ฝั่งร้าน) */
export const NEXT_STATUS = {
  pending: ['accepted', 'cancelled'],
  accepted: ['cooking', 'cancelled'],
  cooking: ['ready'],
  ready: ['completed'],
  completed: [],
  cancelled: [],
};

export function pick(obj, keys) {
  const out = {};
  for (const k of keys) if (obj[k] !== undefined) out[k] = obj[k];
  return out;
}

export function requireInt(v, name) {
  const n = Number(v);
  if (!Number.isInteger(n)) throw new HttpError(400, `${name} ไม่ถูกต้อง`);
  return n;
}
