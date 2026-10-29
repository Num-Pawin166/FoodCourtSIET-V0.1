// Security test: การยืนยันตัวตน สิทธิ์การเข้าถึง การแยกข้อมูลระหว่างผู้ใช้/ร้าน และการตรวจ input ที่เป็นอันตราย
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { startServer, PNG } from './helpers.js';

let api;
let student; let otherStudent; let vendorA; let vendorB; let admin;
let orderA; // ออเดอร์ของ student ที่ร้าน A (โอนพร้อมเพย์ + มีสลิป)

before(async () => {
  api = await startServer();
  [student, otherStudent, vendorA, vendorB, admin] = await Promise.all([
    api.login('65010001'), api.login('65010002'), api.login('shopa'), api.login('shopb'), api.login('admin', 'admin1234'),
  ]);
  await api.call('/vendor/shop', { token: vendorA, method: 'PATCH', body: { promptpay_id: '0812345678' } });
  const slot = (await api.call('/shops/1')).json.pickup_slots[0];
  orderA = (await api.call('/orders', { token: student, body: { shop_id: 1, items: [{ menu_item_id: 1, qty: 1 }], pickup_time: slot, payment_method: 'promptpay' } })).json;
  await api.call(`/orders/${orderA.id}/slip`, { token: student, raw: PNG, type: 'image/png' });
});
after(() => api.close());

describe('การยืนยันตัวตน (authentication)', () => {
  const protectedRoutes = ['/auth/me', '/favorites', '/orders', '/vendor/orders', '/admin/summary'];

  test('ไม่มี token → 401 ทุก endpoint ที่ต้องล็อกอิน', async () => {
    for (const p of protectedRoutes) assert.equal((await api.call(p)).status, 401, p);
    assert.equal((await api.call('/ai/chat', { body: { messages: [{ role: 'user', text: 'hi' }] } })).status, 401);
  });

  test('token ปลอม / ลงลายเซ็นด้วย secret อื่น / หมดอายุ → 401', async () => {
    const forged = jwt.sign({ sub: 1, role: 'admin' }, 'not-the-real-secret');
    const { JWT_SECRET } = await import('../src/util.js');
    const expired = jwt.sign({ sub: 1, role: 'admin', exp: Math.floor(Date.now() / 1000) - 60 }, JWT_SECRET);
    for (const token of ['garbage', forged, expired]) {
      assert.equal((await api.call('/admin/summary', { token })).status, 401);
    }
    const res = await fetch(`${api.base}/auth/me`, { headers: { authorization: `Basic ${student}` } });
    assert.equal(res.status, 401);
  });

  test('token ของบัญชีที่ถูกลบไปแล้ว → 401', async () => {
    const { JWT_SECRET } = await import('../src/util.js');
    const ghost = jwt.sign({ sub: 99999, role: 'admin' }, JWT_SECRET);
    assert.equal((await api.call('/auth/me', { token: ghost })).status, 401);
  });

  test('role ใน token ไม่มีผล ระบบเชื่อ role จากฐานข้อมูล', async () => {
    const { JWT_SECRET } = await import('../src/util.js');
    const me = (await api.call('/auth/me', { token: student })).json;
    const escalated = jwt.sign({ sub: me.id, role: 'admin' }, JWT_SECRET);
    assert.equal((await api.call('/admin/summary', { token: escalated })).status, 403);
  });

  test('รหัสผ่านผิด / ผู้ใช้ไม่มีอยู่ ได้ข้อความเดียวกัน (ไม่บอกว่าชื่อผู้ใช้มีจริงไหม)', async () => {
    const wrongPass = await api.call('/auth/login', { body: { username: '65010001', password: 'nope' } });
    const noUser = await api.call('/auth/login', { body: { username: 'nobody', password: 'nope' } });
    assert.equal(wrongPass.status, 401);
    assert.equal(noUser.status, 401);
    assert.equal(wrongPass.json.error, noUser.json.error);
    assert.equal((await api.call('/auth/login', { body: {} })).status, 400);
  });

  test('ผลลัพธ์ login และ /me ไม่มี password_hash', async () => {
    const r = await api.call('/auth/login', { body: { username: '65010001', password: '1234' } });
    assert.ok(!JSON.stringify(r.json).includes('password'));
    const users = (await api.call('/admin/users', { token: admin })).json;
    assert.ok(!JSON.stringify(users).includes('password_hash'));
  });

  test('Google: ต้องมี id_token', async () => {
    assert.equal((await api.call('/auth/google', { body: {} })).status, 503); // ยังไม่ตั้ง client ID ที่ server นี้
  });
});

