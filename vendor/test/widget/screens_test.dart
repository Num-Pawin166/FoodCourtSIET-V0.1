import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_vendor/screens/login_screen.dart';
import 'package:foodcourt_vendor/screens/menu_screen.dart';
import 'package:foodcourt_vendor/screens/orders_screen.dart';
import 'package:foodcourt_vendor/screens/shop_screen.dart';
import 'package:foodcourt_vendor/screens/vendor_shell.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';

void main() {
  late FakeVendorBackend backend;
  late FakeImagePicker picker;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeVendorBackend();
    picker = FakeImagePicker();
    ImagePickerPlatform.instance = picker;
  });

  group('หน้า Login ร้านค้า', () {
    testWidgets('ไม่กรอก → เตือน / ผิด → ข้อความจากเซิร์ฟเวอร์ / ถูก → ล็อกอิน', (tester) async {
      usePhoneScreen(tester);
      final state = fakeState(backend);
      await tester.pumpWidget(wrap(state, const LoginScreen()));
      expect(find.text('สำหรับร้านค้า'), findsOneWidget);

      await tester.tap(find.text('เข้าสู่ระบบ'));
      await tester.pump();
      expect(find.text('กรุณากรอกข้อมูลให้ครบ'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'shopa');
      await tester.enterText(find.byType(TextField).at(1), 'nope');
      await tester.tap(find.text('เข้าสู่ระบบ'));
      await tester.pumpAndSettle();
      expect(find.text('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(state.user?.username, 'shopa');
    });
  });

  group('หน้าออเดอร์', () {
    testWidgets('ไม่มีออเดอร์: สรุปยอด + ว่าง + ไม่มีเสียง', (tester) async {
      usePhoneScreen(tester);
      final sound = FakeSound();
      final state = await signedInState(backend, sound: sound);
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      expect(find.text('ร้านข้าวขาหมูป้าแดง · คิว A'), findsOneWidget);
      expect(find.text('ไม่มีออเดอร์ในหมวดนี้'), findsOneWidget);
      expect(sound.plays, 0);
      expect(state.pendingCount, 0);
    });

    testWidgets('ออเดอร์ใหม่เข้า → แจ้งเตือน + ป้าย "ใหม่" + เสียงดังซ้ำ จนกดรับ', (tester) async {
      usePhoneScreen(tester);
      final sound = FakeSound();
      final state = await signedInState(backend, sound: sound);
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();

      backend.addOrder(note: 'ไม่ใส่ผักดอง');
      await tester.pump(const Duration(seconds: 5)); // รอบ poll ถัดไป
      await tester.pump();
      expect(find.text('🔔 ออเดอร์ใหม่ A-001'), findsOneWidget);
      expect(find.text('ใหม่'), findsOneWidget);
      expect(find.text('📝 ไม่ใส่ผักดอง'), findsOneWidget);
      expect(state.pendingCount, 1);
      expect(sound.plays, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(sound.plays, greaterThanOrEqualTo(2));

      await tester.tap(find.text('รับออเดอร์'));
      await tester.pumpAndSettle();
      expect(backend.orders.single['status'], 'accepted');
      expect(state.pendingCount, 0);
      expect(state.alarm.ringing, isFalse);
    });

    testWidgets('เดินสถานะ: รับแล้ว → เริ่มทำ → ทำเสร็จ → ลูกค้ารับแล้ว (สลับแท็บตามสถานะ)', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      final o = backend.addOrder();
      o['status'] = 'accepted';
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'รับแล้ว 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'รับแล้ว 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เริ่มทำ'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'กำลังทำ 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'กำลังทำ 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ทำเสร็จแล้ว'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'พร้อมรับ 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'พร้อมรับ 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลูกค้ารับแล้ว'));
      await tester.pumpAndSettle();
      expect(o['status'], 'completed');

      await tester.ensureVisible(find.text('ทั้งหมดวันนี้'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ทั้งหมดวันนี้'));
      await tester.pumpAndSettle();
      expect(find.textContaining('รับอาหารแล้ว'), findsOneWidget);
    });

    testWidgets('ปฏิเสธออเดอร์พร้อมเหตุผล (กดไม่ยกเลิกก่อน 1 ครั้ง)', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      final o = backend.addOrder();
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ปฏิเสธ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ไม่ยกเลิก'));
      await tester.pumpAndSettle();
      expect(o['status'], 'pending');

      await tester.tap(find.text('ปฏิเสธ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ข้าวหมด');
      await tester.tap(find.text('ยืนยันยกเลิก'));
      await tester.pumpAndSettle();
      expect(o['status'], 'cancelled');
      expect(o['cancel_reason'], 'ข้าวหมด');
    });

    testWidgets('จ่ายที่ร้าน → บันทึกรับเงินสด', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      final o = backend.addOrder();
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('จ่ายที่ร้าน'));
      await tester.pumpAndSettle();
      expect(find.text('ลูกค้าเลือกจ่ายที่ร้าน'), findsOneWidget);
      await tester.tap(find.text('รับเงินสดแล้ว'));
      await tester.pumpAndSettle();
      expect(o['payment_status'], 'paid');
      expect(find.text('บันทึกรับเงินแล้ว'), findsOneWidget);
    });

    testWidgets('โอนพร้อมเพย์: ดูสลิป → ปฏิเสธพร้อมเหตุผล', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      final o = backend.addOrder(payment: 'promptpay', paymentStatus: 'slip_uploaded');
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('สลิปรอตรวจ · แตะเพื่อดู'));
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันรับเงิน'), findsOneWidget);
      expect(backend.requests.any((r) => r.url.path.endsWith('/slip')), isTrue);
      await tester.tap(find.text('สลิปไม่ถูกต้อง'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ส่ง'));
      await tester.pumpAndSettle();
      expect(o['payment_status'], 'rejected');
      expect(o['payment_note'], 'ยอดเงินไม่ตรง');
      expect(find.text('สลิปไม่ผ่าน · รอลูกค้าแนบใหม่'), findsOneWidget);
    });

    testWidgets('โอนพร้อมเพย์: ยืนยันรับเงิน / ยังไม่แนบสลิป', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      final o = backend.addOrder(payment: 'promptpay', paymentStatus: 'slip_uploaded');
      backend.addOrder(payment: 'promptpay');
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('สลิปรอตรวจ · แตะเพื่อดู'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยืนยันรับเงิน'));
      await tester.pumpAndSettle();
      expect(o['payment_status'], 'paid');
      expect(find.text('ชำระเงินแล้ว'), findsOneWidget);

      await tester.tap(find.text('โอนพร้อมเพย์ · รอลูกค้าโอน'));
      await tester.pumpAndSettle();
      expect(find.text('ลูกค้ายังไม่ได้แนบสลิป'), findsOneWidget);
      await tester.tap(find.text('ปิด'));
      await tester.pumpAndSettle();
    });

    testWidgets('สวิตช์เปิด/ปิดร้าน', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(backend.shop['is_open'], isFalse);
      expect(find.text('ปิดร้าน'), findsOneWidget);
    });

    testWidgets('เน็ตหลุดตอนเปิด → error + ลองใหม่ / เปลี่ยนสถานะไม่สำเร็จ → แจ้ง', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      backend.offline = true;
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      backend.offline = false;
      backend.addOrder();
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      backend.failStatus = 409;
      await tester.tap(find.text('รับออเดอร์'));
      await tester.pumpAndSettle();
      expect(find.text('เซิร์ฟเวอร์ผิดพลาด'), findsWidgets);
    });
  });

  group('หน้าเมนู', () {
    testWidgets('รายการเมนู + สวิตช์ของหมด', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const MenuScreen()));
      await tester.pumpAndSettle();
      expect(find.text('ข้าวขาหมู'), findsOneWidget);
      expect(find.text('฿45 · หมด'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(backend.menu.first['is_available'], isFalse);
      expect(find.text('ข้าวขาหมู ตั้งเป็นหมดแล้ว'), findsOneWidget);
    });

    testWidgets('เพิ่มเมนูพร้อมรูป (เลือกจากคลังภาพ)', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const MenuScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เพิ่มเมนู'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('บันทึก'));
      await tester.pump();
      expect(find.text('กรุณากรอกชื่อและราคา (ตัวเลข)'), findsOneWidget);

      picker.next = tinyPng;
      await tester.tap(find.text('เพิ่มรูปเมนู'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เลือกจากคลังภาพ'));
      await tester.pumpAndSettle();
      expect(picker.lastSource, ImageSource.gallery);

      await tester.enterText(find.byType(TextField).at(0), 'ข้าวหมูแดง');
      await tester.enterText(find.byType(TextField).at(1), 'ราดน้ำแดง');
      await tester.enterText(find.byType(TextField).at(2), '55');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();
      expect(backend.menu.last['name'], 'ข้าวหมูแดง');
      expect(backend.menu.last['price'], 55);
      expect(backend.uploadedImage, tinyPng);
      expect(find.text('ข้าวหมูแดง'), findsOneWidget);
    });

    testWidgets('แก้ไขเมนู: ลบรูปเดิม + ปิดขาย', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const MenuScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ข้าวมันไก่ทอด'));
      await tester.pumpAndSettle();
      expect(find.text('แก้ไขเมนู'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบรูป'));
      await tester.pumpAndSettle();
      expect(find.text('เพิ่มรูปเมนู'), findsOneWidget);
      await tester.tap(find.text('มีขาย'));
      await tester.enterText(find.byType(TextField).at(2), '49');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();
      final m = backend.menu[1];
      expect(m['price'], 49);
      expect(m['is_available'], isTrue);
      expect(m['image_url'], isNull);
    });

    testWidgets('ลบเมนู (ยืนยันก่อน)', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const MenuScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ข้าวขาหมู'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบ'));
      await tester.pumpAndSettle();
      expect(backend.menu.map((m) => m['name']), isNot(contains('ข้าวขาหมู')));
    });
  });

  group('หน้าร้านของฉัน', () {
    testWidgets('แก้ข้อมูลร้าน: เวลารอ คำอธิบาย พร้อมเพย์ แล้วบันทึก', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopScreen()));
      await tester.pumpAndSettle();
      expect(find.text('07:30 น.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add).first); // เวลารอขั้นต่ำ 5 → 6
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove).last); // สูงสุด 10 → 9
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'ข้าวขาหมูสูตรเด็ด');
      await tester.enterText(find.byType(TextField).at(1), '0812345678');
      await tester.dragUntilVisible(find.text('บันทึก'), find.byType(ListView), const Offset(0, -300));
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();
      expect(backend.shop['prep_min'], 6);
      expect(backend.shop['prep_max'], 9);
      expect(backend.shop['description'], 'ข้าวขาหมูสูตรเด็ด');
      expect(backend.shop['promptpay_id'], '0812345678');
      expect(find.text('บันทึกข้อมูลร้านแล้ว'), findsOneWidget);
    });

    testWidgets('พร้อมเพย์ผิดรูปแบบ → แสดง error จากเซิร์ฟเวอร์', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '123');
      await tester.dragUntilVisible(find.text('บันทึก'), find.byType(ListView), const Offset(0, -300));
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();
      expect(find.text('หมายเลขพร้อมเพย์ไม่ถูกต้อง'), findsOneWidget);
    });

    testWidgets('เลือกเวลาเปิดร้านด้วยนาฬิกา', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('07:30 น.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('07:30 น.'), findsOneWidget);
      await tester.tap(find.text('17:00 น.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('เปลี่ยนรูปร้าน แล้วลบรูป', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopScreen()));
      await tester.pumpAndSettle();
      picker.next = tinyPng;
      await tester.tap(find.byIcon(Icons.photo_camera));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ถ่ายรูป'));
      await tester.pumpAndSettle();
      expect(picker.lastSource, ImageSource.camera);
      expect(find.text('เปลี่ยนรูปร้านแล้ว'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.photo_camera));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบรูปร้าน'));
      await tester.pumpAndSettle();
      expect(backend.shop['image_url'], isNull);
    });

    testWidgets('แก้ชื่อเจ้าของร้าน และเปลี่ยนรหัสผ่าน', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('เจ้าของร้าน A'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'ป้าแดง');
      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pumpAndSettle();
      expect(find.text('ป้าแดง'), findsOneWidget);

      Future<void> changePassword(String cur, String next, String confirm) async {
        await tester.tap(find.text('เปลี่ยนรหัสผ่าน'));
        await tester.pumpAndSettle();
        final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
        await tester.enterText(fields.at(0), cur);
        await tester.enterText(fields.at(1), next);
        await tester.enterText(fields.at(2), confirm);
        await tester.tap(find.widgetWithText(FilledButton, 'เปลี่ยนรหัสผ่าน'));
        await tester.pumpAndSettle();
      }

      await changePassword('1234', 'abcd', 'abce');
      expect(find.text('รหัสผ่านใหม่ทั้งสองช่องไม่ตรงกัน'), findsOneWidget);
      await changePassword('wrong', 'abcd', 'abcd');
      expect(find.text('รหัสผ่านเดิมไม่ถูกต้อง'), findsOneWidget);
      await changePassword('1234', 'abcd', 'abcd');
      expect(backend.password, 'abcd');
    });

    testWidgets('ออกจากระบบ', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopScreen()));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.text('ออกจากระบบ'), find.byType(ListView), const Offset(0, -300));
      await tester.tap(find.text('ออกจากระบบ'));
      await tester.pump();
      expect(state.user, isNull);
    });
  });

  group('แถบเมนูล่าง + แถบเตือนสีแดง', () {
    testWidgets('มีออเดอร์ค้าง → แถบแดงทุกแท็บ กดแล้วกลับหน้าออเดอร์', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      backend.addOrder();
      await tester.pumpWidget(wrap(state, const VendorShell()));
      await tester.pumpAndSettle();
      expect(find.text('มีออเดอร์ใหม่ 1 รายการ รอร้านกดรับ'), findsOneWidget);

      await tester.tap(find.text('เมนู'));
      await tester.pumpAndSettle();
      expect(state.tab, 1);
      expect(find.text('ดูออเดอร์ ›'), findsOneWidget);
      await tester.tap(find.text('ดูออเดอร์ ›'));
      await tester.pumpAndSettle();
      expect(state.tab, 0);
      await tester.tap(find.text('ร้านของฉัน'));
      await tester.pumpAndSettle();
      expect(state.tab, 2);
    });
  });
}
