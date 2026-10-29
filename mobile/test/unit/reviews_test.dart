import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/models.dart';
import 'package:foodcourt_siet/reviews.dart';
import '../support/fake_backend.dart';

/// Unit test: รีวิวร้านบน Cloud Firestore (ใช้ Firestore จำลองในหน่วยความจำ)
void main() {
  late FakeFirebaseFirestore db;
  late ReviewService reviews;
  late FakeBackend backend;

  setUp(() {
    db = FakeFirebaseFirestore();
    reviews = fakeReviews(db);
    backend = FakeBackend();
  });

  Order completed({int shopId = 1}) => Order.fromJson(backend.addCompletedOrder(shopId: shopId));

  Future<void> seed(String id, {required int shopId, required int rating, required DateTime at, String uid = 'other'}) =>
      db.collection('reviews').doc(id).set({
        'shopId': shopId, 'orderId': int.parse(id.split('_').last), 'rating': rating, 'comment': '',
        'authorName': 'คนอื่น', 'authorUid': uid, 'updatedAt': Timestamp.fromDate(at),
      });

  group('submit', () {
    test('บันทึกลง reviews/order_<id> พร้อมข้อมูลครบ ชื่อย่อ และ uid ของผู้รีวิว', () async {
      final order = completed();
      await reviews.submit(order: order, rating: 4, comment: '  อร่อย คิวเร็ว  ', authorName: 'สมชาย ใจดี');
      final doc = await db.collection('reviews').doc('order_${order.id}').get();
      expect(doc.exists, isTrue);
      final d = doc.data()!;
      expect(d['shopId'], 1);
      expect(d['orderId'], order.id);
      expect(d['rating'], 4);
      expect(d['comment'], 'อร่อย คิวเร็ว');
      expect(d['authorName'], 'สมชาย ใ.');
      expect(d['authorUid'], 'uid-me');
      expect(d['updatedAt'], isA<Timestamp>());
      expect(d.keys, unorderedEquals(['shopId', 'orderId', 'rating', 'comment', 'authorName', 'authorUid', 'updatedAt']));
    });

    test('ส่งซ้ำ = แก้รีวิวเดิม (1 ออเดอร์มีรีวิวเดียว)', () async {
      final order = completed();
      await reviews.submit(order: order, rating: 5, comment: 'ดีมาก', authorName: 'สมชาย');
      await reviews.submit(order: order, rating: 2, comment: 'รอบนี้ช้า', authorName: 'สมชาย');
      final all = await db.collection('reviews').get();
      expect(all.docs, hasLength(1));
      expect(all.docs.single.data()['rating'], 2);
    });

    test('คะแนนต้องอยู่ระหว่าง 1–5', () async {
      for (final r in [0, 6, -1]) {
        await expectLater(reviews.submit(order: completed(), rating: r, comment: '', authorName: 'a'), throwsArgumentError);
      }
      expect((await db.collection('reviews').get()).docs, isEmpty);
    });

    test('รีวิวได้เฉพาะออเดอร์ที่รับอาหารแล้ว', () async {
      final pending = Order.fromJson({...backend.addCompletedOrder(), 'status': 'pending'});
      await expectLater(reviews.submit(order: pending, rating: 5, comment: '', authorName: 'a'), throwsStateError);
    });

    test('ความคิดเห็นยาวเกิน 300 ตัวอักษรถูกปฏิเสธ (นับหลังตัดช่องว่าง)', () async {
      await expectLater(reviews.submit(order: completed(), rating: 5, comment: 'ก' * 301, authorName: 'a'), throwsArgumentError);
      await reviews.submit(order: completed(), rating: 5, comment: '  ${'ก' * 300}  ', authorName: 'a');
    });

    test('ล็อกอิน Firebase ไม่ได้ → ส่ง error กลับ ไม่บันทึก', () async {
      final broken = ReviewService(db, signIn: () async => throw Exception('auth disabled'));
      await expectLater(broken.submit(order: completed(), rating: 5, comment: '', authorName: 'a'), throwsException);
      expect((await db.collection('reviews').get()).docs, isEmpty);
    });
  });

  group('watch', () {
    test('watchShop: เฉพาะร้านนั้น เรียงใหม่สุดก่อน', () async {
      await seed('order_1', shopId: 1, rating: 3, at: DateTime(2026, 10, 1));
      await seed('order_2', shopId: 1, rating: 5, at: DateTime(2026, 10, 5));
      await seed('order_3', shopId: 2, rating: 1, at: DateTime(2026, 10, 9));
      final list = await reviews.watchShop(1).first;
      expect(list.map((r) => r.orderId), [2, 1]);
      expect(list.first.updatedAt, DateTime(2026, 10, 5));
      expect(ReviewService.average(list), 4);
    });

    test('watchShop อัปเดตทันทีเมื่อมีรีวิวใหม่ (real-time)', () async {
      final emitted = <int>[];
      final sub = reviews.watchShop(1).listen((l) => emitted.add(l.length));
      await pumpEventQueue();
      await reviews.submit(order: completed(), rating: 5, comment: '', authorName: 'a');
      await pumpEventQueue();
      await sub.cancel();
      expect(emitted, [0, 1]);
    });

    test('watchOrder: ยังไม่รีวิว = null แล้วได้รีวิวหลังส่ง', () async {
      final order = completed();
      expect(await reviews.watchOrder(order.id).first, isNull);
      await reviews.submit(order: order, rating: 4, comment: 'ok', authorName: 'สมชาย ใจดี');
      final mine = await reviews.watchOrder(order.id).first;
      expect(mine!.rating, 4);
      expect(mine.id, 'order_${order.id}');
      expect(mine.authorUid, 'uid-me');
    });

    test('Firebase ใช้ไม่ได้ → stream ส่ง error (หน้าจอแสดงข้อความแทน)', () async {
      final broken = ReviewService(db, signIn: () async => throw Exception('offline'));
      await expectLater(broken.watchShop(1), emitsError(isException));
    });
  });

  test('average ของรายการว่าง = 0', () => expect(ReviewService.average([]), 0));

  test('shortName ย่อนามสกุลเพื่อความเป็นส่วนตัว', () {
    expect(ReviewService.shortName('สมชาย ใจดี'), 'สมชาย ใ.');
    expect(ReviewService.shortName('  Somchai   Jaidee  '), 'Somchai J.');
    expect(ReviewService.shortName('สมชาย'), 'สมชาย');
    expect(ReviewService.shortName('   '), 'นักศึกษา');
    expect(ReviewService.shortName('ก' * 50).length, 40);
  });

  test('init: ไม่ใช่ Android (เช่น เว็บ/เดสก์ท็อป) → ปิดฟีเจอร์รีวิว', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await ReviewService.init(), isNull);
    expect(ReviewService.initError, isNull);
  });

  test('init บน Android แต่เปิด Firebase ไม่ได้ → คืน null และเก็บสาเหตุไว้แสดง', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android; // ในเทสต์ไม่มี Firebase native → ล้มเหลวแน่นอน
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      ReviewService.initError = null;
    });
    expect(await ReviewService.init(), isNull);
    expect(ReviewService.initError, isNotNull);
  });
}
