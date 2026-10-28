import { createClient } from '@libsql/client';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

// ฐานข้อมูล: Turso (libSQL บน cloud) ถ้ามี TURSO_DATABASE_URL ไม่งั้นใช้ไฟล์ SQLite ในเครื่อง (data/foodcourt.db)
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(__dirname, '..', 'data');

function resolveUrl() {
  if (process.env.TURSO_DATABASE_URL) return process.env.TURSO_DATABASE_URL;
  fs.mkdirSync(DATA_DIR, { recursive: true });
  return pathToFileURL(process.env.DB_PATH || path.join(DATA_DIR, 'foodcourt.db')).href;
}

export const DB_URL = resolveUrl();
export const isRemote = !DB_URL.startsWith('file:');
const client = createClient({ url: DB_URL, authToken: process.env.TURSO_AUTH_TOKEN });

/** แปลงผลลัพธ์ libSQL เป็น object ธรรมดา { column: value } */
const toObjects = (rs) => rs.rows.map((r) => Object.fromEntries(rs.columns.map((c, i) => [c, r[i]])));

/** ชุดคำสั่งเดียวกันใช้ได้ทั้งกับ client ปกติและใน transaction */
function wrap(exec) {
  const run = (sql, args) => exec({ sql, args: args.map((a) => (a === undefined ? null : a)) });
  return {
    /** แถวแรก หรือ undefined */
    get: async (sql, ...args) => toObjects(await run(sql, args))[0],
    all: async (sql, ...args) => toObjects(await run(sql, args)),
    /** { changes, lastInsertRowid } */
    run: async (sql, ...args) => {
      const rs = await run(sql, args);
      return { changes: rs.rowsAffected, lastInsertRowid: rs.lastInsertRowid == null ? null : Number(rs.lastInsertRowid) };
    },
  };
}

export const db = {
  ...wrap((stmt) => client.execute(stmt)),
  /** หลายคำสั่ง (DDL) ในครั้งเดียว */
  exec: (sql) => client.executeMultiple(sql),
  /** หลายคำสั่งเขียนในรอบเดียว (atomic) — [{ sql, args }] */
  batch: (stmts) => client.batch(stmts.map((s) => ({ sql: s.sql, args: s.args ?? [] })), 'write'),
};

/** transaction แบบเขียน: fn รับ tx ที่มี get/all/run เหมือน db */
export async function transaction(fn) {
  const tx = await client.transaction('write');
  try {
    const result = await fn(wrap((stmt) => tx.execute(stmt)));
    await tx.commit();
    return result;
  } catch (err) {
    await tx.rollback().catch(() => {});
    throw err;
  } finally {
    tx.close();
  }
}

export async function initSchema() {
  if (!isRemote) await client.execute('PRAGMA journal_mode = WAL').catch(() => {});
  await db.exec(`
CREATE TABLE IF NOT EXISTS shops (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT NOT NULL UNIQUE,             -- ตัวอักษรนำหน้าคิว เช่น A -> A-027
  name        TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category    TEXT NOT NULL DEFAULT 'อาหารจานเดียว',
  open_time   TEXT NOT NULL DEFAULT '07:30',
  close_time  TEXT NOT NULL DEFAULT '17:00',
  prep_min    INTEGER NOT NULL DEFAULT 5,
  prep_max    INTEGER NOT NULL DEFAULT 10,
  is_open     INTEGER NOT NULL DEFAULT 1,
  image_url   TEXT,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  username      TEXT NOT NULL UNIQUE,           -- รหัสนักศึกษา หรือชื่อผู้ใช้ของร้าน/แอดมิน
  name          TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('student','vendor','admin')),
  shop_id       INTEGER REFERENCES shops(id) ON DELETE SET NULL,
  faculty       TEXT NOT NULL DEFAULT 'SIET - KMITL',
  is_active     INTEGER NOT NULL DEFAULT 1,
  created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS menu_items (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  shop_id      INTEGER NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  description  TEXT NOT NULL DEFAULT '',
  price        INTEGER NOT NULL CHECK (price >= 0),
  is_available INTEGER NOT NULL DEFAULT 1,
  image_url    TEXT,
  sort_order   INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS orders (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  queue_no      TEXT NOT NULL,
  order_date    TEXT NOT NULL,                  -- YYYY-MM-DD (เวลาไทย) ใช้รีเซ็ตเลขคิวรายวัน
  user_id       INTEGER NOT NULL REFERENCES users(id),
  shop_id       INTEGER NOT NULL REFERENCES shops(id),
  status        TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','accepted','cooking','ready','completed','cancelled')),
  pickup_time   TEXT NOT NULL,                  -- HH:MM
  note          TEXT NOT NULL DEFAULT '',
  total         INTEGER NOT NULL,
  cancel_reason TEXT,
  created_at    TEXT NOT NULL,
  accepted_at   TEXT,
  cooking_at    TEXT,
  ready_at      TEXT,
  completed_at  TEXT,
  cancelled_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_orders_shop_date ON orders(shop_id, order_date);
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id, created_at);

CREATE TABLE IF NOT EXISTS order_items (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id     INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  menu_item_id INTEGER REFERENCES menu_items(id) ON DELETE SET NULL,
  name         TEXT NOT NULL,                   -- เก็บชื่อ/ราคา ณ ตอนสั่ง
  price        INTEGER NOT NULL,
  qty          INTEGER NOT NULL CHECK (qty > 0)
);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

CREATE TABLE IF NOT EXISTS favorites (
  user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  menu_item_id INTEGER NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  PRIMARY KEY (user_id, menu_item_id)
);
`);
  // รูปภาพ (รูปเมนู + สลิปโอนเงิน) เก็บใน DB เพราะดิสก์ของ Render แบบฟรีหายทุกครั้งที่ deploy
  await db.exec(`
CREATE TABLE IF NOT EXISTS images (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  kind        TEXT NOT NULL CHECK (kind IN ('menu','slip')),
  mime        TEXT NOT NULL,
  data        BLOB NOT NULL,
  uploaded_by INTEGER,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);`);

  // migrations: คอลัมน์ที่เพิ่มทีหลัง (DB เก่าจะได้รับคอลัมน์ใหม่อัตโนมัติ)
  await addColumns('users', { email: 'TEXT' });
  await db.exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL');
  await addColumns('shops', { promptpay_id: 'TEXT' });
  await addColumns('orders', {
    payment_method: "TEXT NOT NULL DEFAULT 'cash'",     // cash = จ่ายที่ร้าน | promptpay = โอน
    payment_status: "TEXT NOT NULL DEFAULT 'unpaid'",   // unpaid | slip_uploaded | paid | rejected
    slip_image_id: 'INTEGER',
    payment_note: 'TEXT',                                // เหตุผลที่ร้านปฏิเสธสลิป
    paid_at: 'TEXT',
  });
}

async function addColumns(table, defs) {
  const existing = new Set((await db.all(`PRAGMA table_info(${table})`)).map((c) => c.name));
  for (const [col, type] of Object.entries(defs)) {
    if (!existing.has(col)) await db.exec(`ALTER TABLE ${table} ADD COLUMN ${col} ${type}`);
  }
}
