import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_vendor/reviews.dart';
import '../support/fake_backend.dart';

/// Unit test: ร้านค้าอ่านรีวิวร้านตัวเองจาก Firestore (Firestore จำลองในหน่วยความจำ)
void main() {
  late FakeFirebaseFirestore db;
  late ReviewFeed feed;

  setUp(() {
    db = FakeFirebaseFirestore();
    feed = fakeFeed(db);
  });

  test('watchShop: เฉพาะรีวิวของร้านตัวเอง เรียงใหม่สุดก่อน', () async {
    await seedReview(db, 1, 3, day: 1);
    await seedReview(db, 2, 5, day: 5, comment: 'อร่อย');
    await seedReview(db, 3, 1, shopId: 2, day: 9);
    final list = await feed.watchShop(1).first;
    expect(list.map((r) => r.orderId), [2, 1]);
    expect(list.first.comment, 'อร่อย');
    expect(list.first.authorName, 'สมชาย ใ.');
    expect(list.first.updatedAt, DateTime(2026, 10, 5, 12));
  });

  test('watchShop อัปเดตทันทีเมื่อนักศึกษารีวิวใหม่ (real-time)', () async {
    final sizes = <int>[];
    final sub = feed.watchShop(1).listen((l) => sizes.add(l.length));
    await pumpEventQueue();
    await seedReview(db, 7, 4);
    await pumpEventQueue();
    await sub.cancel();
    expect(sizes, [0, 1]);
  });

  test('Firebase ล็อกอินไม่ได้ → stream ส่ง error', () async {
    final broken = ReviewFeed(db, signIn: () async => throw Exception('offline'));
    await expectLater(broken.watchShop(1), emitsError(isException));
  });

  test('average และ distribution (จำนวนรีวิวแยกตามดาว)', () async {
    for (final (id, r) in [(1, 5), (2, 5), (3, 4), (4, 2)]) {
      await seedReview(db, id, r);
    }
    final list = await feed.watchShop(1).first;
    expect(ReviewFeed.average(list), 4);
    expect(ReviewFeed.distribution(list), [0, 1, 0, 1, 2]);
    expect(ReviewFeed.average([]), 0);
    expect(ReviewFeed.distribution([]), [0, 0, 0, 0, 0]);
  });

  test('init: ไม่ใช่ Android → ปิดฟีเจอร์ / Android แต่เปิด Firebase ไม่ได้ → เก็บสาเหตุไว้', () async {
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      ReviewFeed.initError = null;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(await ReviewFeed.init(), isNull);
    expect(ReviewFeed.initError, isNull);

    debugDefaultTargetPlatformOverride = TargetPlatform.android; // ในเทสต์ไม่มี Firebase native → ล้มเหลว
    expect(await ReviewFeed.init(), isNull);
    expect(ReviewFeed.initError, isNotNull);
  });
}
