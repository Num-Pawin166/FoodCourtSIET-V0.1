// ตัวช่วยของ integration / security test: เปิด API จริงบนพอร์ตสุ่ม กับฐานข้อมูล SQLite ชั่วคราว
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { mock } from 'node:test';

// ต้องตั้ง env ก่อน import โค้ดใน src (db.js อ่านค่าตอนโหลด) — ไม่แตะ Turso / Gemini / Google จริง
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'foodcourt-test-'));
process.env.DB_PATH = path.join(dir, 'test.db');
for (const k of ['TURSO_DATABASE_URL', 'TURSO_AUTH_TOKEN', 'GEMINI_API_KEY', 'GOOGLE_CLIENT_ID', 'ALLOW_PASSWORD_REGISTER']) delete process.env[k];

/** เวลาทดสอบคงที่: อังคาร 20 ต.ค. 2026 11:00 น. (เวลาไทย) — ทุกร้านเปิด ผลไม่ขึ้นกับเวลาที่รัน CI */
export const NOW = new Date('2026-10-20T04:00:00Z');

// รูปขั้นต่ำที่ผ่านการตรวจ magic bytes
export const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(64, 1)]);
export const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 2)]);
export const WEBP = Buffer.concat([Buffer.from('RIFF'), Buffer.alloc(4), Buffer.from('WEBP'), Buffer.alloc(32, 3)]);

export async function startServer() {
  mock.timers.enable({ apis: ['Date'], now: NOW });
  const { initSchema, db } = await import('../src/db.js');
  const { seedIfEmpty } = await import('../src/seed.js');
  const { createApp } = await import('../src/app.js');
  await initSchema();
  await seedIfEmpty();
  const server = createApp().listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api`;

  /** เรียก API: body = JSON, raw = ไฟล์ดิบ (Buffer) */
  async function call(p, { token, body, raw, type = 'application/json', method } = {}) {
    const res = await fetch(base + p, {
      method: method || (body !== undefined || raw ? 'POST' : 'GET'),
      headers: { 'content-type': raw ? type : 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: raw ?? (body !== undefined ? JSON.stringify(body) : undefined),
    });
    const ct = res.headers.get('content-type') || '';
    return {
      status: res.status,
      headers: res.headers,
      json: ct.includes('json') ? await res.json() : null,
      bytes: ct.startsWith('image') ? Buffer.from(await res.arrayBuffer()) : null,
    };
  }
  const login = async (username, password = '1234') => {
    const r = await call('/auth/login', { body: { username, password } });
    if (r.status !== 200) throw new Error(`login ${username} failed: ${r.status}`);
    return r.json.token;
  };
  const close = async () => {
    await new Promise((resolve) => server.close(resolve));
    mock.timers.reset();
  };
  return { call, login, close, db, base };
}
