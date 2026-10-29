import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_vendor/reviews.dart';
import 'package:foodcourt_vendor/screens/reviews_screen.dart';
import 'package:foodcourt_vendor/screens/vendor_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';

/// Widget test: แท็บ "รีวิว" ของแอปร้านค้า
void main() {
  late FakeVendorBackend backend;
  late FakeFirebaseFirestore db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeVendorBackend();
    db = FakeFirebaseFirestore();
  });

  Future<void> open(WidgetTester tester, {ReviewFeed? feed, Widget screen = const ReviewsScreen()}) async {
    usePhoneScreen(tester);
    final state = await signedInState(backend, reviews: feed ?? fakeFeed(db));
    await tester.pumpWidget(wrap(state, screen));
    await tester.pumpAndSettle();
  }

  testWidgets('ยังไม่มีรีวิว → บอกว่าลูกค้ารีวิวได้หลังรับอาหาร', (tester) async {
    await open(tester);
    expect(find.text('รีวิวร้าน'), findsOneWidget);
    expect(find.text('ยังไม่มีรีวิว\nลูกค้ารีวิวได้หลังรับอาหารแล้ว'), findsOneWidget);
  });

  testWidgets('คะแนนเฉลี่ย จำนวนรีวิว สัดส่วนดาว และรีวิวทุกอัน (ไม่รวมร้านอื่น)', (tester) async {
    await seedReview(db, 101, 5, comment: 'ขาหมูนุ่มมาก', day: 3);
    await seedReview(db, 102, 4, name: 'มานี ม.', comment: 'คิวเร็ว', day: 2);
    await seedReview(db, 103, 3, name: 'ปิติ ส.', day: 1);
    await seedReview(db, 104, 1, shopId: 2, comment: 'ร้านอื่น');
    await open(tester);

    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('3 รีวิว'), findsOneWidget);
    expect(find.text('รีวิวทั้งหมด (3)'), findsOneWidget);
    expect(find.text('ขาหมูนุ่มมาก'), findsOneWidget);
    expect(find.text('คิวเร็ว'), findsOneWidget);
    expect(find.text('ปิติ ส.'), findsOneWidget);
    expect(find.text('ออเดอร์ #101'), findsOneWidget);
    expect(find.text('ร้านอื่น'), findsNothing);
    // แถบสัดส่วน: 5 ดาว 1 รีวิว จาก 3
    final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
    expect(bars.map((b) => b.value), [1 / 3, 1 / 3, 1 / 3, 0, 0]);
  });

  testWidgets('นักศึกษารีวิวใหม่ขณะร้านเปิดหน้านี้อยู่ → ขึ้นทันที', (tester) async {
    await open(tester);
    await tester.runAsync(() => seedReview(db, 200, 5, comment: 'เพิ่งกินเสร็จ'));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่งกินเสร็จ'), findsOneWidget);
    expect(find.text('1 รีวิว'), findsOneWidget);
  });

  testWidgets('โหลดข้อมูลร้านไม่ได้ → แสดง error และกดลองใหม่ได้', (tester) async {
    usePhoneScreen(tester);
    final state = await signedInState(backend, reviews: fakeFeed(db));
    backend.failStatus = 500;
    await tester.pumpWidget(wrap(state, const ReviewsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่'), findsOneWidget);
    backend.failStatus = null;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('รีวิวร้าน'), findsOneWidget);
    expect(find.textContaining('ยังไม่มีรีวิว'), findsOneWidget);
  });

  testWidgets('Firebase ใช้ไม่ได้ระหว่างโหลดรีวิว → แจ้งว่าโหลดไม่ได้', (tester) async {
    await open(tester, feed: ReviewFeed(db, signIn: () async => throw Exception('offline')));
    expect(find.text('โหลดรีวิวไม่ได้ในขณะนี้'), findsOneWidget);
  });

  testWidgets('ไม่มี Firebase: บนเว็บบอกให้ใช้แอป / บน Android แสดงสาเหตุ', (tester) async {
    usePhoneScreen(tester);
    final state = await signedInState(backend);
    await tester.pumpWidget(wrap(state, const ReviewsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('ดูรีวิวได้ในแอป Android'), findsOneWidget);

    ReviewFeed.initError = Exception('no network');
    addTearDown(() => ReviewFeed.initError = null);
    await tester.pumpWidget(wrap(fakeState(backend), const ReviewsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('ระบบรีวิวใช้งานไม่ได้: Exception: no network'), findsOneWidget);
  });

  testWidgets('แท็บ "รีวิว" ในแถบเมนูล่าง', (tester) async {
    await seedReview(db, 101, 5, comment: 'อร่อย');
    await open(tester, screen: const VendorShell());
    await tester.tap(find.text('รีวิว'));
    await tester.pumpAndSettle();
    expect(find.text('อร่อย'), findsOneWidget);
  });
}
