import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/reviews.dart';
import 'package:foodcourt_siet/screens/orders_screen.dart';
import 'package:foodcourt_siet/screens/shop_menu_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';

/// Widget test: รีวิวร้าน (Firestore) ในหน้าร้าน และในแท็บประวัติ
void main() {
  late FakeBackend backend;
  late FakeFirebaseFirestore db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
    db = FakeFirebaseFirestore();
  });

  Future<void> seed(int orderId, int rating, String name, String comment, {int shopId = 1, int day = 1}) =>
      db.collection('reviews').doc('order_$orderId').set({
        'shopId': shopId, 'orderId': orderId, 'rating': rating, 'comment': comment, 'authorName': name,
        'authorUid': 'someone', 'updatedAt': Timestamp.fromDate(DateTime(2026, 10, day, 12)),
      });

  group('หน้าร้าน', () {
    testWidgets('ยังไม่มีรีวิว → บอกวิธีรีวิว', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend, reviews: fakeReviews(db));
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      expect(find.text('รีวิวจากลูกค้า'), findsOneWidget);
      expect(find.text('ยังไม่มีรีวิว รับอาหารแล้วรีวิวได้ที่หน้าประวัติ'), findsOneWidget);
    });

    testWidgets('คะแนนเฉลี่ย + 2 รีวิวล่าสุด + ดูทั้งหมด (ไม่รวมรีวิวร้านอื่น)', (tester) async {
      usePhoneScreen(tester);
      await seed(1, 5, 'สมชาย ใ.', 'อร่อยมาก', day: 3);
      await seed(2, 4, 'มานี ม.', 'คิวเร็ว', day: 2);
      await seed(3, 3, 'ปิติ ส.', 'พอใช้', day: 1);
      await seed(4, 1, 'ร้านอื่น', 'ไม่ควรเห็น', shopId: 2);
      final state = await signedInState(backend, reviews: fakeReviews(db));
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('4.0'), findsOneWidget);
      expect(find.text('(3 รีวิว)'), findsOneWidget);
      expect(find.text('อร่อยมาก'), findsOneWidget);
      expect(find.text('คิวเร็ว'), findsOneWidget);
      expect(find.text('พอใช้'), findsNothing);
      expect(find.text('ไม่ควรเห็น'), findsNothing);

      await tester.tap(find.text('ดูทั้งหมด'));
      await tester.pumpAndSettle();
      expect(find.text('รีวิวทั้งหมด (3)'), findsOneWidget);
      expect(find.text('พอใช้'), findsOneWidget);
    });

    testWidgets('มีคนรีวิวใหม่ขณะเปิดหน้าอยู่ → ขึ้นทันที (real-time)', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend, reviews: fakeReviews(db));
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      await tester.runAsync(() => seed(9, 5, 'เพื่อน ก.', 'เพิ่งกินมา'));
      await tester.pumpAndSettle();
      expect(find.text('เพิ่งกินมา'), findsOneWidget);
      expect(find.text('(1 รีวิว)'), findsOneWidget);
    });

    testWidgets('เชื่อม Firebase ไม่ได้ → แสดงข้อความ แต่หน้าร้านยังใช้ได้', (tester) async {
      usePhoneScreen(tester);
      final broken = ReviewService(db, signIn: () async => throw Exception('offline'));
      final state = await signedInState(backend, reviews: broken);
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      expect(find.text('โหลดรีวิวไม่ได้ในขณะนี้'), findsOneWidget);
      expect(find.text('ข้าวขาหมู'), findsOneWidget);
    });

    testWidgets('ไม่มี Firebase (เช่น เว็บ) → ไม่แสดงส่วนรีวิว', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      expect(find.text('รีวิวจากลูกค้า'), findsNothing);
      expect(find.textContaining('ระบบรีวิวใช้งานไม่ได้'), findsNothing);
    });

    testWidgets('Android แต่เปิด Firebase ไม่ได้ → แสดงสาเหตุ (ไม่ซ่อนเงียบ)', (tester) async {
      usePhoneScreen(tester);
      ReviewService.initError = Exception('no network');
      addTearDown(() => ReviewService.initError = null);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      expect(find.textContaining('ระบบรีวิวใช้งานไม่ได้: Exception: no network'), findsOneWidget);
    });
  });

  group('แท็บประวัติ', () {
    Future<void> openHistory(WidgetTester tester, {ReviewService? reviews}) async {
      final state = await signedInState(backend, reviews: reviews ?? fakeReviews(db));
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ประวัติ'));
      await tester.pumpAndSettle();
    }

    testWidgets('ให้คะแนน → ส่งรีวิว → การ์ดแสดง "รีวิวแล้ว" → แก้รีวิวได้', (tester) async {
      usePhoneScreen(tester);
      final order = backend.addCompletedOrder();
      await openHistory(tester);

      await tester.tap(find.text('ให้คะแนนร้าน'));
      await tester.pumpAndSettle();
      expect(find.text('รีวิว ร้านข้าวขาหมูป้าแดง'), findsOneWidget);
      // ยังไม่เลือกดาว → กดส่งไม่ได้
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'ส่งรีวิว')).onPressed, isNull);

      await tester.tap(find.byTooltip('4 ดาว'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ขาหมูนุ่มมาก');
      await tester.tap(find.text('ส่งรีวิว'));
      await tester.pumpAndSettle();

      expect(find.text('ขอบคุณสำหรับรีวิว!'), findsOneWidget);
      final saved = (await db.collection('reviews').doc('order_${order['id']}').get()).data()!;
      expect(saved['rating'], 4);
      expect(saved['comment'], 'ขาหมูนุ่มมาก');
      expect(saved['authorName'], 'สมชาย ใ.');
      expect(find.text('รีวิวแล้ว · แตะเพื่อแก้'), findsOneWidget);

      // แก้: ข้อมูลเดิมถูกเติมไว้ให้
      await tester.tap(find.text('รีวิวแล้ว · แตะเพื่อแก้'));
      await tester.pumpAndSettle();
      expect(find.text('ขาหมูนุ่มมาก'), findsOneWidget);
      await tester.tap(find.byTooltip('2 ดาว'));
      await tester.pump();
      await tester.tap(find.text('บันทึกการแก้ไข'));
      await tester.pumpAndSettle();
      expect((await db.collection('reviews').doc('order_${order['id']}').get()).data()!['rating'], 2);
      expect((await db.collection('reviews').get()).docs, hasLength(1));
    });

    testWidgets('ส่งรีวิวไม่สำเร็จ → แจ้ง error และ sheet ยังเปิดอยู่ให้ลองใหม่', (tester) async {
      usePhoneScreen(tester);
      backend.addCompletedOrder();
      var calls = 0;
      // อ่านได้ (ครั้งแรก) แต่ตอนส่งล็อกอิน Firebase ไม่ผ่าน
      final flaky = ReviewService(db, signIn: () async => calls++ < 1 ? 'uid-me' : throw Exception('ส่งไม่สำเร็จ'));
      await openHistory(tester, reviews: flaky);
      await tester.tap(find.text('ให้คะแนนร้าน'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('5 ดาว'));
      await tester.pump();
      await tester.tap(find.text('ส่งรีวิว'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ส่งไม่สำเร็จ'), findsOneWidget);
      expect(find.text('ส่งรีวิว'), findsOneWidget);
      expect((await db.collection('reviews').get()).docs, isEmpty);
    });

    testWidgets('ออเดอร์ที่ยกเลิก → ไม่มีปุ่มรีวิว', (tester) async {
      usePhoneScreen(tester);
      backend.addCompletedOrder()['status'] = 'cancelled';
      await openHistory(tester);
      expect(find.text('ให้คะแนนร้าน'), findsNothing);
    });
  });
}
