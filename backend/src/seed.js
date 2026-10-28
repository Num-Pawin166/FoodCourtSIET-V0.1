import bcrypt from 'bcryptjs';
import { db, initSchema, isRemote, DB_URL } from './db.js';
import { localDate, toMinutes } from './util.js';

const SHOPS = [
  { code: 'A', name: 'ร้านข้าวขาหมูป้าแดง', category: 'อาหารจานเดียว', description: 'ข้าวขาหมู ข้าวมันไก่ ข้าวหมูกรอบ ทำสดทุกวัน', open: '07:30', close: '17:00', prep: [5, 10],
    menu: [['ข้าวขาหมู', 'พร้อมน้ำซุป ผักดอง น้ำจิ้ม', 50], ['ข้าวมันไก่ทอด', 'พร้อมน้ำซุป น้ำจิ้ม', 45], ['ข้าวหมูกรอบ', 'พร้อมน้ำซุป น้ำจิ้ม', 55], ['ข้าวขาหมูพิเศษ', 'เพิ่มขาหมูและไข่พะโล้', 65]] },
  { code: 'B', name: 'ก๋วยเตี๋ยวลุงชัย', category: 'เส้น', description: 'ก๋วยเตี๋ยวหมูน้ำใส ต้มยำ เย็นตาโฟ', open: '08:00', close: '16:00', prep: [5, 8],
    menu: [['ก๋วยเตี๋ยวหมูน้ำใส', 'เลือกเส้นได้ บอกในหมายเหตุ', 45], ['ก๋วยเตี๋ยวต้มยำ', 'รสจัดจ้าน', 50], ['เย็นตาโฟ', 'ลูกชิ้นปลา เต้าหู้', 50], ['บะหมี่แห้งหมูแดง', 'หมูแดง เกี๊ยวทอด', 50]] },
  { code: 'C', name: 'ครัวพี่ต้น อาหารตามสั่ง', category: 'อาหารจานเดียว', description: 'กะเพรา ข้าวผัด ผัดพริกแกง', open: '09:00', close: '18:00', prep: [8, 15],
    menu: [['กะเพราหมูสับไข่ดาว', 'เผ็ดน้อย/เผ็ดมาก บอกในหมายเหตุ', 55], ['ข้าวผัดหมู', 'พร้อมแตงกวา มะนาว', 45], ['ข้าวไข่เจียวหมูสับ', '', 40], ['ผัดพริกแกงไก่', '', 50]] },
  { code: 'D', name: 'ผัดไทยหอยทอด', category: 'เส้น', description: 'ผัดไทยกุ้งสด หอยทอดกรอบ', open: '10:00', close: '17:00', prep: [8, 12],
    menu: [['ผัดไทยกุ้งสด', '', 60], ['ผัดไทยวุ้นเส้น', '', 50], ['หอยทอด', 'กรอบนอกนุ่มใน', 60]] },
  { code: 'E', name: 'น้องน้ำ เครื่องดื่ม', category: 'เครื่องดื่ม', description: 'ชา กาแฟ น้ำผลไม้ปั่น', open: '07:00', close: '18:00', prep: [3, 5],
    menu: [['ชาไทยเย็น', '', 30], ['โกโก้เย็น', '', 30], ['อเมริกาโน่เย็น', '', 40], ['น้ำแตงโมปั่น', '', 35], ['น้ำเปล่า', '', 10]] },
];

const STUDENTS = [
  ['65010001', 'สมชาย ใจดี'], ['65010002', 'สมหญิง รักเรียน'], ['65010003', 'ธนากร มีสุข'],
  ['65010004', 'พิมพ์ชนก แก้วใส'], ['65010005', 'กิตติพงษ์ ศรีสวัสดิ์'], ['66010010', 'ณัฐธิดา ทองดี'],
];

