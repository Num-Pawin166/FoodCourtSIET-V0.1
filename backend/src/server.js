import { db, initSchema, isRemote } from './db.js';
import { createApp } from './app.js';
import { seedIfEmpty } from './seed.js';

const PORT = Number(process.env.PORT) || 3000;

await initSchema();
await seedIfEmpty();

const app = createApp();

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
