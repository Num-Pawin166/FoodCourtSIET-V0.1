import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/api.dart';
import 'package:foodcourt_siet/local_db.dart';
import 'package:foodcourt_siet/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';

/// Security test ฝั่งแอป: การเก็บ token, การออกจากระบบ, การแยกสิทธิ์ และข้อมูลในเครื่องที่ใช้ร่วมกัน
void main() {
  late FakeBackend backend;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
  });

  group('token และการยืนยันตัวตน', () {
    test('ก่อนล็อกอินไม่ส่ง Authorization header', () async {
      final state = fakeState(backend);
      await state.api.shops();
      expect(backend.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('หลังล็อกอินส่ง Bearer token ทุก request', () async {
      final state = await signedInState(backend);
      backend.requests.clear();
      await state.api.orders();
      expect(backend.requests.single.headers['Authorization'], 'Bearer ${FakeBackend.token}');
    });

    test('เซิร์ฟเวอร์ตอบ 401 (token หมดอายุ/ถูกระงับ) → ออกจากระบบอัตโนมัติ และลบ token ที่เก็บไว้', () async {
      final state = await signedInState(backend);
      state.api.token = 'revoked';
      await expectLater(state.api.orders(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
      await Future<void>.delayed(Duration.zero);
      expect(state.user, isNull);
      expect(state.api.token, isNull);
      expect((await SharedPreferences.getInstance()).getString('token'), isNull);
    });

    test('รหัสผ่านผิดได้ 401 แต่ไม่ถือว่า "เซสชันหมดอายุ" (ยังไม่มี token)', () async {
      final state = fakeState(backend);
      var loggedOut = false;
      state.api.onUnauthorized = () => loggedOut = true;
      await expectLater(state.login('65010001', 'wrong'), throwsA(isA<ApiException>()));
      expect(loggedOut, isFalse);
    });

    test('ข้อความ error ที่แสดงมาจากเซิร์ฟเวอร์ ไม่ใช่รายละเอียดภายใน', () async {
      final state = await signedInState(backend);
      backend.failStatus = 500;
      await expectLater(state.api.shops(), throwsA(isA<ApiException>().having((e) => e.toString(), 'message', 'เซิร์ฟเวอร์ผิดพลาด')));
      backend.failStatus = null;
      backend.offline = true;
      await expectLater(state.api.shops(), throwsA(isA<ApiException>().having((e) => e.toString(), 'message', contains('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้'))));
    });
  });

  group('แยกสิทธิ์', () {
    test('บัญชีร้านค้า/แอดมินล็อกอินแอปนักศึกษาไม่ได้ และไม่เก็บ token', () async {
      final state = fakeState(backend);
      await expectLater(state.login('shopa', '1234'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
      expect(state.user, isNull);
      expect(state.api.token, isNull);
      expect((await SharedPreferences.getInstance()).getString('token'), isNull);
    });

    testWidgets('หน้า Login แจ้งให้บัญชีร้านค้าไปใช้เว็บหลังบ้าน', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(fakeState(backend), const LoginScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'shopa');
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.textContaining('กรุณาใช้งานผ่านเว็บหลังบ้าน'), findsOneWidget);
    });

    testWidgets('ช่องรหัสผ่านซ่อนตัวอักษรเป็นค่าเริ่มต้น', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(fakeState(backend), const LoginScreen()));
      await tester.pumpAndSettle();
      final password = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(password.obscureText, isTrue);
    });
  });

  group('ข้อมูลในเครื่องเมื่อใช้มือถือร่วมกัน', () {
    test('ออกจากระบบ → ล้าง token, ตะกร้า, ออเดอร์ที่แคชไว้ และแชท AI', () async {
      final store = MemoryLocalStore();
      final state = await signedInState(backend, store: store);
      await state.api.createOrder(shopId: 1, items: {1: 1}, pickupTime: '11:15');
      await state.loadOrders();
      await store.addChat(SavedChat(true, 'งบ 50'));
      await state.reorder((await state.loadOrders()).$1.single);
      await Future<void>.delayed(Duration.zero);
      expect(await store.loadCart(), isNotNull);

      await state.logout();
      expect(await store.loadCart(), isNull);
      expect(await store.cachedOrders(history: false), isNull);
      expect(await store.chatHistory(), isEmpty);
      expect(state.favoriteIds, isEmpty);
      expect((await SharedPreferences.getInstance()).getString('token'), isNull);
    });

    test('หลังออกจากระบบ request ถัดไปไม่มี token ติดไป', () async {
      final state = await signedInState(backend);
      await state.logout();
      backend.requests.clear();
      await state.api.shops();
      expect(backend.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('ข้อมูลในเครื่องเสีย/อ่านไม่ได้ → แอปยังทำงานต่อได้ (ไม่ค้าง)', () async {
      SharedPreferences.setMockInitialValues({'token': FakeBackend.token});
      final state = fakeState(backend, store: _BrokenStore());
      await state.restore();
      expect(state.restoring, isFalse);
      expect(state.user, isNotNull);
      expect(state.cartCount, 0);
    });
  });
}

/// ฐานข้อมูลที่พังทุกคำสั่ง
class _BrokenStore extends MemoryLocalStore {
  @override
  Future<SavedCart?> loadCart() => Future.error(StateError('db corrupted'));
}
