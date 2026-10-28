class User {
  final int id;
  final String username;
  final String name;
  final String role;
  final String faculty;
  final String? email;

  User({required this.id, required this.username, required this.name, required this.role, required this.faculty, this.email});

  /// รหัสนักศึกษา KMITL เป็นตัวเลข 8 หลัก (บัญชีบุคลากรใช้ชื่อจากอีเมล)
  bool get hasStudentId => RegExp(r'^\d{8}$').hasMatch(username);

  factory User.fromJson(Map<String, dynamic> j) => User(
      id: j['id'], username: j['username'], name: j['name'], role: j['role'], faculty: j['faculty'] ?? '', email: j['email']);
}

class Shop {
  final int id;
  final String code;
  final String name;
  final String description;
  final String category;
  final String openTime;
  final String closeTime;
  final int prepMin;
  final int prepMax;
  final bool openNow;
  final int queueCount;
  final bool promptpayEnabled;
  final List<MenuItem> menu;
  final List<String> pickupSlots;

  Shop({
    required this.id, required this.code, required this.name, required this.description, required this.category,
    required this.openTime, required this.closeTime, required this.prepMin, required this.prepMax,
    required this.openNow, required this.queueCount, this.promptpayEnabled = false, this.menu = const [], this.pickupSlots = const [],
  });

  factory Shop.fromJson(Map<String, dynamic> j) => Shop(
        id: j['id'], code: j['code'], name: j['name'], description: j['description'] ?? '', category: j['category'],
        openTime: j['open_time'], closeTime: j['close_time'], prepMin: j['prep_min'], prepMax: j['prep_max'],
        openNow: j['open_now'] == true, queueCount: j['queue_count'] ?? 0,
        promptpayEnabled: j['promptpay_enabled'] == true,
        menu: (j['menu'] as List? ?? []).map((e) => MenuItem.fromJson(e)).toList(),
        pickupSlots: (j['pickup_slots'] as List? ?? []).cast<String>(),
      );
}

class MenuItem {
  final int id;
  final int shopId;
  final String name;
  final String description;
  final int price;
  final bool isAvailable;
  final String? shopName;
  final String? imageUrl;

  MenuItem({required this.id, required this.shopId, required this.name, required this.description,
      required this.price, required this.isAvailable, this.shopName, this.imageUrl});

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id: j['id'], shopId: j['shop_id'], name: j['name'], description: j['description'] ?? '',
        price: j['price'], isAvailable: j['is_available'] == true, shopName: j['shop_name'],
        imageUrl: j['image_url'],
      );
}

class AiPick {
  final int menuItemId;
  final String name;
  final int price;
  final int shopId;
  final String shopName;
  final String reason;
  final String? imageUrl;

  AiPick({required this.menuItemId, required this.name, required this.price, required this.shopId, required this.shopName, required this.reason, this.imageUrl});

  factory AiPick.fromJson(Map<String, dynamic> j) => AiPick(
        menuItemId: j['menu_item_id'], name: j['name'], price: j['price'],
        shopId: j['shop_id'], shopName: j['shop_name'], reason: j['reason'] ?? '', imageUrl: j['image_url'],
      );
}

class AiReply {
  final String reply;
  final List<AiPick> items;
  AiReply(this.reply, this.items);

  factory AiReply.fromJson(Map<String, dynamic> j) =>
      AiReply(j['reply'] ?? '', (j['items'] as List? ?? []).map((e) => AiPick.fromJson(e)).toList());
}

class OrderLine {
  final int? menuItemId;
  final String name;
  final int price;
  final int qty;

  OrderLine({this.menuItemId, required this.name, required this.price, required this.qty});

  factory OrderLine.fromJson(Map<String, dynamic> j) =>
      OrderLine(menuItemId: j['menu_item_id'], name: j['name'], price: j['price'], qty: j['qty']);
}

class Order {
  final int id;
  final String queueNo;
  final String status;
  final String statusLabel;
  final int shopId;
  final String shopName;
  final List<OrderLine> items;
  final String pickupTime;
  final String note;
  final int total;
  final int queueAhead;
  final String? cancelReason;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? cookingAt;
  final DateTime? readyAt;
  final String paymentMethod; // cash | promptpay
  final String paymentStatus; // unpaid | slip_uploaded | paid | rejected
  final String? paymentNote;

  Order({
    required this.id, required this.queueNo, required this.status, required this.statusLabel,
    required this.shopId, required this.shopName, required this.items, required this.pickupTime,
    required this.note, required this.total, required this.queueAhead, this.cancelReason,
    required this.createdAt, this.acceptedAt, this.cookingAt, this.readyAt,
    this.paymentMethod = 'cash', this.paymentStatus = 'unpaid', this.paymentNote,
  });

  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v).toLocal();

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'], queueNo: j['queue_no'], status: j['status'], statusLabel: j['status_label'],
        shopId: j['shop']['id'], shopName: j['shop']['name'],
        items: (j['items'] as List).map((e) => OrderLine.fromJson(e)).toList(),
        pickupTime: j['pickup_time'], note: j['note'] ?? '', total: j['total'], queueAhead: j['queue_ahead'] ?? 0,
        cancelReason: j['cancel_reason'], createdAt: _dt(j['created_at'])!,
        acceptedAt: _dt(j['accepted_at']), cookingAt: _dt(j['cooking_at']), readyAt: _dt(j['ready_at']),
        paymentMethod: j['payment_method'] ?? 'cash', paymentStatus: j['payment_status'] ?? 'unpaid',
        paymentNote: j['payment_note'],
      );
}

extension OrderPayment on Order {
  bool get isPromptPay => paymentMethod == 'promptpay';
  /// ยังต้องโอน/แนบสลิปใหม่ (ออเดอร์ยังไม่ถูกยกเลิก)
  bool get needsPayment => isPromptPay && (paymentStatus == 'unpaid' || paymentStatus == 'rejected') && status != 'cancelled';
  String get paymentLabel => switch ((paymentMethod, paymentStatus)) {
        (_, 'paid') => 'ชำระเงินแล้ว',
        ('cash', _) => 'จ่ายที่ร้าน',
        (_, 'slip_uploaded') => 'รอร้านตรวจสลิป',
        (_, 'rejected') => 'สลิปไม่ผ่าน',
        _ => 'รอโอนเงิน',
      };
}

class PaymentInfo {
  final int orderId;
  final String queueNo;
  final int amount;
  final String shopName;
  final String method;
  final String status;
  final String? note;
  final bool hasSlip;
  final String? promptpayMasked;
  final String? qrPayload;

  PaymentInfo({
    required this.orderId, required this.queueNo, required this.amount, required this.shopName, required this.method,
    required this.status, this.note, required this.hasSlip, this.promptpayMasked, this.qrPayload,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> j) => PaymentInfo(
        orderId: j['order_id'], queueNo: j['queue_no'], amount: j['amount'], shopName: j['shop_name'], method: j['method'],
        status: j['status'], note: j['note'], hasSlip: j['has_slip'] == true,
        promptpayMasked: j['promptpay_masked'], qrPayload: j['qr_payload'],
      );
}
