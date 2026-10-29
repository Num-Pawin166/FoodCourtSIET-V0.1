// Integration test: เปิด API จริง + ฐานข้อมูลจริง (SQLite ชั่วคราว) แล้วเดิน flow ตั้งแต่ต้นจนจบผ่าน HTTP
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, PNG, JPEG, WEBP } from './helpers.js';

let api;
let student; let vendorA; let vendorC; let admin;

before(async () => {
  api = await startServer();
  [student, vendorA, vendorC, admin] = await Promise.all([
    api.login('65010001'), api.login('shopa'), api.login('shopc'), api.login('admin', 'admin1234'),
  ]);
});
after(() => api.close());

const firstSlot = async (shopId) => (await api.call(`/shops/${shopId}`)).json.pickup_slots[0];

describe('ข้อมูลสาธารณะ', () => {
  test('health check', async () => {
    const r = await api.call('/health');
    assert.equal(r.status, 200);
    assert.equal(r.json.ok, true);
  });

  test('รายชื่อร้าน 5 ร้าน พร้อมคิวและสถานะเปิด', async () => {
    const r = await api.call('/shops');
    assert.equal(r.status, 200);
    assert.equal(r.json.length, 5);
    assert.ok(r.json.every((s) => s.open_now && typeof s.queue_count === 'number'));
  });

  test('ค้นหาด้วยชื่อเมนู และกรองตามหมวด', async () => {
    assert.equal((await api.call(`/shops?q=${encodeURIComponent('กะเพรา')}`)).json.length, 1);
    const noodles = (await api.call(`/shops?category=${encodeURIComponent('เส้น')}`)).json;
    assert.ok(noodles.length === 2 && noodles.every((s) => s.category === 'เส้น'));
    assert.equal((await api.call('/categories')).json.length, 3);
  });

  test('รายละเอียดร้าน: เมนู + ช่วงเวลารับอาหาร', async () => {
    const r = await api.call('/shops/1');
    assert.equal(r.json.menu.length, 4);
    assert.equal(r.json.pickup_slots[0], '11:15'); // 11:00 + เตรียม 5 นาที → ปัดเป็น 11:15
    assert.deepEqual((await api.call('/shops/1/slots')).json, r.json.pickup_slots);
    assert.equal((await api.call('/shops/999')).status, 404);
    assert.equal((await api.call('/shops/999/slots')).status, 404);
  });

  test('endpoint ที่ไม่มีอยู่ได้ 404 และ JSON เสียได้ 400', async () => {
    assert.equal((await api.call('/nope')).status, 404);
    const res = await fetch(`${api.base}/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{bad' });
    assert.equal(res.status, 400);
  });

  test('ค่า Google Sign-In ตอนยังไม่ตั้ง client ID', async () => {
    const r = await api.call('/auth/config');
    assert.equal(r.json.google_client_id, null);
    assert.equal(r.json.allowed_domain, 'kmitl.ac.th');
    assert.equal((await api.call('/auth/google', { body: { id_token: 'x' } })).status, 503);
  });
});

describe('บัญชีของฉัน', () => {
  test('me / stats / แก้ชื่อ', async () => {
    assert.equal((await api.call('/auth/me', { token: student })).json.username, '65010001');
    const stats = (await api.call('/auth/me/stats', { token: student })).json;
    assert.equal(typeof stats.orders_this_month, 'number');
    const r = await api.call('/auth/me', { token: student, method: 'PATCH', body: { name: 'สมชาย ทดสอบ' } });
    assert.equal(r.json.name, 'สมชาย ทดสอบ');
    assert.equal((await api.call('/auth/me', { token: student, method: 'PATCH', body: { name: 'x' } })).status, 400);
  });

  test('เปลี่ยนรหัสผ่าน แล้วล็อกอินด้วยรหัสใหม่ได้', async () => {
    const t = await api.login('65010003');
    assert.equal((await api.call('/auth/me/password', { token: t, method: 'PATCH', body: { current_password: 'wrong', new_password: 'abcd' } })).status, 400);
    assert.equal((await api.call('/auth/me/password', { token: t, method: 'PATCH', body: { current_password: '1234', new_password: '12' } })).status, 400);
    const r = await api.call('/auth/me/password', { token: t, method: 'PATCH', body: { current_password: '1234', new_password: 'abcd' } });
    assert.equal(r.status, 200);
    assert.ok(await api.login('65010003', 'abcd'));
  });

  test('สมัครด้วยรหัสผ่านถูกปิดไว้ (ต้องใช้ Google @kmitl.ac.th)', async () => {
    assert.equal((await api.call('/auth/register', { body: { username: '67010001', name: 'ใหม่', password: '1234' } })).status, 403);
  });

  test('เมนูโปรด: เพิ่ม / ดู / ลบ', async () => {
    assert.equal((await api.call('/favorites/16', { token: student, method: 'PUT' })).status, 200);
    assert.ok((await api.call('/favorites', { token: student })).json.some((f) => f.id === 16));
    await api.call('/favorites/16', { token: student, method: 'DELETE' });
    assert.ok(!(await api.call('/favorites', { token: student })).json.some((f) => f.id === 16));
    assert.equal((await api.call('/favorites/9999', { token: student, method: 'PUT' })).status, 404);
  });
});

describe('flow ออเดอร์: สั่ง → ร้านรับ → ทำ → พร้อม → รับแล้ว', () => {
  let orderId;

  test('สั่งอาหาร: ได้เลขคิว และราคาคำนวณจากฐานข้อมูล', async () => {
    const r = await api.call('/orders', {
      token: student,
      body: { shop_id: 1, items: [{ menu_item_id: 1, qty: 2 }, { menu_item_id: 3, qty: 1 }], pickup_time: await firstSlot(1), note: 'ไม่ใส่ผัก' },
    });
    assert.equal(r.status, 201);
    assert.equal(r.json.queue_no, 'A-001');
    assert.equal(r.json.total, 50 * 2 + 55);
    assert.equal(r.json.status, 'pending');
    assert.equal(r.json.item_count, 3);
    orderId = r.json.id;
  });

  test('ออเดอร์ที่ 2 ได้คิวถัดไป และเห็นคิวก่อนหน้า 1 คิว แล้วลูกค้ายกเลิกได้', async () => {
    const r = await api.call('/orders', { token: student, body: { shop_id: 1, items: [{ menu_item_id: 2, qty: 1 }], pickup_time: await firstSlot(1) } });
    assert.equal(r.json.queue_no, 'A-002');
    assert.equal(r.json.queue_ahead, 1);
    const c = await api.call(`/orders/${r.json.id}/cancel`, { token: student, method: 'POST' });
    assert.equal(c.json.status, 'cancelled');
  });

  test('รายการเดียวกันส่งซ้ำ ระบบรวมจำนวนให้', async () => {
    const r = await api.call('/orders', { token: student, body: { shop_id: 5, items: [{ menu_item_id: 16, qty: 1 }, { menu_item_id: 16, qty: 2 }], pickup_time: await firstSlot(5) } });
    assert.equal(r.json.items.length, 1);
    assert.equal(r.json.items[0].qty, 3);
    assert.equal(r.json.total, 90);
  });

  test('ร้านเห็นออเดอร์ และเปลี่ยนสถานะทีละขั้น', async () => {
    const active = (await api.call('/vendor/orders', { token: vendorA })).json;
    assert.ok(active.some((o) => o.id === orderId && o.note === 'ไม่ใส่ผัก'));
    for (const status of ['accepted', 'cooking', 'ready', 'completed']) {
      const r = await api.call(`/vendor/orders/${orderId}/status`, { token: vendorA, method: 'PATCH', body: { status } });
      assert.equal(r.json.status, status);
      assert.ok(r.json[`${status}_at`]);
    }
  });

  test('ข้ามขั้น / ย้อนสถานะไม่ได้ และยกเลิกออเดอร์ที่เสร็จแล้วไม่ได้', async () => {
    assert.equal((await api.call(`/vendor/orders/${orderId}/status`, { token: vendorA, method: 'PATCH', body: { status: 'cooking' } })).status, 409);
    assert.equal((await api.call(`/orders/${orderId}/cancel`, { token: student, method: 'POST' })).status, 409);
  });

  test('ร้านยกเลิกพร้อมเหตุผล ลูกค้าเห็นเหตุผล', async () => {
    const o = (await api.call('/orders', { token: student, body: { shop_id: 1, items: [{ menu_item_id: 4, qty: 1 }], pickup_time: await firstSlot(1) } })).json;
    await api.call(`/vendor/orders/${o.id}/status`, { token: vendorA, method: 'PATCH', body: { status: 'accepted' } });
    const r = await api.call(`/vendor/orders/${o.id}/status`, { token: vendorA, method: 'PATCH', body: { status: 'cancelled', reason: 'ของหมด' } });
    assert.equal(r.json.cancel_reason, 'ของหมด');
    assert.equal((await api.call(`/orders/${o.id}`, { token: student })).json.status, 'cancelled');
    // รับออเดอร์แล้วลูกค้ายกเลิกเองไม่ได้
    const o2 = (await api.call('/orders', { token: student, body: { shop_id: 1, items: [{ menu_item_id: 4, qty: 1 }], pickup_time: await firstSlot(1) } })).json;
    await api.call(`/vendor/orders/${o2.id}/status`, { token: vendorA, method: 'PATCH', body: { status: 'accepted' } });
    assert.equal((await api.call(`/orders/${o2.id}/cancel`, { token: student, method: 'POST' })).status, 409);
  });

  test('ประวัติ / ออเดอร์ที่ยังไม่เสร็จ / สรุปยอดร้าน', async () => {
    const history = (await api.call('/orders?scope=history', { token: student })).json;
    assert.ok(history.some((o) => o.id === orderId && o.status === 'completed'));
    const active = (await api.call('/orders?scope=active', { token: student })).json;
    assert.ok(active.every((o) => ['pending', 'accepted', 'cooking', 'ready'].includes(o.status)));
    const today = (await api.call('/vendor/orders?scope=today', { token: vendorA })).json;
    assert.ok(today.length >= 4);
    const sum = (await api.call('/vendor/summary', { token: vendorA })).json;
    assert.ok(sum.orders >= 4 && sum.revenue >= 155 && sum.cancelled >= 2);
    assert.equal(sum.top_items[0].name, 'ข้าวขาหมู');
  });

  test('สั่งไม่ได้: ตะกร้าว่าง / เวลารับไม่ถูก / เมนูหมด / ร้านปิด / จำนวนเกิน', async () => {
    const slot = await firstSlot(1);
    const order = (body) => api.call('/orders', { token: student, body: { shop_id: 1, pickup_time: slot, items: [{ menu_item_id: 1, qty: 1 }], ...body } });
    assert.equal((await order({ items: [] })).status, 400);
    assert.equal((await order({ pickup_time: '03:00' })).status, 409);
    assert.equal((await order({ items: [{ menu_item_id: 1, qty: 21 }] })).status, 400);
    assert.equal((await order({ note: 'x'.repeat(201) })).status, 400);
    assert.equal((await order({ payment_method: 'bitcoin' })).status, 400);
    assert.equal((await order({ shop_id: 999 })).status, 404);

    await api.call('/vendor/menu/1', { token: vendorA, method: 'PATCH', body: { is_available: false } });
    assert.equal((await order({})).status, 409);
    await api.call('/vendor/menu/1', { token: vendorA, method: 'PATCH', body: { is_available: true } });

    await api.call('/vendor/shop', { token: vendorA, method: 'PATCH', body: { is_open: false } });
    assert.equal((await order({})).status, 409);
    assert.deepEqual((await api.call('/shops/1')).json.pickup_slots, []);
    await api.call('/vendor/shop', { token: vendorA, method: 'PATCH', body: { is_open: true } });
  });
});

describe('ชำระเงินพร้อมเพย์ + สลิป', () => {
  let orderId;

  test('ร้านตั้งหมายเลขพร้อมเพย์ (ตรวจรูปแบบ)', async () => {
    assert.equal((await api.call('/vendor/shop', { token: vendorC, method: 'PATCH', body: { promptpay_id: '12345' } })).status, 400);
    const r = await api.call('/vendor/shop', { token: vendorC, method: 'PATCH', body: { promptpay_id: '081-234-5678' } });
    assert.equal(r.json.promptpay_id, '0812345678');
    assert.equal((await api.call('/shops/3')).json.promptpay_enabled, true);
  });

  test('ร้านที่ไม่มีพร้อมเพย์ เลือกโอนไม่ได้', async () => {
    const r = await api.call('/orders', { token: student, body: { shop_id: 2, items: [{ menu_item_id: 5, qty: 1 }], pickup_time: await firstSlot(2), payment_method: 'promptpay' } });
    assert.equal(r.status, 409);
  });

  test('สั่งแบบโอน → ได้ QR ที่มียอดเงิน', async () => {
    const o = await api.call('/orders', { token: student, body: { shop_id: 3, items: [{ menu_item_id: 9, qty: 2 }], pickup_time: await firstSlot(3), payment_method: 'promptpay' } });
    assert.equal(o.json.payment_method, 'promptpay');
    assert.equal(o.json.payment_status, 'unpaid');
    orderId = o.json.id;
    const p = (await api.call(`/orders/${orderId}/payment`, { token: student })).json;
    assert.equal(p.amount, 110);
    assert.equal(p.promptpay_masked, '081-xxx-5678');
    assert.ok(p.qr_payload.includes('0066812345678') && p.qr_payload.includes('5406110.00'));
  });

  test('แนบสลิป → ร้านดูสลิป → ปฏิเสธ → แนบใหม่ → ยืนยัน', async () => {
    let r = await api.call(`/orders/${orderId}/slip`, { token: student, raw: PNG, type: 'image/png' });
    assert.equal(r.json.payment_status, 'slip_uploaded');
    assert.equal(r.json.has_slip, true);

    r = await api.call(`/vendor/orders/${orderId}/slip`, { token: vendorC });
    assert.equal(r.headers.get('content-type'), 'image/png');
    assert.equal(r.headers.get('cache-control'), 'private, no-store');
    assert.deepEqual(r.bytes, PNG);
    assert.deepEqual((await api.call(`/orders/${orderId}/slip`, { token: student })).bytes, PNG);

    r = await api.call(`/vendor/orders/${orderId}/payment`, { token: vendorC, method: 'PATCH', body: { action: 'reject', reason: 'ยอดไม่ตรง' } });
    assert.equal(r.json.payment_status, 'rejected');
    assert.equal(r.json.payment_note, 'ยอดไม่ตรง');

    r = await api.call(`/orders/${orderId}/slip`, { token: student, raw: JPEG, type: 'image/jpeg' });
    assert.equal(r.json.payment_status, 'slip_uploaded');
    assert.equal(r.json.payment_note, null);

    r = await api.call(`/vendor/orders/${orderId}/payment`, { token: vendorC, method: 'PATCH', body: { action: 'confirm' } });
    assert.equal(r.json.payment_status, 'paid');
    assert.ok(r.json.paid_at);
  });

  test('หลังจ่ายแล้ว: ไม่มี QR, แนบสลิปซ้ำ/ยืนยันซ้ำ/ปฏิเสธไม่ได้', async () => {
    assert.equal((await api.call(`/orders/${orderId}/payment`, { token: student })).json.qr_payload, null);
    assert.equal((await api.call(`/orders/${orderId}/slip`, { token: student, raw: JPEG, type: 'image/jpeg' })).status, 409);
    assert.equal((await api.call(`/vendor/orders/${orderId}/payment`, { token: vendorC, method: 'PATCH', body: { action: 'confirm' } })).status, 409);
    assert.equal((await api.call(`/vendor/orders/${orderId}/payment`, { token: vendorC, method: 'PATCH', body: { action: 'reject' } })).status, 409);
    assert.equal((await api.call(`/vendor/orders/${orderId}/payment`, { token: vendorC, method: 'PATCH', body: { action: 'refund' } })).status, 400);
  });

  test('จ่ายที่ร้าน: แนบสลิปไม่ได้ ร้านกดรับเงินสดได้', async () => {
    const o = (await api.call('/orders', { token: student, body: { shop_id: 3, items: [{ menu_item_id: 10, qty: 1 }], pickup_time: await firstSlot(3) } })).json;
    assert.equal(o.payment_method, 'cash');
    assert.equal((await api.call(`/orders/${o.id}/slip`, { token: student, raw: PNG, type: 'image/png' })).status, 409);
    assert.equal((await api.call(`/orders/${o.id}/slip`, { token: student })).status, 404);
    assert.equal((await api.call(`/vendor/orders/${o.id}/slip`, { token: vendorC })).status, 404);
    const r = await api.call(`/vendor/orders/${o.id}/payment`, { token: vendorC, method: 'PATCH', body: { action: 'confirm' } });
    assert.equal(r.json.payment_status, 'paid');
  });

  test('ออเดอร์ที่ยกเลิกแล้วแนบสลิปไม่ได้', async () => {
    const o = (await api.call('/orders', { token: student, body: { shop_id: 3, items: [{ menu_item_id: 11, qty: 1 }], pickup_time: await firstSlot(3), payment_method: 'promptpay' } })).json;
    await api.call(`/orders/${o.id}/cancel`, { token: student, method: 'POST' });
    assert.equal((await api.call(`/orders/${o.id}/slip`, { token: student, raw: PNG, type: 'image/png' })).status, 409);
  });

  test('ปิดรับโอนพร้อมเพย์', async () => {
    const r = await api.call('/vendor/shop', { token: vendorC, method: 'PATCH', body: { promptpay_id: '' } });
    assert.equal(r.json.promptpay_id, null);
    assert.equal(r.json.promptpay_enabled, false);
  });
});

describe('ร้านค้า: เมนู รูป และข้อมูลร้าน', () => {
  test('เพิ่ม / แก้ / ลบเมนู (เมนูโปรดที่อ้างถึงถูกลบตาม)', async () => {
    const m = await api.call('/vendor/menu', { token: vendorA, body: { name: 'เมนูทดสอบ', price: 39, description: 'ทดสอบ' } });
    assert.equal(m.status, 201);
    const id = m.json.id;
    assert.equal((await api.call(`/vendor/menu/${id}`, { token: vendorA, method: 'PATCH', body: { price: 45, sort_order: 9 } })).json.price, 45);
    await api.call(`/favorites/${id}`, { token: student, method: 'PUT' });
    assert.equal((await api.call(`/vendor/menu/${id}`, { token: vendorA, method: 'DELETE' })).status, 200);
    assert.ok(!(await api.call('/favorites', { token: student })).json.some((f) => f.id === id));
    assert.equal((await api.call(`/vendor/menu/${id}`, { token: vendorA, method: 'DELETE' })).status, 404);
    assert.ok((await api.call('/vendor/menu', { token: vendorA })).json.length >= 4);
  });

  test('ตรวจข้อมูลเมนู: ไม่มีชื่อ / ราคาติดลบ / ราคาทศนิยม', async () => {
    for (const body of [{ price: 10 }, { name: 'x', price: -1 }, { name: 'x', price: 9.5 }, { name: ' ', price: 10 }]) {
      assert.equal((await api.call('/vendor/menu', { token: vendorA, body })).status, 400, JSON.stringify(body));
    }
    assert.equal((await api.call('/vendor/menu/1', { token: vendorA, method: 'PATCH', body: { price: 'abc' } })).status, 400);
  });

  test('รูปเมนู: อัปโหลด → แสดงสาธารณะ → เปลี่ยนรูป (รูปเก่าถูกลบ) → ลบรูป', async () => {
    let r = await api.call('/vendor/menu/2/image', { token: vendorA, raw: JPEG, type: 'image/jpeg' });
    const url1 = r.json.image_url;
    assert.match(url1, /^\/api\/images\/\d+$/);
    const img = await api.call(url1.replace('/api', ''));
    assert.equal(img.headers.get('content-type'), 'image/jpeg');
    assert.match(img.headers.get('cache-control'), /immutable/);
    assert.equal((await api.call('/shops/1')).json.menu.find((m) => m.id === 2).image_url, url1);

    r = await api.call('/vendor/menu/2/image', { token: vendorA, raw: WEBP, type: 'image/webp' });
    const url2 = r.json.image_url;
    assert.notEqual(url2, url1);
    assert.equal((await api.call(url1.replace('/api', ''))).status, 404);
    assert.equal((await api.call(url2.replace('/api', ''))).headers.get('content-type'), 'image/webp');

    r = await api.call('/vendor/menu/2/image', { token: vendorA, method: 'DELETE' });
    assert.equal(r.json.image_url, null);
    assert.equal((await api.call(url2.replace('/api', ''))).status, 404);
  });

  test('ลบเมนูที่มีรูป รูปถูกลบตาม', async () => {
    const id = (await api.call('/vendor/menu', { token: vendorA, body: { name: 'มีรูป', price: 20 } })).json.id;
    const url = (await api.call(`/vendor/menu/${id}/image`, { token: vendorA, raw: PNG, type: 'image/png' })).json.image_url;
    await api.call(`/vendor/menu/${id}`, { token: vendorA, method: 'DELETE' });
    assert.equal((await api.call(url.replace('/api', ''))).status, 404);
  });

  test('รูปร้าน: อัปโหลดแล้วนักศึกษาเห็น ลบได้', async () => {
    let r = await api.call('/vendor/shop/image', { token: vendorA, raw: PNG, type: 'image/png' });
    assert.match(r.json.image_url, /^\/api\/images\/\d+$/);
    assert.equal((await api.call('/shops/1')).json.image_url, r.json.image_url);
    r = await api.call('/vendor/shop/image', { token: vendorA, method: 'DELETE' });
    assert.equal(r.json.image_url, null);
  });

  test('แก้ข้อมูลร้าน: เวลา/เวลารอ ตรวจความถูกต้อง', async () => {
    const r = await api.call('/vendor/shop', { token: vendorA, method: 'PATCH', body: { description: 'ร้านอร่อย', prep_min: 6, prep_max: 12, open_time: '07:00', close_time: '17:30' } });
    assert.equal(r.json.prep_min, 6);
    assert.equal(r.json.description, 'ร้านอร่อย');
    assert.equal((await api.call('/vendor/shop', { token: vendorA })).json.close_time, '17:30');
    for (const body of [{ open_time: '25:00' }, { close_time: 'x' }, { open_time: '18:00' }, { prep_min: 20 }, { prep_min: -1 }]) {
      assert.equal((await api.call('/vendor/shop', { token: vendorA, method: 'PATCH', body })).status, 400, JSON.stringify(body));
    }
  });
});

describe('ผู้ดูแล (admin)', () => {
  test('ภาพรวม 14 วัน: ยอดรายวัน ยอดแยกร้าน เมนูขายดี', async () => {
    const r = (await api.call('/admin/summary?days=14', { token: admin })).json;
    assert.equal(r.daily.length, 14);
    assert.equal(r.by_shop.length, 5);
    assert.ok(r.daily.slice(0, 13).every((d) => d.orders > 0)); // seed มีประวัติย้อนหลังทุกวัน
    assert.equal(r.top_items.length, 5);
    assert.equal(r.counts.shops, 5);
    assert.ok(r.today.orders > 0);
  });

  test('จัดการร้าน: เพิ่ม / แก้ / ลบ / รหัสคิวซ้ำ / ลบร้านที่มีออเดอร์ไม่ได้', async () => {
    const shops = (await api.call('/admin/shops', { token: admin })).json;
    assert.equal(shops[0].owners[0].username, 'shopa');
    let r = await api.call('/admin/shops', { token: admin, body: { code: 'z', name: 'ร้านทดสอบ', category: 'อื่นๆ', open_time: '08:00', close_time: '15:00' } });
    assert.equal(r.status, 201);
    assert.equal(r.json.code, 'Z');
    const id = r.json.id;
    assert.equal((await api.call('/admin/shops', { token: admin, body: { code: 'Z', name: 'ซ้ำ', category: 'อื่นๆ' } })).status, 409);
    assert.equal((await api.call('/admin/shops', { token: admin, body: { code: '1', name: 'x', category: 'อื่นๆ' } })).status, 400);
    assert.equal((await api.call('/admin/shops', { token: admin, body: { code: 'Y', category: 'อื่นๆ' } })).status, 400);
    r = await api.call(`/admin/shops/${id}`, { token: admin, method: 'PATCH', body: { name: 'ร้านทดสอบ 2', is_open: false } });
    assert.equal(r.json.name, 'ร้านทดสอบ 2');
    assert.equal(r.json.is_open, false);
    assert.equal((await api.call(`/admin/shops/${id}`, { token: admin, method: 'PATCH', body: { code: 'A' } })).status, 409);
    assert.equal((await api.call(`/admin/shops/${id}`, { token: admin, method: 'DELETE' })).status, 200);
    assert.equal((await api.call(`/admin/shops/${id}`, { token: admin, method: 'DELETE' })).status, 404);
    assert.equal((await api.call('/admin/shops/999', { token: admin, method: 'PATCH', body: {} })).status, 404);
    assert.equal((await api.call('/admin/shops/1', { token: admin, method: 'DELETE' })).status, 409);
  });

  test('จัดการผู้ใช้: สร้างบัญชีร้าน → ล็อกอินได้ → ระงับ → ล็อกอินไม่ได้', async () => {
    const vendors = (await api.call('/admin/users?role=vendor', { token: admin })).json;
    assert.equal(vendors.length, 5);
    assert.equal((await api.call(`/admin/users?q=${encodeURIComponent('สมหญิง')}`, { token: admin })).json.length, 1);

    let r = await api.call('/admin/users', { token: admin, body: { username: 'shopa2', name: 'ผู้ช่วยร้าน A', password: 'pass1', role: 'vendor', shop_id: 1 } });
    assert.equal(r.status, 201);
    assert.equal(r.json.shop.id, 1);
    const id = r.json.id;
    const t = await api.login('shopa2', 'pass1');
    assert.equal((await api.call('/vendor/shop', { token: t })).json.id, 1);

    assert.equal((await api.call('/admin/users', { token: admin, body: { username: 'shopa2', name: 'x', password: '1234' } })).status, 409);
    assert.equal((await api.call('/admin/users', { token: admin, body: { username: 'v9', name: 'x', password: '1234', role: 'vendor', shop_id: 999 } })).status, 400);
    assert.equal((await api.call('/admin/users', { token: admin, body: { username: 'v9', name: 'x', password: '12' } })).status, 400);
    assert.equal((await api.call('/admin/users', { token: admin, body: { username: 'v9', name: 'x', password: '1234', role: 'root' } })).status, 400);
    assert.equal((await api.call('/admin/users', { token: admin, body: { username: 'v9' } })).status, 400);

    r = await api.call(`/admin/users/${id}`, { token: admin, method: 'PATCH', body: { is_active: false, password: 'newpass' } });
    assert.equal(r.json.is_active, false);
    assert.equal((await api.call('/auth/login', { body: { username: 'shopa2', password: 'newpass' } })).status, 403);
    assert.equal((await api.call('/vendor/shop', { token: t })).status, 401); // token เดิมใช้ไม่ได้ทันที

    r = await api.call(`/admin/users/${id}`, { token: admin, method: 'PATCH', body: { role: 'student', is_active: true } });
    assert.equal(r.json.role, 'student');
    assert.equal(r.json.shop, null);
    assert.equal((await api.call(`/admin/users/${id}`, { token: admin, method: 'PATCH', body: { name: '' } })).status, 400);
    assert.equal((await api.call(`/admin/users/${id}`, { token: admin, method: 'PATCH', body: { role: 'x' } })).status, 400);
    assert.equal((await api.call('/admin/users/9999', { token: admin, method: 'PATCH', body: {} })).status, 404);
  });

  test('แอดมินลดสิทธิ์หรือระงับบัญชีตัวเองไม่ได้', async () => {
    assert.equal((await api.call('/admin/users/1', { token: admin, method: 'PATCH', body: { role: 'student' } })).status, 400);
    assert.equal((await api.call('/admin/users/1', { token: admin, method: 'PATCH', body: { is_active: false } })).status, 400);
  });

  test('ออเดอร์ทั้งหมด: กรองตามร้าน / สถานะ / วันที่', async () => {
    const byShop = (await api.call('/admin/orders?shop_id=1', { token: admin })).json;
    assert.ok(byShop.length > 0 && byShop.every((o) => o.shop.id === 1));
    const done = (await api.call('/admin/orders?status=completed', { token: admin })).json;
    assert.ok(done.every((o) => o.status === 'completed'));
    const today = (await api.call('/admin/orders?date=2026-10-20', { token: admin })).json;
    assert.ok(today.length > 0);
  });
});

describe('AI แนะนำเมนู', () => {
  const chat = (text, token = student) => api.call('/ai/chat', { token, body: { messages: [{ role: 'user', text }] } });

  test('ไม่มี Gemini key → ใช้ตัวแนะนำแบบกฎ ตามงบและไม่เผ็ด', async () => {
    const r = await chat('งบ 50 บาท ไม่เผ็ด');
    assert.equal(r.status, 200);
    assert.equal(r.json.source, 'rules');
    assert.ok(r.json.items.length > 0 && r.json.items.length <= 3);
    assert.ok(r.json.items.every((i) => i.price <= 50 && !/กะเพรา|ต้มยำ|พริก/.test(i.name)));
  });

  test('ตัวแนะนำแบบกฎ: หมวดเส้น / เครื่องดื่ม / ไม่กินหมู / หาไม่เจอ', async () => {
    const t = await api.login('65010004');
    const noodles = (await chat('อยากกินก๋วยเตี๋ยว', t)).json.items;
    assert.ok(noodles.every((i) => [2, 4].includes(i.shop_id)));
    const drinks = (await chat('ขอเครื่องดื่มเย็นๆ', t)).json.items;
    assert.ok(drinks.every((i) => i.shop_id === 5));
    const noPork = (await chat('ไม่กินหมู ขอข้าว', t)).json.items;
    assert.ok(noPork.every((i) => !/หมู/.test(i.name)));
    const none = (await chat('งบ 5 บาท', t)).json;
    assert.equal(none.items.length, 0);
    assert.match(none.reply, /ยังไม่เจอ/);
    const deadline = (await chat('ต้องได้ก่อน 11:10', t)).json;
    assert.equal(deadline.items.length, 0);
  });

  test('ใช้ Gemini เมื่อมี key และกรองเมนูที่ AI แต่งขึ้นเองทิ้ง', async (t) => {
    process.env.GEMINI_API_KEY = 'test-key';
    const realFetch = globalThis.fetch;
    let sentPrompt = '';
    t.mock.method(globalThis, 'fetch', async (url, init) => {
      if (!String(url).includes('generativelanguage.googleapis.com')) return realFetch(url, init);
      sentPrompt = JSON.parse(init.body).systemInstruction.parts[0].text;
      const answer = { reply: 'ลองข้าวมันไก่ทอดดูไหม', picks: [{ menu_item_id: 2, reason: 'คิวน้อย' }, { menu_item_id: 9999, reason: 'เมนูที่ไม่มีจริง' }] };
      return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: JSON.stringify(answer) }] } }] }), { status: 200 });
    });
    try {
      const r = (await chat('แนะนำหน่อย', await api.login('65010005'))).json;
      assert.equal(r.source, 'gemini');
      assert.equal(r.reply, 'ลองข้าวมันไก่ทอดดูไหม');
      assert.deepEqual(r.items.map((i) => i.menu_item_id), [2]);
      assert.ok(!sentPrompt.includes('image_url')); // ไม่ส่งข้อมูลที่ไม่จำเป็นให้ AI
    } finally {
      delete process.env.GEMINI_API_KEY;
    }
  });

  test('Gemini ล่มทั้ง 2 โมเดล → ตกไปใช้ตัวแนะนำแบบกฎ', async (t) => {
    process.env.GEMINI_API_KEY = 'test-key';
    const realFetch = globalThis.fetch;
    let calls = 0;
    t.mock.method(globalThis, 'fetch', async (url, init) => {
      if (!String(url).includes('generativelanguage.googleapis.com')) return realFetch(url, init);
      calls++;
      return new Response('overloaded', { status: 503 });
    });
    t.mock.method(console, 'error', () => {});
    try {
      const r = (await chat('งบ 60', await api.login('66010010'))).json;
      assert.equal(r.source, 'rules');
      assert.equal(calls, 2);
    } finally {
      delete process.env.GEMINI_API_KEY;
    }
  });

  test('ข้อความว่างได้ 400', async () => {
    assert.equal((await api.call('/ai/chat', { token: student, body: { messages: [] } })).status, 400);
    assert.equal((await api.call('/ai/chat', { token: student, body: { messages: [{ role: 'assistant', text: 'hi' }] } })).status, 400);
  });
});
