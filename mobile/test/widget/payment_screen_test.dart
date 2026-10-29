import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/app_state.dart';
import 'package:foodcourt_siet/screens/payment_screen.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';
import '../support/fake_image_picker.dart';

void main() {
  late FakeBackend backend;
  late FakeImagePicker picker;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
    picker = FakeImagePicker();
    ImagePickerPlatform.instance = picker;
  });

  Future<AppState> openPayment(WidgetTester tester) async {
    usePhoneScreen(tester);
    final state = await signedInState(backend);
    await state.api.createOrder(shopId: 1, items: {1: 2}, pickupTime: '11:15', paymentMethod: 'promptpay');
    await tester.pumpWidget(wrap(state, const PaymentScreen(orderId: 100)));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('แสดงยอดเงิน QR พร้อมเพย์ และเลขพร้อมเพย์แบบปิดบางส่วน', (tester) async {
    await openPayment(tester);
    expect(find.text('฿100'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('โอนเข้าพร้อมเพย์ 081-xxx-5678'), findsOneWidget);
    expect(find.text('แนบสลิป'), findsOneWidget);
  });

  testWidgets('แนบสลิป → ส่งรูปไปเซิร์ฟเวอร์ → สถานะรอร้านตรวจ', (tester) async {
    await openPayment(tester);
    picker.next = pngBytes;
    await tester.tap(find.text('แนบสลิป'));
    await tester.pumpAndSettle();
    expect(picker.lastSource, ImageSource.gallery);
    expect(backend.slip, pngBytes);
    expect(find.text('แนบสลิปแล้ว รอร้านตรวจสอบ'), findsWidgets);
    expect(find.text('แนบสลิปใหม่'), findsOneWidget);
  });

  testWidgets('ยกเลิกการเลือกรูป → ไม่ส่งอะไร', (tester) async {
    await openPayment(tester);
    await tester.tap(find.text('แนบสลิป'));
    await tester.pumpAndSettle();
    expect(backend.slip, isNull);
  });

  testWidgets('สลิปถูกปฏิเสธ → แสดงเหตุผลให้แนบใหม่', (tester) async {
    backend.paymentStatus = 'rejected';
    await openPayment(tester);
    expect(find.textContaining('สลิปไม่ผ่าน: ยอดไม่ตรง'), findsOneWidget);
  });

  testWidgets('ร้านยืนยันแล้ว → ไม่มี QR และไม่มีปุ่มแนบ', (tester) async {
    backend.paymentStatus = 'paid';
    await openPayment(tester);
    expect(find.text('ร้านยืนยันรับเงินแล้ว'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('แนบสลิป'), findsNothing);
  });

  testWidgets('ปุ่ม "ไปหน้าคำสั่งซื้อ" สลับไปแท็บออเดอร์', (tester) async {
    final state = await openPayment(tester);
    await tester.tap(find.text('ไปหน้าคำสั่งซื้อ'));
    await tester.pumpAndSettle();
    expect(state.tab, 2);
  });

  testWidgets('โหลดข้อมูลไม่ได้ → error + ลองใหม่', (tester) async {
    usePhoneScreen(tester);
    final state = await signedInState(backend);
    await tester.pumpWidget(wrap(state, const PaymentScreen(orderId: 999)));
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบออเดอร์นี้'), findsOneWidget);
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบออเดอร์นี้'), findsOneWidget);
  });
}
