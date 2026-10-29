import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_vendor/api.dart';
import 'package:foodcourt_vendor/screens/login_screen.dart';
import 'package:foodcourt_vendor/screens/shop_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';

/// Security test ฝั่งแอปร้านค้า
void main() {
  late FakeVendorBackend backend;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeVendorBackend();
  });

  test('บัญชีนักศึกษาเข้าแอปร้านค้าไม่ได้ และไม่เก็บ token', () async {
    final state = fakeState(backend);
    await expectLater(state.login('65010001', '1234'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
    expect(state.user, isNull);
    expect(state.api.token, isNull);
    expect((await SharedPreferences.getInstance()).getString('vendor_token'), isNull);
  });

  test('token ที่บันทึกไว้ แต่บัญชีถูกเปลี่ยนเป็นบทบาทอื่นแล้ว → ไม่ให้เข้า', () async {
    SharedPreferences.setMockInitialValues({'vendor_token': FakeVendorBackend.token});
    backend.role = 'student';
    final state = fakeState(backend);
    await state.restore();
    expect(state.user, isNull);
  });

  test('ก่อนล็อกอินไม่ส่ง Authorization / หลังล็อกอินส่ง Bearer token', () async {
    final state = fakeState(backend);
    await expectLater(state.api.shop(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    expect(backend.requests.last.headers.containsKey('Authorization'), isFalse);
    await state.login('shopa', '1234');
    await state.api.shop();
    expect(backend.requests.last.headers['Authorization'], 'Bearer ${FakeVendorBackend.token}');
  });

  test('เซิร์ฟเวอร์ตอบ 401 (บัญชีถูกระงับ) → ออกจากระบบอัตโนมัติ + หยุดเสียงเตือน + ลบ token', () async {
    final state = await signedInState(backend);
    state.alarm.update(1);
    state.api.token = 'revoked';
    await expectLater(state.api.orders(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    expect(state.user, isNull);
    expect(state.alarm.ringing, isFalse);
    expect((await SharedPreferences.getInstance()).getString('vendor_token'), isNull);
  });

  test('ออกจากระบบแล้ว request ถัดไปไม่มี token', () async {
    final state = await signedInState(backend);
    await state.logout();
    await expectLater(state.api.menu(), throwsA(isA<ApiException>()));
    expect(backend.requests.last.headers.containsKey('Authorization'), isFalse);
  });

  testWidgets('ช่องรหัสผ่านซ่อนตัวอักษรเป็นค่าเริ่มต้น / หน้าบอกให้ติดต่อผู้ดูแล (ไม่มีสมัครเอง)', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(wrap(fakeState(backend), const LoginScreen()));
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).obscureText, isTrue);
    expect(find.text('ยังไม่มีบัญชี? ติดต่อผู้ดูแลศูนย์อาหาร'), findsOneWidget);
  });

  testWidgets('ช่องรหัสผ่านในหน้าเปลี่ยนรหัสผ่านซ่อนทุกช่อง', (tester) async {
    usePhoneScreen(tester);
    final state = await signedInState(backend);
    await tester.pumpWidget(wrap(state, const ShopScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เปลี่ยนรหัสผ่าน'));
    await tester.pumpAndSettle();
    final fields = tester.widgetList<TextField>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)));
    expect(fields, hasLength(3));
    expect(fields.every((f) => f.obscureText), isTrue);
  });
}
