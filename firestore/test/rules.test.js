// Security test ของ firestore.rules — รันบน Firestore Emulator จริงของ Google
// npm test  (ต้องมี Java 11+)
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, getDocs, collection, query, where, serverTimestamp, setDoc, setLogLevel, updateDoc } from 'firebase/firestore';

setLogLevel('silent'); // ไม่ต้องพิมพ์ PERMISSION_DENIED ที่ตั้งใจให้เกิด

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-foodcourt',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const alice = () => env.authenticatedContext('alice').firestore();
const bob = () => env.authenticatedContext('bob').firestore();
const guest = () => env.unauthenticatedContext().firestore();

const review = (over = {}) => ({
  shopId: 1, orderId: 101, rating: 5, comment: 'อร่อยมาก', authorName: 'สมชาย ใ.', authorUid: 'alice',
  updatedAt: serverTimestamp(), ...over,
});

/** ใส่รีวิวของ alice ไว้ก่อน โดยข้าม rules */
async function seedAliceReview() {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'reviews/order_101'), { ...review(), updatedAt: new Date() }));
}

describe('อ่านรีวิว', () => {
  test('ผู้ใช้ที่ผ่าน Firebase Auth อ่านรีวิวของร้านได้', async () => {
    await seedAliceReview();
    await assertSucceeds(getDocs(query(collection(bob(), 'reviews'), where('shopId', '==', 1))));
    await assertSucceeds(getDoc(doc(bob(), 'reviews/order_101')));
  });

  test('ไม่ได้ล็อกอิน → อ่านไม่ได้', async () => {
    await seedAliceReview();
    await assertFails(getDoc(doc(guest(), 'reviews/order_101')));
  });
});

describe('สร้างรีวิว', () => {
  test('สร้างรีวิวของตัวเองได้', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'reviews/order_101'), review()));
  });

  test('ไม่ได้ล็อกอิน → สร้างไม่ได้', async () => {
    await assertFails(setDoc(doc(guest(), 'reviews/order_101'), review()));
  });

  test('ปลอมเป็นคนอื่น (authorUid ไม่ใช่ตัวเอง) → ไม่ได้', async () => {
    await assertFails(setDoc(doc(bob(), 'reviews/order_101'), review()));
  });

  test('doc id ไม่ตรงกับเลขออเดอร์ → ไม่ได้', async () => {
    await assertFails(setDoc(doc(alice(), 'reviews/order_999'), review()));
    await assertFails(setDoc(doc(alice(), 'reviews/anything'), review()));
  });

  test('คะแนนนอกช่วง 1–5 หรือไม่ใช่จำนวนเต็ม → ไม่ได้', async () => {
    for (const rating of [0, 6, -1, 4.5, '5']) {
      await assertFails(setDoc(doc(alice(), 'reviews/order_101'), review({ rating })));
    }
  });

  test('ความคิดเห็นยาวเกิน 300 ตัว / ชื่อว่างหรือยาวเกิน → ไม่ได้', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'reviews/order_101'), review({ comment: 'ก'.repeat(300) })));
    await env.clearFirestore();
    await assertFails(setDoc(doc(alice(), 'reviews/order_101'), review({ comment: 'ก'.repeat(301) })));
    await assertFails(setDoc(doc(alice(), 'reviews/order_101'), review({ authorName: '' })));
    await assertFails(setDoc(doc(alice(), 'reviews/order_101'), review({ authorName: 'x'.repeat(61) })));
  });

  test('แนบฟิลด์แปลกปลอม (เช่น verified, isAdmin) → ไม่ได้', async () => {
    await assertFails(setDoc(doc(alice(), 'reviews/order_101'), review({ verified: true })));
  });

  test('ปลอมเวลา (ไม่ใช้เวลาเซิร์ฟเวอร์) → ไม่ได้', async () => {
    await assertFails(setDoc(doc(alice(), 'reviews/order_101'), review({ updatedAt: new Date('2020-01-01') })));
  });
});

describe('แก้ / ลบรีวิว', () => {
  test('เจ้าของแก้คะแนนและความคิดเห็นได้', async () => {
    await seedAliceReview();
    await assertSucceeds(updateDoc(doc(alice(), 'reviews/order_101'), { rating: 3, comment: 'ช้าไปนิด', updatedAt: serverTimestamp() }));
  });

  test('คนอื่นแก้รีวิวของเราไม่ได้ (รวมถึงเขียนทับทั้ง doc)', async () => {
    await seedAliceReview();
    await assertFails(updateDoc(doc(bob(), 'reviews/order_101'), { rating: 1, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(bob(), 'reviews/order_101'), review({ authorUid: 'bob', rating: 1 })));
  });

  test('เจ้าของย้ายรีวิวไปร้านอื่น / เปลี่ยนเจ้าของ → ไม่ได้', async () => {
    await seedAliceReview();
    await assertFails(updateDoc(doc(alice(), 'reviews/order_101'), { shopId: 2, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), 'reviews/order_101'), { authorUid: 'bob', updatedAt: serverTimestamp() }));
  });

  test('ไม่มีใครลบรีวิวผ่านแอปได้ แม้แต่เจ้าของ', async () => {
    await seedAliceReview();
    await assertFails(deleteDoc(doc(alice(), 'reviews/order_101')));
  });
});

test('collection อื่นอ่าน/เขียนไม่ได้เลย', async () => {
  await assertFails(getDoc(doc(alice(), 'users/alice')));
  await assertFails(setDoc(doc(alice(), 'orders/1'), { total: 0 }));
});
