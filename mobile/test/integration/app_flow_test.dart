import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/app_state.dart';
import 'package:foodcourt_siet/local_db.dart';
import 'package:foodcourt_siet/main.dart';
import 'package:foodcourt_siet/reviews.dart';
import 'package:foodcourt_siet/screens/login_screen.dart';
import 'package:foodcourt_siet/screens/payment_screen.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../support/fake_backend.dart';
import '../support/fake_image_picker.dart';

/// Integration test
/// 1) เปิดทั้งแอป (main.dart) แล้วเดินตามขั้นตอนของผู้ใช้ตั้งแต่ล็อกอินจนจ่ายเงิน
///    (หน้าจอ → AppState → Api → HTTP) โดยใช้เซิร์ฟเวอร์จำลอง
/// 2) AppState + Api + ฐานข้อมูล SQLite จริง ทำงานร่วมกัน (เปิดแอปใหม่ / ออฟไลน์ / ออกจากระบบ)
///    — SQLite ต้องใช้ I/O จริง จึงแยกจาก widget test ที่ใช้นาฬิกาจำลอง
void main() {
  sqfliteFfiInit();
  late FakeBackend backend;
  late FakeImagePicker picker;
  late LocalStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
    picker = FakeImagePicker();
    ImagePickerPlatform.instance = picker;
    store = MemoryLocalStore();
  });

  Future<AppState> launchApp(WidgetTester tester, {ReviewService? reviews}) async {
    usePhoneScreen(tester);
    final state = fakeState(backend, store: store, reviews: reviews);
    await tester.pumpWidget(ChangeNotifierProvider(create: (_) => state..restore(), child: const FoodCourtApp()));
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), '65010001');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
  }

  testWidgets('ล็อกอิน → เลือกร้าน → ใส่ตะกร้า → สั่ง (พร้อมเพย์) → แนบสลิป → ติดตามออเดอร์', (tester) async {
    final state = await launchApp(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    await login(tester);
    expect(find.text('ร้านข้าวขาหมูป้าแดง'), findsOneWidget);

    // เลือกร้าน แล้วใส่ข้าวขาหมู 2 จาน
    await tester.tap(find.text('ร้านข้าวขาหมูป้าแดง'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    expect(find.text('฿100'), findsOneWidget);

    // ตะกร้า: เลือกเวลา + หมายเหตุ แล้วยืนยัน
    await tester.tap(find.text('เพิ่มลงตะกร้า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('11:30'));
    await tester.enterText(find.byType(TextField), 'ไม่ใส่ผักดอง');
    await tester.pump();
    await tester.tap(find.text('ยืนยันคำสั่งซื้อ  ฿100'));
    await tester.pumpAndSettle();

    // เซิร์ฟเวอร์ได้รับข้อมูลครบ และแอปพาไปหน้าจ่ายเงินทันที
    final sent = backend.orders.single;
    expect(sent['pickup_time'], '11:30');
    expect(sent['note'], 'ไม่ใส่ผักดอง');
    expect(sent['payment_method'], 'promptpay');
    expect(sent['total'], 100);
    expect(state.cartCount, 0);
    expect(await store.loadCart(), isNull); // ตะกร้าในเครื่องถูกล้างหลังสั่ง
    expect(find.byType(PaymentScreen), findsOneWidget);

    // แนบสลิป
    picker.next = pngBytes;
    await tester.tap(find.text('แนบสลิป'));
    await tester.pumpAndSettle();
    expect(backend.paymentStatus, 'slip_uploaded');

    // กลับไปหน้าคำสั่งซื้อ เห็นเลขคิว และข้อมูลถูกเก็บลงฐานข้อมูลในเครื่อง
    await tester.tap(find.text('ไปหน้าคำสั่งซื้อ'));
    await tester.pumpAndSettle();
    expect(find.text('A - 001'), findsOneWidget);
    expect((await store.cachedOrders(history: false))!.single['queue_no'], 'A-001');
  });

  testWidgets('รับอาหารแล้ว → รีวิวจากแท็บประวัติ → เพื่อนอีกคนเห็นรีวิวในหน้าร้าน (Firestore)', (tester) async {
    final db = FakeFirebaseFirestore(); // Firestore ชุดเดียวกัน แต่ผู้ใช้ Firebase คนละคน
    backend.addCompletedOrder();
    await launchApp(tester, reviews: fakeReviews(db, uid: 'me'));
    await login(tester);

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ประวัติ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ให้คะแนนร้าน'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('5 ดาว'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ขาหมูนุ่ม น้ำซุปดี');
    await tester.tap(find.text('ส่งรีวิว'));
    await tester.pumpAndSettle();
    expect(find.text('รีวิวแล้ว · แตะเพื่อแก้'), findsOneWidget);

    // เปิดแอปอีกเครื่อง (ผู้ใช้อื่น) → เห็นรีวิวในหน้าร้าน
    await tester.pumpWidget(const SizedBox());
    await launchApp(tester, reviews: fakeReviews(db, uid: 'friend'));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ร้านข้าวขาหมูป้าแดง'));
    await tester.pumpAndSettle();
    expect(find.text('ขาหมูนุ่ม น้ำซุปดี'), findsOneWidget);
    expect(find.text('สมชาย ใ.'), findsOneWidget);
    expect(find.text('5.0'), findsOneWidget);
  });

  testWidgets('สั่งแบบจ่ายที่ร้าน → กลับหน้าคำสั่งซื้อพร้อมแจ้งเลขคิว', (tester) async {
    await launchApp(tester);
    await login(tester);
    await tester.tap(find.text('ก๋วยเตี๋ยวลุงชัย'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงตะกร้า'));
    await tester.pumpAndSettle();
    expect(find.text('ร้านนี้ยังไม่รับโอน'), findsOneWidget);
    await tester.tap(find.textContaining('ยืนยันคำสั่งซื้อ'));
    await tester.pumpAndSettle();
    expect(backend.orders.single['payment_method'], 'cash');
    expect(find.text('สั่งอาหารสำเร็จ! หมายเลขคิว B-001'), findsOneWidget);
    expect(find.text('B - 001'), findsOneWidget);
  });

  testWidgets('ปิดแอปแล้วเปิดใหม่: ยังล็อกอินอยู่ และตะกร้ายังอยู่', (tester) async {
    await launchApp(tester);
    await login(tester);
    await tester.tap(find.text('ร้านข้าวขาหมูป้าแดง'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).at(1));
    await tester.pumpAndSettle();

    // เปิดแอปใหม่ (AppState ใหม่ แต่ฐานข้อมูล/SharedPreferences เดิม)
    await tester.pumpWidget(const SizedBox());
    final reopened = await launchApp(tester);
    expect(find.byType(LoginScreen), findsNothing);
    expect(reopened.cartCount, 1);
    expect(reopened.cartLines.single.$1.name, 'ข้าวมันไก่ทอด');
  });

  testWidgets('ถาม AI → กดเมนูที่แนะนำ → ไปหน้าร้าน → สั่งได้ต่อ', (tester) async {
    final state = await launchApp(tester);
    await login(tester);
    await tester.tap(find.text('ถาม AI ช่วยเลือกเมนู'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'งบ 50 ไม่เผ็ด');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect((await store.chatHistory()).map((m) => m.fromUser), [true, false]);
    await tester.tap(find.text('ไปที่ร้าน ›'));
    await tester.pumpAndSettle();
    expect(state.tab, 1);
    expect(find.text('ข้าวมันไก่ทอด'), findsOneWidget);
  });

  group('AppState + Api + SQLite จริง', () {
    late SqliteLocalStore db;
    late String path;
    setUp(() async {
      path = '${await databaseFactoryFfi.getDatabasesPath()}/integration_${DateTime.now().microsecondsSinceEpoch}.db';
      db = SqliteLocalStore(databaseFactoryFfi, path);
    });
    tearDown(() async {
      await db.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    test('ใส่ตะกร้า → ปิดแอป → เปิดใหม่ (ไฟล์ฐานข้อมูลเดิม) → ตะกร้ากลับมา → สั่งได้', () async {
      final first = await signedInState(backend, store: db);
      final shop = await first.api.shop(1);
      first.setQty(shop, shop.menu[0], 2);
      first.setCartNote('แยกน้ำซุป');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await db.close();

      SharedPreferences.setMockInitialValues({'token': FakeBackend.token});
      final reopened = fakeState(backend, store: SqliteLocalStore(databaseFactoryFfi, path));
      await reopened.restore();
      expect(reopened.cartCount, 2);
      expect(reopened.cartNote, 'แยกน้ำซุป');

      final order = await reopened.api.createOrder(
          shopId: reopened.cartShop!.id, items: Map.of(reopened.cartQty), pickupTime: '11:15', note: reopened.cartNote);
      expect(order.total, 100);
      reopened.clearCart();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await reopened.store.loadCart(), isNull);
      await (reopened.store as SqliteLocalStore).close();
    });

    test('ออนไลน์เก็บออเดอร์ลง SQLite → เน็ตหลุด → ยังเห็นเลขคิว → ออกจากระบบแล้วข้อมูลหาย', () async {
      final state = await signedInState(backend, store: db);
      await state.api.createOrder(shopId: 1, items: {1: 1}, pickupTime: '11:15');
      expect((await state.loadOrders()).$2, isFalse);

      backend.offline = true;
      final (orders, offline) = await state.loadOrders();
      expect(offline, isTrue);
      expect(orders.single.queueNo, 'A-001');

      backend.offline = false;
      await state.logout();
      expect(await db.cachedOrders(history: false), isNull);
    });
  });
}