describe('Google Sign-In: ล็อกโดเมน @kmitl.ac.th', () => {
  let isAllowed;
  before(async () => { ({ isAllowedGoogleAccount: isAllowed } = await import('../src/routes/auth.js')); });

  test('บัญชี KMITL ที่ยืนยันอีเมลแล้วผ่าน', () => {
    assert.equal(isAllowed({ email: '65010001@kmitl.ac.th', email_verified: true, hd: 'kmitl.ac.th' }), true);
    assert.equal(isAllowed({ email: 'A.B@KMITL.AC.TH', email_verified: true, hd: 'kmitl.ac.th' }), true);
  });

  test('ปฏิเสธ gmail, โดเมนหลอก, อีเมลยังไม่ยืนยัน และไม่มี hd', () => {
    const rejects = [
      { email: 'someone@gmail.com', email_verified: true },
      { email: 'kmitl.ac.th@gmail.com', email_verified: true, hd: undefined },
      { email: 'x@kmitl.ac.th.evil.com', email_verified: true, hd: 'kmitl.ac.th.evil.com' },
      { email: 'x@fakekmitl.ac.th', email_verified: true, hd: 'fakekmitl.ac.th' },
      { email: 'x@kmitl.ac.th', email_verified: false, hd: 'kmitl.ac.th' },
      { email: 'x@kmitl.ac.th', email_verified: true }, // ไม่มี hd = ไม่ใช่บัญชี Workspace ของสถาบัน
      { email: 'x@gmail.com', email_verified: true, hd: 'kmitl.ac.th' },
      null,
    ];
    for (const p of rejects) assert.equal(isAllowed(p), false, JSON.stringify(p));
  });
});

describe('สิทธิ์ตามบทบาท (authorization)', () => {
  test('นักศึกษาเข้า API ร้านค้าและแอดมินไม่ได้', async () => {
    assert.equal((await api.call('/vendor/orders', { token: student })).status, 403);
    assert.equal((await api.call('/vendor/menu', { token: student, body: { name: 'x', price: 1 } })).status, 403);
    assert.equal((await api.call('/admin/users', { token: student })).status, 403);
    assert.equal((await api.call('/admin/users', { token: student, body: { username: 'hacker', name: 'h', password: '1234', role: 'admin' } })).status, 403);
  });

  test('ร้านค้าเข้า API แอดมินไม่ได้ และสั่งอาหารแทนลูกค้าไม่ได้', async () => {
    assert.equal((await api.call('/admin/summary', { token: vendorA })).status, 403);
    assert.equal((await api.call('/orders', { token: vendorA })).status, 403);
    assert.equal((await api.call('/ai/chat', { token: vendorA, body: { messages: [{ role: 'user', text: 'x' }] } })).status, 403);
  });

  test('บัญชีร้านที่ยังไม่ผูกร้าน ใช้ API ร้านไม่ได้', async () => {
    await api.call('/admin/users', { token: admin, body: { username: 'loose', name: 'ไม่มีร้าน', password: '1234', role: 'vendor', shop_id: 2 } });
    const t = await api.login('loose');
    const { db } = api;
    await db.run(`UPDATE users SET shop_id = NULL WHERE username = 'loose'`);
    assert.equal((await api.call('/vendor/shop', { token: t })).status, 403);
  });
});

