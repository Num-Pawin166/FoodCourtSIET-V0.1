import express from 'express';
import cors from 'cors';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { HttpError } from './util.js';
import authRoutes from './routes/auth.js';
import shopRoutes from './routes/shops.js';
import orderRoutes from './routes/orders.js';
import vendorRoutes from './routes/vendor.js';
import adminRoutes from './routes/admin.js';
import aiRoutes from './routes/ai.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** สร้าง Express app (แยกจาก server.js เพื่อให้ test เปิดบนพอร์ตสุ่มได้) */
export function createApp() {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '100kb' }));

  app.get('/api/health', (_req, res) => res.json({ ok: true, time: new Date().toISOString() }));
  app.use('/api/auth', authRoutes);
  app.use('/api', shopRoutes);
  app.use('/api/orders', orderRoutes);
  app.use('/api/vendor', vendorRoutes);
  app.use('/api/admin', adminRoutes);
  app.use('/api/ai', aiRoutes);
  app.use('/api', (_req, _res) => { throw new HttpError(404, 'ไม่พบ endpoint นี้'); });

  // หน้าเว็บหลังบ้าน (ร้านค้า + แอดมิน)
  app.use(express.static(path.join(__dirname, '..', 'public')));

  app.use((err, _req, res, _next) => {
    const status = err.status || (err.type === 'entity.parse.failed' ? 400 : 500);
    const expected = err instanceof HttpError || status < 500; // error ที่เราตั้งใจโยน แสดงข้อความได้
    if (!expected) console.error(err);
    res.status(status).json({ error: expected ? err.message : 'เกิดข้อผิดพลาดในระบบ' });
  });
  return app;
}
