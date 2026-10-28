import express from 'express';
import { db } from './db.js';
import { HttpError } from './util.js';

export const MAX_IMAGE_BYTES = 2 * 1024 * 1024;

/** รับไฟล์รูปดิบใน body (Content-Type: image/jpeg|png|webp) */
export const rawImage = express.raw({ type: ['image/*', 'application/octet-stream'], limit: MAX_IMAGE_BYTES });

/** ดูชนิดไฟล์จาก magic bytes (ไม่เชื่อ Content-Type จาก client) */
function sniffMime(buf) {
  if (buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length > 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.length > 12 && buf.subarray(0, 4).toString() === 'RIFF' && buf.subarray(8, 12).toString() === 'WEBP') return 'image/webp';
  return null;
}

/** ตรวจ body แล้วบันทึกรูป คืน id */
export async function storeImage(req, kind) {
  const buf = req.body;
  if (!Buffer.isBuffer(buf) || buf.length === 0) throw new HttpError(400, 'ไม่พบไฟล์รูป');
  const mime = sniffMime(buf);
  if (!mime) throw new HttpError(400, 'รองรับเฉพาะรูป JPG, PNG หรือ WebP');
  const info = await db.run('INSERT INTO images (kind, mime, data, uploaded_by) VALUES (?, ?, ?, ?)',
    kind, mime, new Uint8Array(buf), req.user?.id ?? null);
  return info.lastInsertRowid;
}

export async function sendImage(res, id, kind) {
  const img = await db.get('SELECT mime, data FROM images WHERE id = ? AND kind = ?', id, kind);
  if (!img) throw new HttpError(404, 'ไม่พบรูป');
  res.set('Content-Type', img.mime);
  // รูปเมนูไม่เปลี่ยนตาม id (เปลี่ยนรูป = id ใหม่) จึง cache ได้นาน; สลิปเป็นข้อมูลส่วนตัว ห้าม cache สาธารณะ
  res.set('Cache-Control', kind === 'menu' ? 'public, max-age=31536000, immutable' : 'private, no-store');
  res.send(Buffer.from(img.data));
}

export const imageUrl = (id) => (id ? `/api/images/${id}` : null);