describe('การแยกข้อมูล (ห้ามเห็นของคนอื่น)', () => {
  test('นักศึกษาคนอื่นดูออเดอร์ / QR / สลิป / ยกเลิกออเดอร์ของเราไม่ได้', async () => {
    assert.equal((await api.call(`/orders/${orderA.id}`, { token: otherStudent })).status, 404);
    assert.equal((await api.call(`/orders/${orderA.id}/payment`, { token: otherStudent })).status, 404);
    assert.equal((await api.call(`/orders/${orderA.id}/slip`, { token: otherStudent })).status, 404);
    assert.equal((await api.call(`/orders/${orderA.id}/slip`, { token: otherStudent, raw: PNG, type: 'image/png' })).status, 404);
    assert.equal((await api.call(`/orders/${orderA.id}/cancel`, { token: otherStudent, method: 'POST' })).status, 404);
    assert.ok(!(await api.call('/orders?scope=active', { token: otherStudent })).json.some((o) => o.id === orderA.id));
  });

  test('ร้าน B จัดการออเดอร์ / สลิป / เมนู / รูปของร้าน A ไม่ได้', async () => {
    assert.equal((await api.call(`/vendor/orders/${orderA.id}/status`, { token: vendorB, method: 'PATCH', body: { status: 'accepted' } })).status, 404);
    assert.equal((await api.call(`/vendor/orders/${orderA.id}/payment`, { token: vendorB, method: 'PATCH', body: { action: 'confirm' } })).status, 404);
    assert.equal((await api.call(`/vendor/orders/${orderA.id}/slip`, { token: vendorB })).status, 404);
    assert.equal((await api.call('/vendor/menu/1', { token: vendorB, method: 'PATCH', body: { price: 1 } })).status, 404);
    assert.equal((await api.call('/vendor/menu/1', { token: vendorB, method: 'DELETE' })).status, 404);
    assert.equal((await api.call('/vendor/menu/1/image', { token: vendorB, raw: PNG, type: 'image/png' })).status, 404);
    assert.equal((await api.call('/vendor/menu/1/image', { token: vendorB, method: 'DELETE' })).status, 404);
    assert.ok(!(await api.call('/vendor/orders', { token: vendorB })).json.some((o) => o.id === orderA.id));
    assert.equal((await api.call('/shops/1')).json.menu.find((m) => m.id === 1).price, 50); // ราคายังเหมือนเดิม
  });

  test('สลิปเป็นข้อมูลส่วนตัว: เปิดผ่าน URL รูปสาธารณะไม่ได้', async () => {
    const rows = await api.db.all(`SELECT id FROM images WHERE kind = 'slip'`);
    assert.ok(rows.length > 0);
    for (const { id } of rows) assert.equal((await api.call(`/images/${id}`)).status, 404);
  });

  test('หมายเลขพร้อมเพย์จริงไม่หลุดใน API สาธารณะ (แสดงแบบปิดบางส่วนเท่านั้น)', async () => {
    const pub = JSON.stringify([(await api.call('/shops')).json, (await api.call('/shops/1')).json]);
    assert.ok(!pub.includes('0812345678'));
    const pay = (await api.call(`/orders/${orderA.id}/payment`, { token: student })).json;
    assert.equal(pay.promptpay_masked, '081-xxx-5678');
  });
});

