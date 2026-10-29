import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_vendor/api.dart';
import 'package:foodcourt_vendor/models.dart';
import 'package:foodcourt_vendor/order_alarm.dart';
import 'package:foodcourt_vendor/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeVendorBackend backend;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeVendorBackend();
  });

  group('รูปแบบตัวเลข/เวลา', () {
    test('baht ใส่คอมมาหลักพัน', () {
      expect(baht(45), '฿45');
      expect(baht(1234567), '฿1,234,567');
    });
    test('thaiDateTime เป็นปี พ.ศ.', () {
      expect(thaiDateTime(DateTime(2026, 1, 5, 9, 7)), '5 ม.ค. 2569 09.07 น.');
    });
  });

  group('แปลง JSON', () {
    test('Order: ชื่อลูกค้า รายการ การชำระเงิน', () {
      final o = Order.fromJson(backend.addOrder(payment: 'promptpay', paymentStatus: 'slip_uploaded', note: 'ไม่เผ็ด'));
      expect(o.queueNo, 'A-001');
      expect(o.customer, 'สมชาย ใจดี');
      expect(o.items.single.qty, 2);
      expect(o.hasSlip, isTrue);
      expect(o.note, 'ไม่เผ็ด');
      expect(o.createdAt.isUtc, isFalse);
    });
    test('Shop / MenuItem / Vendor', () {
      final s = Shop.fromJson(backend.shop);
      expect([s.code, s.isOpen, s.promptpayId], ['A', true, null]);
      final m = MenuItem.fromJson(backend.menu[1]);
      expect([m.isAvailable, m.sortOrder, m.imageUrl], [false, 1, '/api/images/9']);
      expect(Vendor.fromJson(backend.user).role, 'vendor');
    });
    test('Summary: เมนูขายดี / ไม่มีข้อมูล', () {
      expect(Summary.fromJson({'orders': 3, 'revenue': 150, 'top_items': [{'name': 'ข้าวขาหมู', 'qty': 2}]}).topItem, 'ข้าวขาหมู');
      final empty = Summary.fromJson({});
      expect([empty.orders, empty.topItem, empty.topQty], [0, null, 0]);
    });
    test('ป้ายสถานะครบทุกสถานะ', () {
      expect(statusLabel.keys, containsAll(['pending', 'accepted', 'cooking', 'ready', 'completed', 'cancelled']));
    });
  });

  group('เสียงเตือนออเดอร์ใหม่ (OrderAlarm)', () {
    test('มีออเดอร์รอ → ดังทันทีและซ้ำทุก 3 วินาที จนกว่าจะไม่มีออเดอร์รอ', () {
      fakeAsync((clock) {
        final sound = FakeSound();
        final alarm = OrderAlarm(sound: () => sound);
        alarm.update(2);
        clock.flushMicrotasks();
        expect(alarm.ringing, isTrue);
        expect(sound.plays, 1);
        clock.elapse(const Duration(seconds: 9));
        expect(sound.plays, 4);
        alarm.update(2); // โหลดซ้ำระหว่างดัง ไม่เริ่มนับใหม่
        clock.elapse(const Duration(seconds: 3));
        expect(sound.plays, 5);
        alarm.update(0);
        expect(alarm.ringing, isFalse);
        clock.elapse(const Duration(seconds: 9));
        expect(sound.plays, 5);
        alarm.dispose();
      });
    });

    test('ไม่มีออเดอร์รอ → ไม่ดังเลย (ไม่สร้างเครื่องเล่นเสียง)', () {
      var created = 0;
      final alarm = OrderAlarm(sound: () {
        created++;
        return FakeSound();
      });
      alarm.update(0);
      alarm.dispose();
      expect(created, 0);
    });

    test('สั่นทุกครั้งที่ดัง', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        calls.add(c);
        return null;
      });
      final alarm = OrderAlarm(sound: FakeSound.new);
      alarm.update(1);
      await Future<void>.delayed(Duration.zero);
      alarm.dispose();
      expect(calls.where((c) => c.method == 'HapticFeedback.vibrate'), isNotEmpty);
    });

    test('เล่นเสียงไม่ได้ (เช่นเบราว์เซอร์บล็อก) → ไม่พัง', () async {
      final alarm = OrderAlarm(sound: _BrokenSound.new);
      alarm.update(1);
      await Future<void>.delayed(Duration.zero);
      expect(alarm.ringing, isTrue);
      alarm.dispose();
    });
  });

  group('AppState', () {
    test('ล็อกอิน / restore / ออกจากระบบ', () async {
      final state = await signedInState(backend);
      expect(state.user!.name, 'เจ้าของร้าน A');
      expect((await SharedPreferences.getInstance()).getString('vendor_token'), FakeVendorBackend.token);

      final reopened = fakeState(backend);
      await reopened.restore();
      expect(reopened.user?.username, 'shopa');

      await reopened.logout();
      expect(reopened.user, isNull);
      expect((await SharedPreferences.getInstance()).getString('vendor_token'), isNull);
    });

    test('restore ด้วย token ที่ใช้ไม่ได้ → กลับหน้า Login', () async {
      SharedPreferences.setMockInitialValues({'vendor_token': 'bad'});
      final state = fakeState(backend);
      await state.restore();
      expect(state.user, isNull);
      expect(state.restoring, isFalse);
    });

    test('จำนวนออเดอร์รอ / เปลี่ยนแท็บ / แก้ชื่อ', () async {
      final state = await signedInState(backend);
      var notified = 0;
      state.addListener(() => notified++);
      state.setPendingCount(2);
      state.setPendingCount(2); // ค่าเดิมไม่แจ้งซ้ำ
      expect(notified, 1);
      state.goTab(2);
      expect(state.tab, 2);
      state.setUser(await state.api.updateMe('ป้าแดง'));
      expect(state.user!.name, 'ป้าแดง');
    });

    test('Api: เน็ตหลุดได้ข้อความภาษาไทย / error จากเซิร์ฟเวอร์', () async {
      final state = await signedInState(backend);
      backend.offline = true;
      await expectLater(state.api.menu(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)));
      backend.offline = false;
      backend.failStatus = 500;
      await expectLater(state.api.menu(), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'เซิร์ฟเวอร์ผิดพลาด')));
    });
  });
}

class _BrokenSound implements AlarmSound {
  @override
  Future<void> play() => Future.error(StateError('autoplay blocked'));
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
