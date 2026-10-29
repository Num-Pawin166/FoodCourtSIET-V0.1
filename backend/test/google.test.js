// Integration + Security: ล็อกอินด้วย Google (จำลองผลตรวจ id_token ของ Google ไม่ต่อเน็ตจริง)
import { test, describe, before, after, mock } from 'node:test';
import assert from 'node:assert/strict';
import { OAuth2Client } from 'google-auth-library';
import { startServer } from './helpers.js';

let api;
/** payload ที่ "Google" จะตอบกลับในเทสต์ถัดไป (null = token ไม่ผ่าน) */
let googlePayload = null;

before(async () => {
  process.env.GOOGLE_CLIENT_ID = 'test-client.apps.googleusercontent.com';
  mock.method(OAuth2Client.prototype, 'verifyIdToken', async ({ audience }) => {
    assert.equal(audience, process.env.GOOGLE_CLIENT_ID); // ต้องตรวจว่า token ออกให้แอปเราจริง
    if (!googlePayload) throw new Error('invalid token');
    return { getPayload: () => googlePayload };
  });
  api = await startServer();
});
after(() => api.close());

const google = (payload) => {
  googlePayload = payload;
  return api.call('/auth/google', { body: { id_token: 'fake.jwt.token' } });
};

describe('Google Sign-In', () => {
  test('/auth/config ส่ง client ID ให้แอป', async () => {
    assert.equal((await api.call('/auth/config')).json.google_client_id, 'test-client.apps.googleusercontent.com');
  });

  test('ไม่มี id_token → 400, token ไม่ผ่านการตรวจ → 401', async () => {
    assert.equal((await api.call('/auth/google', { body: {} })).status, 400);
    assert.equal((await google(null)).status, 401);
  });

  test('บัญชี @kmitl.ac.th ใหม่ → สร้างบัญชีนักศึกษาอัตโนมัติ', async () => {
    const r = await google({ email: '67019999@kmitl.ac.th', email_verified: true, hd: 'kmitl.ac.th', name: 'นักศึกษา ใหม่' });
    assert.equal(r.status, 200);
    assert.equal(r.json.user.username, '67019999');
    assert.equal(r.json.user.role, 'student');
    assert.equal(r.json.user.email, '67019999@kmitl.ac.th');
    assert.equal((await api.call('/auth/me', { token: r.json.token })).json.name, 'นักศึกษา ใหม่');
    // บัญชีที่สร้างจาก Google ล็อกอินด้วยรหัสผ่านไม่ได้
    assert.equal((await api.call('/auth/login', { body: { username: '67019999', password: '' } })).status, 400);
  });

  test('ล็อกอินซ้ำได้บัญชีเดิม', async () => {
    const a = await google({ email: '67019999@kmitl.ac.th', email_verified: true, hd: 'kmitl.ac.th' });
    assert.equal(a.status, 200);
    assert.equal((await api.db.get(`SELECT COUNT(*) AS n FROM users WHERE username = '67019999'`)).n, 1);
  });

  test('รหัสนักศึกษาที่มีบัญชีอยู่แล้ว → ผูกอีเมลเข้ากับบัญชีเดิม (ประวัติไม่หาย)', async () => {
    const r = await google({ email: '65010001@kmitl.ac.th', email_verified: true, hd: 'kmitl.ac.th' });
    assert.equal(r.json.user.username, '65010001');
    assert.equal(r.json.user.name, 'สมชาย ใจดี');
    assert.equal(r.json.user.email, '65010001@kmitl.ac.th');
  });

  test('ชื่อผู้ใช้ชนกับบัญชีร้าน/แอดมิน → 409 (ไม่ยึดบัญชีคนอื่น)', async () => {
    const r = await google({ email: 'admin@kmitl.ac.th', email_verified: true, hd: 'kmitl.ac.th' });
    assert.equal(r.status, 409);
    assert.equal((await api.db.get(`SELECT email FROM users WHERE username = 'admin'`)).email, null);
  });

  test('ปฏิเสธ gmail และบัญชีที่ hd ไม่ใช่ kmitl.ac.th → 403', async () => {
    assert.equal((await google({ email: 'someone@gmail.com', email_verified: true })).status, 403);
    assert.equal((await google({ email: 'x@kmitl.ac.th', email_verified: true, hd: 'other.ac.th' })).status, 403);
    assert.equal((await google({ email: 'x@kmitl.ac.th', email_verified: false, hd: 'kmitl.ac.th' })).status, 403);
  });

  test('บัญชีที่ถูกระงับเข้าด้วย Google ไม่ได้', async () => {
    await api.db.run(`UPDATE users SET is_active = 0 WHERE username = '67019999'`);
    assert.equal((await google({ email: '67019999@kmitl.ac.th', email_verified: true, hd: 'kmitl.ac.th' })).status, 403);
  });
});

describe('สมัครด้วยรหัสผ่าน (เปิดด้วย ALLOW_PASSWORD_REGISTER)', () => {
  before(() => { process.env.ALLOW_PASSWORD_REGISTER = 'true'; });
  after(() => { delete process.env.ALLOW_PASSWORD_REGISTER; });

  test('ตรวจรหัสนักศึกษา ชื่อ รหัสผ่าน และห้ามซ้ำ', async () => {
    const reg = (body) => api.call('/auth/register', { body });
    assert.equal((await reg({ username: '123', name: 'ชื่อ', password: '1234' })).status, 400);
    assert.equal((await reg({ username: '67010001', name: 'x', password: '1234' })).status, 400);
    assert.equal((await reg({ username: '67010001', name: 'ชื่อ ทดสอบ', password: '1' })).status, 400);
    assert.equal((await reg({ username: '65010001', name: 'ชื่อ ทดสอบ', password: '1234' })).status, 409);
    const r = await reg({ username: '67010001', name: 'ชื่อ ทดสอบ', password: '1234' });
    assert.equal(r.status, 201);
    assert.ok(await api.login('67010001'));
  });
});