describe('การตรวจ input ที่เป็นอันตราย', () => {
  test('แก้ราคาจากฝั่งแอปไม่ได้: ระบบไม่สนใจ price / total ที่ส่งมา', async () => {
    const slot = (await api.call('/shops/1')).json.pickup_slots[0];
    const r = await api.call('/orders', {
      token: student,
      body: { shop_id: 1, items: [{ menu_item_id: 1, qty: 2, price: 1 }], pickup_time: slot, total: 1 },
    });
    assert.equal(r.status, 201);
    assert.equal(r.json.total, 100);
    assert.equal(r.json.items[0].price, 50);
  });

  test('จำนวนติดลบ / ศูนย์ / ทศนิยม ถูกปฏิเสธ', async () => {
    const slot = (await api.call('/shops/1')).json.pickup_slots[0];
    for (const qty of [-1, 0, 1.5, '2; DROP TABLE orders']) {
      const r = await api.call('/orders', { token: student, body: { shop_id: 1, items: [{ menu_item_id: 1, qty }], pickup_time: slot } });
      assert.equal(r.status, 400, String(qty));
    }
  });

  test('สั่งเมนูของร้านอื่นปนในออเดอร์ไม่ได้', async () => {
    const slot = (await api.call('/shops/1')).json.pickup_slots[0];
    const r = await api.call('/orders', { token: student, body: { shop_id: 1, items: [{ menu_item_id: 16, qty: 1 }], pickup_time: slot } });
    assert.equal(r.status, 400);
  });

  test('SQL injection ในช่องค้นหา / ล็อกอิน ไม่มีผล', async () => {
    const r = await api.call(`/shops?q=${encodeURIComponent("' OR 1=1 --")}`);
    assert.equal(r.status, 200);
    assert.equal(r.json.length, 0);
    const login = await api.call('/auth/login', { body: { username: "admin' --", password: 'x' } });
    assert.equal(login.status, 401);
    const users = await api.call(`/admin/users?q=${encodeURIComponent("%' OR '1'='1")}`, { token: admin });
    assert.equal(users.json.length, 0);
    assert.equal((await api.db.get('SELECT COUNT(*) AS n FROM shops')).n, 5); // ตารางยังอยู่ครบ
  });

  test('id ที่ไม่ใช่ตัวเลขได้ 400', async () => {
    assert.equal((await api.call('/shops/1%20OR%201=1')).status, 400);
    assert.equal((await api.call('/orders/abc', { token: student })).status, 400);
  });

  test('ไฟล์ปลอม: เนื้อไฟล์ไม่ใช่รูป แม้ตั้ง Content-Type เป็นรูป ถูกปฏิเสธ', async () => {
    const fakes = [
      [Buffer.from('<script>alert(1)</script>'), 'image/png'],
      [Buffer.from('%PDF-1.4 fake'), 'image/jpeg'],
      [Buffer.from('GIF89a......'), 'image/gif'],
      [Buffer.alloc(0), 'image/png'],
    ];
    for (const [raw, type] of fakes) {
      const r = await api.call('/vendor/menu/1/image', { token: vendorA, raw, type });
      assert.equal(r.status, 400, raw.toString().slice(0, 10));
    }
  });

  test('ไฟล์ใหญ่เกิน 2 MB ถูกปฏิเสธ', async () => {
    const big = Buffer.concat([PNG, Buffer.alloc(2 * 1024 * 1024)]);
    const r = await api.call('/vendor/menu/1/image', { token: vendorA, raw: big, type: 'image/png' });
    assert.equal(r.status, 413);
  });

  test('body JSON ใหญ่เกินกำหนดถูกปฏิเสธ', async () => {
    const r = await api.call('/vendor/menu', { token: vendorA, body: { name: 'x', price: 1, description: 'ก'.repeat(200_000) } });
    assert.equal(r.status, 413);
  });

  test('error ภายในไม่เปิดเผยรายละเอียดระบบ', async (t) => {
    t.mock.method(console, 'error', () => {});
    t.mock.method(api.db, 'all', async () => { throw new Error('SQLITE_SECRET_INTERNAL_DETAIL'); });
    const r = await api.call('/categories');
    assert.equal(r.status, 500);
    assert.ok(!JSON.stringify(r.json).includes('SQLITE'));
  });
});

describe('จำกัดการใช้งาน AI (rate limit)', () => {
  test('ถามเกิน 10 ครั้งต่อนาทีได้ 429', async () => {
    const t = await api.login('65010002');
    const statuses = [];
    for (let i = 0; i < 11; i++) {
      statuses.push((await api.call('/ai/chat', { token: t, body: { messages: [{ role: 'user', text: 'งบ 50' }] } })).status);
    }
    assert.deepEqual(statuses.slice(0, 10), Array(10).fill(200));
    assert.equal(statuses[10], 429);
  });
});
