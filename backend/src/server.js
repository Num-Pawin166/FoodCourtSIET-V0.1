import express from 'express';
import cors from 'cors';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { db, initSchema, isRemote } from './db.js';
import { HttpError } from './util.js';
import authRoutes from './routes/auth.js';
import shopRoutes from './routes/shops.js';
import orderRoutes from './routes/orders.js';
import vendorRoutes from './routes/vendor.js';
import adminRoutes from './routes/admin.js';
import aiRoutes from './routes/ai.js';
import { seedIfEmpty } from './seed.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT) || 3000;

await initSchema();
await seedIfEmpty();

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

const shopCount = (await db.get('SELECT COUNT(*) AS n FROM shops')).n;

app.listen(PORT, '0.0.0.0', (err) => {
  // Express 5 ส่ง error ตอนเปิดพอร์ตไม่ได้มาที่ callback นี้ (ไม่โยนออกไปเอง)
  if (err) {
    console.error(err.code === 'EADDRINUSE'
      ? `❌ พอร์ต ${PORT} ถูกใช้อยู่ — มี backend อีกตัวเปิดค้างอยู่ ปิดตัวนั้นก่อน หรือใช้ตัวที่เปิดอยู่ต่อได้เลย`
      : `❌ เปิดเซิร์ฟเวอร์ไม่ได้: ${err.message}`);
    process.exit(1);
  }
  console.log(`FoodCourt SIET API  ->  http://localhost:${PORT}/api   (${shopCount} shops)`);
  console.log(`Database            ->  ${isRemote ? 'Turso (cloud)' : 'local SQLite file (data/foodcourt.db)'}`);
  console.log(`Back office (web)   ->  http://localhost:${PORT}/`);
  console.log(`Google Sign-In      ->  ${process.env.GOOGLE_CLIENT_ID ? `@${process.env.ALLOWED_EMAIL_DOMAIN || "kmitl.ac.th"} only` : "not configured (set GOOGLE_CLIENT_ID in backend/.env)"}`);
  console.log(`AI menu assistant   ->  ${process.env.GEMINI_API_KEY ? `Gemini (${process.env.GEMINI_MODEL || 'gemini-3.5-flash'}, fallback ${process.env.GEMINI_FALLBACK_MODEL || 'gemini-3.5-flash-lite'})` : 'rule-based (set GEMINI_API_KEY in backend/.env to use Gemini)'}`);
});
