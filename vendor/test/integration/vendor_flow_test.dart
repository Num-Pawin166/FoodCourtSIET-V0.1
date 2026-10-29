import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_vendor/app_state.dart';
import 'package:foodcourt_vendor/main.dart';
import 'package:foodcourt_vendor/screens/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';

/// Integration test: เปิดแอปร้านค้าทั้งแอป (main.dart) แล้วทำงานตามวันจริงของร้าน
void main() {
  late FakeVendorBackend backend;
  late FakeSound sound;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeVendorBackend();
    sound = FakeSound();
  });

  Future<AppState> launch(WidgetTester tester) async {
    usePhoneScreen(tester);
    final state = fakeState(backend, sound: sound);
    await tester.pumpWidget(ChangeNotifierProvider(create: (_) => state..restore(), child: const VendorApp()));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('ล็อกอิน → ออเดอร์ใหม่เข้า (เสียงดังซ้ำ + แถบแดง) → รับ → ทำ → พร้อม → ลูกค้ารับ → ตรวจสลิป', (tester) async {
    final state = await launch(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'shopa');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    expect(find.text('ไม่มีออเดอร์ในหมวดนี้'), findsOneWidget);

    // นักศึกษาสั่ง (โอนพร้อมเพย์ + แนบสลิปแล้ว) ระหว่างที่ร้านอยู่หน้าเมนู
    await tester.tap(find.text('เมนู'));
    await tester.pumpAndSettle();
    backend.addOrder(payment: 'promptpay', paymentStatus: 'slip_uploaded');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('มีออเดอร์ใหม่ 1 รายการ รอร้านกดรับ'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(sound.plays, greaterThanOrEqualTo(3)); // ดังซ้ำทุก 3 วินาที

    // แตะแถบแดง → กลับหน้าออเดอร์ → รับออเดอร์ → เสียงหยุด
    await tester.tap(find.text('ดูออเดอร์ ›'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('รับออเดอร์'));
    await tester.pumpAndSettle();
    expect(state.alarm.ringing, isFalse);
    expect(find.textContaining('มีออเดอร์ใหม่'), findsNothing);
    final playsAfterAccept = sound.plays;
    await tester.pump(const Duration(seconds: 6));
    expect(sound.plays, playsAfterAccept);

    // ตรวจสลิป → ยืนยันรับเงิน
    await tester.tap(find.widgetWithText(ChoiceChip, 'รับแล้ว 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สลิปรอตรวจ · แตะเพื่อดู'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันรับเงิน'));
    await tester.pumpAndSettle();
    expect(backend.orders.single['payment_status'], 'paid');

    // เดินสถานะจนจบ
    for (final (chip, action) in [('รับแล้ว 1', 'เริ่มทำ'), ('กำลังทำ 1', 'ทำเสร็จแล้ว'), ('พร้อมรับ 1', 'ลูกค้ารับแล้ว')]) {
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, chip));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, chip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
    }
    expect(backend.orders.single['status'], 'completed');
    expect(find.text('฿100'), findsOneWidget); // ยอดขายวันนี้
  });

  testWidgets('เปิดแอปใหม่ยังล็อกอินอยู่ และออเดอร์ที่ค้างอยู่ก่อนเปิดแอปก็มีเสียงเตือน', (tester) async {
    SharedPreferences.setMockInitialValues({'vendor_token': FakeVendorBackend.token});
    backend.addOrder();
    final state = await launch(tester);
    expect(state.user?.username, 'shopa');
    expect(state.alarm.ringing, isTrue);
    expect(find.text('มีออเดอร์ใหม่ 1 รายการ รอร้านกดรับ'), findsOneWidget);

    // ออกจากระบบ → เสียงหยุด
    await tester.tap(find.text('ร้านของฉัน'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('ออกจากระบบ'), find.byType(ListView).last, const Offset(0, -300));
    await tester.tap(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();
    expect(state.alarm.ringing, isFalse);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('เพิ่มเมนูใหม่แล้วตั้งเป็น "หมด" ได้ทันที', (tester) async {
    SharedPreferences.setMockInitialValues({'vendor_token': FakeVendorBackend.token});
    await launch(tester);
    await tester.tap(find.text('เมนู'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มเมนู'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'ชาเย็น');
    await tester.enterText(find.byType(TextField).at(2), '30');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(find.text('ชาเย็น'), findsOneWidget);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(backend.menu.last['is_available'], isFalse);
  });
}
