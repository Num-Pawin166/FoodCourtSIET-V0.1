// Unit test: ฟังก์ชันล้วนที่ไม่ต้องใช้ฐานข้อมูล
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import './helpers.js'; // ตั้ง env ให้ใช้ DB ชั่วคราวก่อนโหลด src
import { normalizePromptPayId, maskPromptPayId, promptPayPayload } from '../src/promptpay.js';
import {
  toMinutes, fromMinutes, isHHMM, localDate, localTime, startOfDayIso, startOfMonthIso, pickupSlots, isShopOpenNow,
  serializeShop, serializeMenuItem, requireInt, pick, placeholders, NEXT_STATUS, HttpError,
} from '../src/util.js';

/** CRC-16/CCITT-FALSE เขียนแยกอีกแบบ (แบบตาราง) เพื่อตรวจผลของ promptpay.js */
function crcReference(str) {
  const table = Array.from({ length: 256 }, (_, n) => {
    let c = n << 8;
    for (let k = 0; k < 8; k++) c = c & 0x8000 ? (c << 1) ^ 0x1021 : c << 1;
    return c & 0xffff;
  });
  let crc = 0xffff;
  for (const b of Buffer.from(str)) crc = ((crc << 8) ^ table[((crc >> 8) ^ b) & 0xff]) & 0xffff;
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/** แยก TLV ระดับบนของ payload EMVCo เป็น { tag: value } */
function parseTlv(s) {
  const out = {};
  for (let i = 0; i < s.length;) {
    const tag = s.slice(i, i + 2);
    const len = Number(s.slice(i + 2, i + 4));
    out[tag] = s.slice(i + 4, i + 4 + len);
    i += 4 + len;
  }
  return out;
}

describe('promptpay', () => {
  test('normalizePromptPayId รับเบอร์มือถือ / เลขบัตร 13 หลัก / e-Wallet 15 หลัก', () => {
    assert.equal(normalizePromptPayId('081-234-5678'), '0812345678');
    assert.equal(normalizePromptPayId('1 2345 67890 12 3'), '1234567890123');
    assert.equal(normalizePromptPayId('123456789012345'), '123456789012345');
  });

  test('normalizePromptPayId ปฏิเสธค่าที่ไม่ถูกต้อง', () => {
    for (const bad of ['12345', '1812345678', '', null, undefined, '08123456789', 'abc']) {
      assert.equal(normalizePromptPayId(bad), null, String(bad));
    }
  });

  test('maskPromptPayId ปิดบางส่วนของหมายเลข', () => {
    assert.equal(maskPromptPayId('0812345678'), '081-xxx-5678');
    assert.equal(maskPromptPayId('1234567890123'), '1-xxxx-xxxxx-12-3');
    assert.equal(maskPromptPayId(null), null);
  });

  test('payload เบอร์มือถือ: โครงสร้าง EMVCo ถูกต้อง และ CRC ตรงกับการคำนวณอิสระ', () => {
    const payload = promptPayPayload('0812345678', 155);
    const f = parseTlv(payload);
    assert.equal(f['00'], '01');
    assert.equal(f['01'], '12');
    assert.equal(f['29'], '0016A000000677010111' + '01130066812345678');
    assert.equal(f['53'], '764');
    assert.equal(f['54'], '155.00');
    assert.equal(f['58'], 'TH');
    assert.equal(f['63'], crcReference(payload.slice(0, -4)));
  });

  test('payload เลขบัตรประชาชนใช้ tag 02, e-Wallet ใช้ tag 03 และยอดมีทศนิยม 2 ตำแหน่ง', () => {
    assert.match(parseTlv(promptPayPayload('1234567890123', 50))['29'], /02131234567890123$/);
    assert.match(parseTlv(promptPayPayload('123456789012345', 50))['29'], /0315123456789012345$/);
    assert.equal(parseTlv(promptPayPayload('0812345678', 49.5))['54'], '49.50');
  });

  test('payload โยน error เมื่อหมายเลขไม่ถูกต้อง', () => {
    assert.throws(() => promptPayPayload('123', 10), /invalid PromptPay ID/);
  });
});

describe('เวลา (เวลาไทยเสมอ)', () => {
  test('toMinutes / fromMinutes แปลงกลับไปมาได้', () => {
    assert.equal(toMinutes('11:45'), 705);
    assert.equal(fromMinutes(705), '11:45');
    assert.equal(fromMinutes(toMinutes('07:05')), '07:05');
  });

  test('isHHMM ตรวจรูปแบบเวลา', () => {
    for (const ok of ['00:00', '09:30', '23:59']) assert.ok(isHHMM(ok), ok);
    for (const bad of ['24:00', '9:30', '12:60', '', null, 1230]) assert.ok(!isHHMM(bad), String(bad));
  });

  test('localDate / localTime ใช้เขต Asia/Bangkok ไม่ขึ้นกับเครื่อง', () => {
    const d = new Date('2026-10-19T18:30:00Z'); // = 20 ต.ค. 01:30 เวลาไทย
    assert.equal(localDate(d), '2026-10-20');
    assert.equal(localTime(d), '01:30');
  });

  test('startOfDayIso / startOfMonthIso คืนเที่ยงคืนเวลาไทยเป็น UTC', () => {
    assert.equal(startOfDayIso('2026-10-20'), '2026-10-19T17:00:00.000Z');
    assert.equal(startOfMonthIso(new Date('2026-10-20T04:00:00Z')), '2026-09-30T17:00:00.000Z');
  });
});

describe('ร้านและช่วงเวลารับอาหาร', () => {
  const shop = { id: 1, code: 'A', name: 'ร้าน', is_open: 1, open_time: '08:00', close_time: '12:00', prep_min: 10, prep_max: 15, promptpay_id: null };
  const at = (hhmm) => new Date(`2026-10-20T${hhmm}:00+07:00`);

  test('pickupSlots เริ่มหลังเวลาเตรียม ปัดขึ้นทุก 15 นาที', () => {
    assert.deepEqual(pickupSlots(shop, at('10:07')).slice(0, 3), ['10:30', '10:45', '11:00']);
  });

  test('pickupSlots ไม่เกินเวลาปิดร้าน และไม่เกิน 9 ช่อง', () => {
    assert.deepEqual(pickupSlots(shop, at('11:30')), ['11:45', '12:00']);
    assert.equal(pickupSlots({ ...shop, close_time: '20:00' }, at('08:00')).length, 9);
  });

  test('pickupSlots ก่อนร้านเปิดเริ่มที่เวลาเปิด และร้านปิดสวิตช์ได้ช่องว่าง', () => {
    assert.equal(pickupSlots(shop, at('06:00'))[0], '08:00');
    assert.deepEqual(pickupSlots({ ...shop, is_open: 0 }, at('10:00')), []);
  });

  test('isShopOpenNow ดูทั้งสวิตช์และเวลาทำการ', () => {
    assert.equal(isShopOpenNow(shop, at('10:00')), true);
    assert.equal(isShopOpenNow(shop, at('12:00')), false); // ปิดตรงเวลาปิด
    assert.equal(isShopOpenNow(shop, at('07:59')), false);
    assert.equal(isShopOpenNow({ ...shop, is_open: 0 }, at('10:00')), false);
  });

  test('serializeShop ไม่ส่งหมายเลขพร้อมเพย์จริงออกไป', () => {
    const out = serializeShop({ ...shop, promptpay_id: '0812345678' }, new Map([[1, 3]]));
    assert.equal(out.queue_count, 3);
    assert.equal(out.promptpay_enabled, true);
    assert.ok(!('promptpay_id' in out));
  });

  test('serializeMenuItem แปลง is_available เป็น boolean', () => {
    const m = serializeMenuItem({ id: 1, shop_id: 1, name: 'x', description: '', price: 40, is_available: 0, image_url: null, sort_order: 0 });
    assert.equal(m.is_available, false);
  });
});

describe('ตัวช่วยทั่วไป', () => {
  test('requireInt รับจำนวนเต็ม และโยน HttpError 400 เมื่อไม่ใช่', () => {
    assert.equal(requireInt('42', 'id'), 42);
    assert.throws(() => requireInt('4.2', 'id'), (e) => e instanceof HttpError && e.status === 400);
    assert.throws(() => requireInt('abc', 'id'), HttpError);
  });

  test('pick เลือกเฉพาะ key ที่มีค่า', () => {
    assert.deepEqual(pick({ a: 1, b: undefined, c: 3 }, ['a', 'b']), { a: 1 });
  });

  test('placeholders สร้าง ? ตามจำนวน', () => {
    assert.equal(placeholders([1, 2, 3]), '?, ?, ?');
  });

  test('NEXT_STATUS: ออเดอร์ที่จบแล้วเปลี่ยนสถานะต่อไม่ได้ และห้ามข้ามขั้น', () => {
    assert.deepEqual(NEXT_STATUS.completed, []);
    assert.deepEqual(NEXT_STATUS.cancelled, []);
    assert.ok(!NEXT_STATUS.pending.includes('cooking'));
  });
});