// สุ่มแบบกำหนด seed ได้ เพื่อให้ข้อมูลตัวอย่างเหมือนเดิมทุกครั้ง
let s = 42;
const rand = () => ((s = (s * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
const randInt = (a, b) => a + Math.floor(rand() * (b - a + 1));

async function seedAll() {
  const hash = bcrypt.hashSync('1234', 10);
  // กำหนด id เองทั้งหมด (DB ว่าง) แล้วส่งเป็น batch เดียว — เร็วแม้ DB อยู่บน cloud
  const stmts = [];
  const add = (sql, ...args) => stmts.push({ sql, args });
  const ids = { shop: 0, menu: 0, user: 0, order: 0 };
  const insShop = (...a) => { add('INSERT INTO shops (id, code, name, category, description, open_time, close_time, prep_min, prep_max) VALUES (?,?,?,?,?,?,?,?,?)', ++ids.shop, ...a); return ids.shop; };
  const insMenu = (...a) => { add('INSERT INTO menu_items (id, shop_id, name, description, price, sort_order) VALUES (?,?,?,?,?,?)', ++ids.menu, ...a); return ids.menu; };
  const insUser = (...a) => { add('INSERT INTO users (id, username, name, password_hash, role, shop_id) VALUES (?,?,?,?,?,?)', ++ids.user, ...a); return ids.user; };
  {
    insUser('admin', 'ผู้ดูแลศูนย์อาหาร', bcrypt.hashSync('admin1234', 10), 'admin', null);
    const shops = SHOPS.map((sh) => {
      const id = insShop(sh.code, sh.name, sh.category, sh.description, sh.open, sh.close, sh.prep[0], sh.prep[1]);
      const menu = sh.menu.map(([n, d, p], i) => ({ id: insMenu(id, n, d, p, i), name: n, price: p }));
      insUser(`shop${sh.code.toLowerCase()}`, `เจ้าของ${sh.name}`, hash, 'vendor', id);
      return { ...sh, id, menu };
    });
    const studentIds = STUDENTS.map(([u, n]) => insUser(u, n, hash, 'student', null));

    // ประวัติออเดอร์ย้อนหลัง 14 วัน (ไม่รวมวันนี้)
    const insOrder = { run: (...a) => { add(
      `INSERT INTO orders (id, queue_no, order_date, user_id, shop_id, status, pickup_time, note, total, created_at, accepted_at, cooking_at, ready_at, completed_at, cancelled_at, cancel_reason)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, ++ids.order, ...a); return { lastInsertRowid: ids.order }; } };
    const insItem = { run: (...a) => add('INSERT INTO order_items (order_id, menu_item_id, name, price, qty) VALUES (?,?,?,?,?)', ...a) };
    for (let dayAgo = 14; dayAgo >= 1; dayAgo--) {
      const date = localDate(new Date(Date.now() - dayAgo * 86400000));
      for (const shop of shops) {
        const n = randInt(4, 14);
        const minutes = Array.from({ length: n }, () => randInt(toMinutes(shop.open) + 30, toMinutes(shop.close) - 30)).sort((a, b) => a - b);
        minutes.forEach((m, i) => {
          const created = new Date(`${date}T${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}:00+07:00`);
          const at = (min) => new Date(created.getTime() + min * 60000).toISOString();
          const cancelled = rand() < 0.06;
          const lines = shop.menu.filter(() => rand() < 0.45);
          if (!lines.length) lines.push(shop.menu[0]);
          const qtys = lines.map(() => (rand() < 0.8 ? 1 : 2));
          const total = lines.reduce((t, l, k) => t + l.price * qtys[k], 0);
          const pickupMin = Math.ceil((m + shop.prep[1]) / 15) * 15;
          const pickup = `${String(Math.floor(pickupMin / 60)).padStart(2, '0')}:${String(pickupMin % 60).padStart(2, '0')}`;
          const oid = insOrder.run(
            // บัญชีทดลองหลัก (65010001) ได้ส่วนน้อย ให้ยอดในหน้าโปรไฟล์ดูสมจริง
            `${shop.code}-${String(i + 1).padStart(3, '0')}`, date, rand() < 0.02 ? studentIds[0] : studentIds[randInt(1, studentIds.length - 1)], shop.id,
            cancelled ? 'cancelled' : 'completed', pickup, '', total, created.toISOString(),
            cancelled ? null : at(1), cancelled ? null : at(2), cancelled ? null : at(shop.prep[1]), cancelled ? null : at(shop.prep[1] + 5),
            cancelled ? at(2) : null, cancelled ? 'ลูกค้ายกเลิก' : null,
          ).lastInsertRowid;
          lines.forEach((l, k) => insItem.run(oid, l.id, l.name, l.price, qtys[k]));
        });
      }
    }

    // เมนูโปรดของบัญชีตัวอย่าง
    add('INSERT INTO favorites (user_id, menu_item_id) VALUES (?, ?)', studentIds[0], shops[0].menu[0].id);
    add('INSERT INTO favorites (user_id, menu_item_id) VALUES (?, ?)', studentIds[0], shops[2].menu[0].id);
  }
  await db.batch(stmts); // atomic: สำเร็จทั้งหมดหรือไม่เขียนเลย
  return stmts.length;
}

export async function seedIfEmpty() {
  if ((await db.get('SELECT COUNT(*) AS n FROM users')).n === 0) {
    const n = await seedAll();
    console.log(`Seeded demo data: ${n} rows (admin/admin1234, shopa..shope/1234, 65010001/1234)`);
  }
}

// `npm run seed` = ล้างข้อมูลทั้งหมดแล้วใส่ข้อมูลตัวอย่างใหม่
if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('src/seed.js')) {
  await initSchema();
  await db.batch(['favorites', 'order_items', 'orders', 'menu_items', 'users', 'shops'].map((t) => ({ sql: `DELETE FROM ${t}` })));
  await db.exec('DELETE FROM sqlite_sequence').catch(() => {});
  const n = await seedAll();
  console.log(`Database reset with demo data (${n} rows) -> ${isRemote ? 'Turso' : DB_URL}`);
}
