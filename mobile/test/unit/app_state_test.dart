import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/api.dart';
import 'package:foodcourt_siet/local_db.dart';
import 'package:foodcourt_siet/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
  });

  Shop shopA() => Shop.fromJson({...backend.shop(1), 'menu': backend.menuOf(1)});
  Shop shopB() => Shop.fromJson({...backend.shop(2), 'menu': backend.menuOf(2)});

  group('ล็อกอิน / ออกจากระบบ', () {
    test('ล็อกอินสำเร็จ: เก็บ token และโหลดเมนูโปรด', () async {
      final state = fakeState(backend);
      await state.login(' 65010001 ', '1234');
      expect(state.user!.username, '65010001');
      expect(state.api.token, FakeBackend.token);
      expect(state.favoriteIds, {1});
      expect((await SharedPreferences.getInstance()).getString('token'), FakeBackend.token);
    });

    test('รหัสผ่านผิด → ApiException 401 และยังไม่ล็อกอิน', () async {
      final state = fakeState(backend);
      await expectLater(state.login('65010001', 'x'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
      expect(state.user, isNull);
    });

    test('restore: มี token เดิม → เข้าสู่ระบบอัตโนมัติ', () async {
      SharedPreferences.setMockInitialValues({'token': FakeBackend.token});
      final state = fakeState(backend);
      await state.restore();
      expect(state.restoring, isFalse);
      expect(state.user!.name, 'สมชาย ใจดี');
    });

    test('restore: token หมดอายุ → กลับไปหน้า Login', () async {
      SharedPreferences.setMockInitialValues({'token': 'expired'});
      final state = fakeState(backend);
      await state.restore();
      expect(state.user, isNull);
      expect(state.api.token, isNull);
      expect(state.restoring, isFalse);
    });

    test('restore: ไม่มี token → ไม่เรียก API', () async {
      final state = fakeState(backend);
      await state.restore();
      expect(backend.requests, isEmpty);
    });
  });

  group('ตะกร้า', () {
    test('เพิ่ม/ลด/ลบ และคำนวณยอดรวม', () async {
      final state = await signedInState(backend);
      final shop = shopA();
      state.setQty(shop, shop.menu[0], 2);
      state.setQty(shop, shop.menu[1], 1);
      expect(state.cartCount, 3);
      expect(state.cartTotal, 50 * 2 + 45);
      state.setQty(shop, shop.menu[0], 0);
      expect(state.cartLines.single.$1.name, 'ข้าวมันไก่ทอด');
      state.setQty(shop, shop.menu[1], 0);
      expect(state.cartShop, isNull);
    });

    test('จำนวนต่อเมนูไม่เกิน 20', () async {
      final state = await signedInState(backend);
      state.setQty(shopA(), shopA().menu[0], 99);
      expect(state.qtyOf(1), 20);
    });

    test('สั่งได้ทีละร้าน: ใส่เมนูร้านอื่นแล้วตะกร้าเดิมถูกล้าง', () async {
      final state = await signedInState(backend);
      state.setQty(shopA(), shopA().menu[0], 1);
      expect(state.isOtherShop(shopB()), isTrue);
      expect(state.isOtherShop(shopA()), isFalse);
      state.setQty(shopB(), shopB().menu[0], 1);
      expect(state.cartShop!.id, 2);
      expect(state.cartCount, 1);
    });

    test('ตะกร้าถูกบันทึกลงฐานข้อมูลในเครื่อง และกลับมาหลังเปิดแอปใหม่', () async {
      final store = MemoryLocalStore();
      final state = await signedInState(backend, store: store);
      state.setQty(shopA(), shopA().menu[0], 2);
      state.setCartNote('แยกน้ำซุป');
      await Future<void>.delayed(Duration.zero);
      expect((await store.loadCart())!.items.single.$2, 2);

      SharedPreferences.setMockInitialValues({'token': FakeBackend.token});
      final reopened = fakeState(backend, store: store);
      await reopened.restore();
      expect(reopened.cartCount, 2);
      expect(reopened.cartShop!.name, 'ร้านข้าวขาหมูป้าแดง');
      expect(reopened.cartNote, 'แยกน้ำซุป');
    });

    test('สั่งอีกครั้ง: ใส่เฉพาะเมนูที่ยังมีขาย และบอกจำนวนที่หมด', () async {
      final state = await signedInState(backend);
      final old = Order.fromJson({
        'id': 1, 'queue_no': 'A-001', 'status': 'completed', 'status_label': '', 'shop': {'id': 1, 'name': 'ร้าน A'},
        'items': [
          {'menu_item_id': 1, 'name': 'ข้าวขาหมู', 'price': 50, 'qty': 2},
          {'menu_item_id': 3, 'name': 'ข้าวหมูกรอบ', 'price': 55, 'qty': 1},
        ],
        'pickup_time': '11:15', 'note': 'ไม่ใส่ผัก', 'total': 155, 'created_at': '2026-10-19T04:00:00Z',
      });
      final missing = await state.reorder(old);
      expect(missing, 1); // ข้าวหมูกรอบหมด
      expect(state.qtyOf(1), 2);
      expect(state.cartNote, 'ไม่ใส่ผัก');
      expect(state.selectedShopId, 1);
    });
  });

  group('ออเดอร์ + โหมดออฟไลน์', () {
    test('ออนไลน์: ได้ข้อมูลสดและเก็บลงเครื่อง', () async {
      final store = MemoryLocalStore();
      final state = await signedInState(backend, store: store);
      await state.api.createOrder(shopId: 1, items: {1: 1}, pickupTime: '11:15');
      final (orders, offline) = await state.loadOrders();
      expect(offline, isFalse);
      expect(orders.single.queueNo, 'A-001');
      expect(await store.cachedOrders(history: false), hasLength(1));
    });

    test('เน็ตหลุด: แสดงข้อมูลล่าสุดในเครื่องแทน', () async {
      final state = await signedInState(backend);
      await state.api.createOrder(shopId: 1, items: {1: 1}, pickupTime: '11:15');
      await state.loadOrders();
      backend.offline = true;
      final (orders, offline) = await state.loadOrders();
      expect(offline, isTrue);
      expect(orders.single.queueNo, 'A-001');
    });

    test('เน็ตหลุดและไม่เคยโหลด → แจ้ง error', () async {
      final state = await signedInState(backend);
      backend.offline = true;
      await expectLater(state.loadOrders(history: true), throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)));
    });

    test('เซิร์ฟเวอร์ error (ไม่ใช่เน็ตหลุด) → ไม่ใช้ข้อมูลเก่า', () async {
      final state = await signedInState(backend);
      await state.loadOrders();
      backend.failStatus = 500;
      await expectLater(state.loadOrders(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)));
    });
  });

  group('เมนูโปรด / นำทาง', () {
    test('กดหัวใจ: เปลี่ยนทันทีและส่งไปเซิร์ฟเวอร์', () async {
      final state = await signedInState(backend);
      await state.toggleFavorite(2);
      expect(state.favoriteIds, contains(2));
      expect(backend.favorites, contains(2));
      await state.toggleFavorite(2);
      expect(backend.favorites, isNot(contains(2)));
    });

    test('ส่งไม่สำเร็จ → ย้อนสถานะหัวใจกลับ', () async {
      final state = await signedInState(backend);
      backend.offline = true;
      await expectLater(state.toggleFavorite(2), throwsA(isA<ApiException>()));
      expect(state.favoriteIds, isNot(contains(2)));
    });

    test('openShop / goTab', () async {
      final state = await signedInState(backend);
      state.openShop(2);
      expect((state.tab, state.selectedShopId), (1, 2));
      state.goTab(3);
      expect(state.tab, 3);
    });
  });
}
