import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import { OAuth2Client } from 'google-auth-library';
import { db } from '../db.js';
import { HttpError, auth, signToken, publicUser, startOfMonthIso } from '../util.js';

const r = Router();

// Google Sign-In: ใช้ Web client ID ตัวเดียวทั้งเว็บและ Android (Android ส่งเป็น serverClientId)
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '';
const ALLOWED_DOMAIN = (process.env.ALLOWED_EMAIL_DOMAIN || 'kmitl.ac.th').toLowerCase();
const googleClient = new OAuth2Client();

// แอปดึงค่านี้ไปตั้งค่าปุ่ม Google (client ID ไม่ใช่ความลับ)
r.get('/config', (_req, res) => {
  res.json({ google_client_id: GOOGLE_CLIENT_ID || null, allowed_domain: ALLOWED_DOMAIN });
});

r.post('/google', async (req, res) => {
  if (!GOOGLE_CLIENT_ID) throw new HttpError(503, 'ยังไม่ได้ตั้งค่า Google Sign-In ที่เซิร์ฟเวอร์');
  const idToken = String(req.body?.id_token || '');
  if (!idToken) throw new HttpError(400, 'ไม่มี id_token');

  let p;
  try {
    const ticket = await googleClient.verifyIdToken({ idToken, audience: GOOGLE_CLIENT_ID });
    p = ticket.getPayload();
  } catch {
    throw new HttpError(401, 'ยืนยันตัวตนกับ Google ไม่สำเร็จ กรุณาลองใหม่');
  }
  const email = String(p?.email || '').toLowerCase();
  // hd = Google Workspace domain ของบัญชี — ตรวจทั้ง hd และท้ายอีเมล กันบัญชี gmail ที่ตั้งชื่อคล้าย
  if (!p?.email_verified || p.hd !== ALLOWED_DOMAIN || !email.endsWith(`@${ALLOWED_DOMAIN}`)) {
    throw new HttpError(403, `ใช้ได้เฉพาะอีเมล @${ALLOWED_DOMAIN} เท่านั้น`);
  }

  const localPart = email.split('@')[0];
  let user = await db.get('SELECT * FROM users WHERE email = ?', email);
  if (!user) {
    // บัญชีเดิมที่ใช้รหัสนักศึกษาเดียวกัน (เช่น 65010001) → ผูกอีเมลเข้ากับบัญชีนั้น
    const existing = await db.get(`SELECT * FROM users WHERE username = ? AND email IS NULL AND role = 'student'`, localPart);
    if (existing) {
      await db.run('UPDATE users SET email = ? WHERE id = ?', email, existing.id);
    } else {
      if (await db.get('SELECT 1 FROM users WHERE username = ?', localPart)) {
        throw new HttpError(409, 'ชื่อผู้ใช้นี้ถูกใช้แล้ว กรุณาติดต่อผู้ดูแล');
      }
      // ไม่มีรหัสผ่าน: เก็บ hash ของค่าสุ่มที่ไม่มีใครรู้ ล็อกอินด้วยรหัสผ่านไม่ได้
      const unusable = bcrypt.hashSync(crypto.randomBytes(32).toString('hex'), 10);
      await db.run(`INSERT INTO users (username, name, email, password_hash, role) VALUES (?, ?, ?, ?, 'student')`,
        localPart, String(p.name || localPart).slice(0, 100), email, unusable);
    }
    user = await db.get('SELECT * FROM users WHERE email = ?', email);
  }
  if (!user.is_active) throw new HttpError(403, 'บัญชีนี้ถูกระงับ');
  res.json({ token: signToken(user), user: await publicUser(user) });
});

r.post('/login', async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) throw new HttpError(400, 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน');
  const user = await db.get('SELECT * FROM users WHERE username = ?', String(username).trim());
  if (!user || !bcrypt.compareSync(String(password), user.password_hash)) {
    throw new HttpError(401, 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
  }
  if (!user.is_active) throw new HttpError(403, 'บัญชีนี้ถูกระงับ');
  res.json({ token: signToken(user), user: await publicUser(user) });
});

// สมัครด้วยรหัสผ่าน: ปิดไว้ (นักศึกษาใช้ Google @kmitl.ac.th) เปิดได้ด้วย ALLOW_PASSWORD_REGISTER=true
r.post('/register', async (req, res) => {
  if (process.env.ALLOW_PASSWORD_REGISTER !== 'true') throw new HttpError(403, 'กรุณาเข้าสู่ระบบด้วยบัญชี Google @kmitl.ac.th');
  const { username, name, password } = req.body || {};
  if (!/^\d{8}$/.test(String(username || ''))) throw new HttpError(400, 'รหัสนักศึกษาต้องเป็นตัวเลข 8 หลัก');
  if (!name || String(name).trim().length < 2) throw new HttpError(400, 'กรุณากรอกชื่อ-นามสกุล');
  if (!password || String(password).length < 4) throw new HttpError(400, 'รหัสผ่านต้องมีอย่างน้อย 4 ตัวอักษร');
  if (await db.get('SELECT 1 FROM users WHERE username = ?', username)) throw new HttpError(409, 'รหัสนักศึกษานี้มีบัญชีแล้ว');
  const info = await db.run(`INSERT INTO users (username, name, password_hash, role) VALUES (?, ?, ?, 'student')`,
    String(username), String(name).trim(), bcrypt.hashSync(String(password), 10));
  const user = await db.get('SELECT * FROM users WHERE id = ?', info.lastInsertRowid);
  res.status(201).json({ token: signToken(user), user: await publicUser(user) });
});

r.get('/me', auth(), async (req, res) => res.json(await publicUser(req.user)));

// สถิติหน้า "บัญชีของฉัน": ออเดอร์เดือนนี้ / ยอดใช้จ่ายเดือนนี้
r.get('/me/stats', auth(), async (req, res) => {
  const row = await db.get(
    `SELECT COUNT(*) AS orders, COALESCE(SUM(total), 0) AS spent
     FROM orders WHERE user_id = ? AND created_at >= ? AND status != 'cancelled'`,
    req.user.id, startOfMonthIso(),
  );
  res.json({ orders_this_month: row.orders, spent_this_month: row.spent });
});

r.patch('/me/password', auth(), async (req, res) => {
  const { current_password, new_password } = req.body || {};
  if (!bcrypt.compareSync(String(current_password || ''), req.user.password_hash)) throw new HttpError(400, 'รหัสผ่านเดิมไม่ถูกต้อง');
  if (!new_password || String(new_password).length < 4) throw new HttpError(400, 'รหัสผ่านใหม่ต้องมีอย่างน้อย 4 ตัวอักษร');
  await db.run('UPDATE users SET password_hash = ? WHERE id = ?', bcrypt.hashSync(String(new_password), 10), req.user.id);
  res.json({ ok: true });
});

export default r;
