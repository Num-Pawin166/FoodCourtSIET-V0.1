import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/models.dart';
import '../support/fake_backend.dart';

final _order = <String, dynamic>{
  'id': 1, 'queue_no': 'A-001', 'status': 'pending', 'status_label': 'รอร้านรับออเดอร์',
  'shop': {'id': 1, 'name': 'ร้าน A'}, 'items': [{'menu_item_id': 1, 'name': 'ข้าวขาหมู', 'price': 50, 'qty': 2}],
  'pickup_time': '11:15', 'note': '', 'total': 100, 'queue_ahead': 0, 'cancel_reason': null,
  'created_at': '2026-10-20T04:00:00.000Z', 'accepted_at': null, 'cooking_at': null, 'ready_at': null,
};

void main() {
  final backend = FakeBackend();

  group('แปลง JSON จาก API', () {
    test('User: รู้ว่ามีรหัสนักศึกษา 8 หลักหรือไม่', () {
      final u = User.fromJson(backend.user);
      expect(u.name, 'สมชาย ใจดี');
      expect(u.hasStudentId, isTrue);
      expect(User.fromJson({...backend.user, 'username': 'somchai.j'}).hasStudentId, isFalse);
    });

    test('Shop: อ่านเมนู ช่วงเวลารับ และพร้อมเพย์', () {
      final s = Shop.fromJson({...backend.shop(1), 'menu': backend.menuOf(1), 'pickup_slots': ['11:15']});
      expect(s.code, 'A');
      expect(s.openNow, isTrue);
      expect(s.promptpayEnabled, isTrue);
      expect(s.menu, hasLength(3));
      expect(s.menu[2].isAvailable, isFalse);
      expect(s.pickupSlots, ['11:15']);
    });

    test('Shop / MenuItem / AiPick: toJson แล้ว fromJson ได้ค่าเดิม (ใช้บันทึกลงเครื่อง)', () {
      final s = Shop.fromJson(backend.shop(2));
      final s2 = Shop.fromJson(s.toJson());
      expect([s2.id, s2.name, s2.category, s2.prepMax, s2.queueCount, s2.promptpayEnabled],
          [s.id, s.name, s.category, s.prepMax, s.queueCount, s.promptpayEnabled]);
      final m = MenuItem.fromJson({...FakeBackend.menu(1, 1, 'ข้าวขาหมู', 50), 'shop_name': 'ร้าน A'});
      final m2 = MenuItem.fromJson(m.toJson());
      expect([m2.id, m2.shopId, m2.name, m2.price, m2.isAvailable, m2.shopName], [1, 1, 'ข้าวขาหมู', 50, true, 'ร้าน A']);
      final p = AiPick(menuItemId: 2, name: 'x', price: 45, shopId: 1, shopName: 'ร้าน A', reason: 'คิวน้อย');
      expect(AiPick.fromJson(p.toJson()).reason, 'คิวน้อย');
    });

    test('AiReply: ไม่มี items ก็ไม่พัง', () {
      expect(AiReply.fromJson({'reply': 'ไม่เจอเมนู'}).items, isEmpty);
    });

    test('Order: เวลาแปลงเป็นเวลาเครื่อง และรายการอาหาร', () {
      final o = Order.fromJson({..._order, 'accepted_at': '2026-10-20T04:05:00.000Z'});
      expect(o.queueNo, 'A-001');
      expect(o.items.single.qty, 2);
      expect(o.acceptedAt!.isUtc, isFalse);
      expect(o.cookingAt, isNull);
      expect(o.paymentMethod, 'cash'); // API เก่าที่ไม่มีฟิลด์ชำระเงิน
    });

    test('PaymentInfo', () {
      final p = PaymentInfo.fromJson({
        'order_id': 1, 'queue_no': 'A-001', 'amount': 100, 'shop_name': 'ร้าน A', 'method': 'promptpay',
        'status': 'unpaid', 'note': null, 'has_slip': false, 'promptpay_masked': '081-xxx-5678', 'qr_payload': '000201',
      });
      expect(p.hasSlip, isFalse);
      expect(p.qrPayload, '000201');
    });
  });

  group('สถานะการชำระเงินของออเดอร์', () {
    Order order(String method, String status, {String orderStatus = 'pending'}) =>
        Order.fromJson({..._order, 'payment_method': method, 'payment_status': status, 'status': orderStatus});

    test('ป้ายสถานะตรงกับทุกกรณี', () {
      expect(order('cash', 'unpaid').paymentLabel, 'จ่ายที่ร้าน');
      expect(order('cash', 'paid').paymentLabel, 'ชำระเงินแล้ว');
      expect(order('promptpay', 'unpaid').paymentLabel, 'รอโอนเงิน');
      expect(order('promptpay', 'slip_uploaded').paymentLabel, 'รอร้านตรวจสลิป');
      expect(order('promptpay', 'rejected').paymentLabel, 'สลิปไม่ผ่าน');
      expect(order('promptpay', 'paid').paymentLabel, 'ชำระเงินแล้ว');
    });

    test('needsPayment: ต้องโอน/แนบใหม่เฉพาะพร้อมเพย์ที่ยังไม่จ่ายและไม่ถูกยกเลิก', () {
      expect(order('promptpay', 'unpaid').needsPayment, isTrue);
      expect(order('promptpay', 'rejected').needsPayment, isTrue);
      expect(order('promptpay', 'slip_uploaded').needsPayment, isFalse);
      expect(order('promptpay', 'unpaid', orderStatus: 'cancelled').needsPayment, isFalse);
      expect(order('cash', 'unpaid').needsPayment, isFalse);
    });
  });
}
