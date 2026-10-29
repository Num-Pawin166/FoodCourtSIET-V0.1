import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_vendor/api.dart';
import 'package:foodcourt_vendor/app_state.dart';
import 'package:foodcourt_vendor/order_alarm.dart';
import 'package:foodcourt_vendor/reviews.dart';
import 'package:foodcourt_vendor/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:provider/provider.dart';

/// backend ฝั่งร้านค้าจำลอง (รูปแบบ JSON เดียวกับ /api/vendor/* ของจริง)
class FakeVendorBackend {
  static const token = 'vendor-token';
  bool offline = false;
  int? failStatus;
  final requests = <http.Request>[];
  final orders = <Map<String, dynamic>>[];
  final menu = <Map<String, dynamic>>[
    {'id': 1, 'shop_id': 1, 'name': 'ข้าวขาหมู', 'description': 'พร้อมน้ำซุป', 'price': 50, 'is_available': true, 'image_url': null, 'sort_order': 0},
    {'id': 2, 'shop_id': 1, 'name': 'ข้าวมันไก่ทอด', 'description': '', 'price': 45, 'is_available': false, 'image_url': '/api/images/9', 'sort_order': 1},
  ];
  Map<String, dynamic> shop = {
    'id': 1, 'code': 'A', 'name': 'ร้านข้าวขาหมูป้าแดง', 'description': 'ข้าวขาหมู', 'category': 'อาหารจานเดียว',
    'open_time': '07:30', 'close_time': '17:00', 'prep_min': 5, 'prep_max': 10, 'is_open': true, 'open_now': true,
    'queue_count': 0, 'promptpay_enabled': false, 'promptpay_id': null, 'image_url': null,
  };
  String userName = 'เจ้าของร้าน A';
  String role = 'vendor';
  String password = '1234';
  List<int>? uploadedImage;

  late final client = MockClient(_handle);

  Map<String, dynamic> get user => {'id': 2, 'username': 'shopa', 'name': userName, 'role': role};

  /// เพิ่มออเดอร์ใหม่ (เหมือนนักศึกษาเพิ่งสั่ง)
  Map<String, dynamic> addOrder({String payment = 'cash', String paymentStatus = 'unpaid', String note = ''}) {
    final o = {
      'id': 100 + orders.length, 'queue_no': 'A-${(orders.length + 1).toString().padLeft(3, '0')}', 'status': 'pending',
      'user': {'id': 7, 'name': 'สมชาย ใจดี'}, 'items': [{'name': 'ข้าวขาหมู', 'qty': 2, 'price': 50}],
      'pickup_time': '11:30', 'note': note, 'total': 100, 'cancel_reason': null, 'created_at': '2026-10-20T04:00:00.000Z',
      'payment_method': payment, 'payment_status': paymentStatus, 'has_slip': paymentStatus == 'slip_uploaded', 'payment_note': null,
    };
    orders.add(o);
    return o;
  }

  http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  Future<http.Response> _handle(http.Request req) async {
    requests.add(req);
    if (offline) throw http.ClientException('offline');
    if (failStatus != null) return _json({'error': 'เซิร์ฟเวอร์ผิดพลาด'}, failStatus!);
    final path = req.url.path.replaceFirst(RegExp(r'^.*/api'), '');
    Map<String, dynamic> body() => req.body.isEmpty ? {} : jsonDecode(req.body);

    if (req.method == 'POST' && path == '/auth/login') {
      final b = body();
      if (b['username'] == '65010001') {
        return _json({'token': 'student', 'user': {'id': 7, 'username': '65010001', 'name': 'นักศึกษา', 'role': 'student'}});
      }
      if (b['username'] != 'shopa' || b['password'] != password) return _json({'error': 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'}, 401);
      return _json({'token': token, 'user': user});
    }
    if (req.headers['Authorization'] != 'Bearer $token') return _json({'error': 'กรุณาเข้าสู่ระบบ'}, 401);

    switch ((req.method, path)) {
      case ('GET', '/auth/me'):
        return _json(user);
      case ('PATCH', '/auth/me'):
        userName = body()['name'];
        return _json(user);
      case ('PATCH', '/auth/me/password'):
        final b = body();
        if (b['current_password'] != password) return _json({'error': 'รหัสผ่านเดิมไม่ถูกต้อง'}, 400);
        password = b['new_password'];
        return _json({'ok': true});
      case ('GET', '/vendor/shop'):
        return _json(shop);
      case ('PATCH', '/vendor/shop'):
        final b = body();
        if (b['promptpay_id'] == '123') return _json({'error': 'หมายเลขพร้อมเพย์ไม่ถูกต้อง'}, 400);
        shop = {...shop, ...b};
        if (b.containsKey('promptpay_id')) shop['promptpay_id'] = (b['promptpay_id'] as String).isEmpty ? null : b['promptpay_id'];
        return _json(shop);
      case ('POST', '/vendor/shop/image'):
        uploadedImage = req.bodyBytes;
        shop['image_url'] = '/api/images/50';
        return _json(shop);
      case ('DELETE', '/vendor/shop/image'):
        shop['image_url'] = null;
        return _json(shop);
      case ('GET', '/vendor/summary'):
        final live = orders.where((o) => o['status'] != 'cancelled');
        return _json({
          'orders': orders.length, 'revenue': live.fold<int>(0, (s, o) => s + (o['total'] as int)),
          'cancelled': orders.length - live.length,
          'in_progress': orders.where((o) => ['pending', 'accepted', 'cooking'].contains(o['status'])).length,
          'top_items': orders.isEmpty ? [] : [{'name': 'ข้าวขาหมู', 'qty': 2}],
        });
      case ('GET', '/vendor/orders'):
        final today = req.url.queryParameters['scope'] == 'today';
        return _json(today ? orders : orders.where((o) => ['pending', 'accepted', 'cooking', 'ready'].contains(o['status'])).toList());
      case ('GET', '/vendor/menu'):
        return _json(menu);
      case ('POST', '/vendor/menu'):
        final m = {'id': 10 + menu.length, 'shop_id': 1, 'image_url': null, 'sort_order': 0, 'is_available': true, ...body()};
        menu.add(m);
        return _json(m, 201);
    }
    final menuMatch = RegExp(r'^/vendor/menu/(\d+)(/image)?$').firstMatch(path);
    if (menuMatch != null) {
      final m = menu.firstWhere((m) => m['id'] == int.parse(menuMatch[1]!));
      if (menuMatch[2] != null) {
        if (req.method == 'POST') uploadedImage = req.bodyBytes;
        m['image_url'] = req.method == 'POST' ? '/api/images/77' : null;
        return _json(m);
      }
      if (req.method == 'DELETE') {
        menu.remove(m);
        return _json({'ok': true});
      }
      m.addAll(body());
      return _json(m);
    }
    final ord = RegExp(r'^/vendor/orders/(\d+)/(status|payment|slip)$').firstMatch(path);
    if (ord != null) {
      final o = orders.firstWhere((o) => o['id'] == int.parse(ord[1]!));
      final b = req.method == 'GET' ? <String, dynamic>{} : body();
      switch (ord[2]) {
        case 'status':
          o['status'] = b['status'];
          if (b['reason'] != null) o['cancel_reason'] = b['reason'];
          return _json(o);
        case 'payment':
          o['payment_status'] = b['action'] == 'confirm' ? 'paid' : 'rejected';
          o['payment_note'] = b['reason'];
          return _json(o);
        case 'slip':
          return http.Response.bytes(tinyPng, 200, headers: {'content-type': 'image/png'});
      }
    }
    return _json({'error': 'ไม่พบ endpoint นี้'}, 404);
  }
}

/// เสียงจำลอง: นับจำนวนครั้งที่ดัง
class FakeSound implements AlarmSound {
  int plays = 0;
  int stops = 0;
  @override
  Future<void> play() async => plays++;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}
}

class FakeImagePicker extends ImagePickerPlatform {
  Uint8List? next;
  ImageSource? lastSource;
  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    lastSource = source;
    return next == null ? null : XFile.fromData(next!, name: 'photo.png');
  }
}

/// PNG 1×1 จริง
final tinyPng = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));

AppState fakeState(FakeVendorBackend backend, {FakeSound? sound, ReviewFeed? reviews}) {
  final s = sound ?? FakeSound();
  return AppState(api: Api(client: backend.client), alarm: OrderAlarm(sound: () => s), reviews: reviews);
}

/// รีวิวบน Firestore จำลอง (fake_cloud_firestore)
ReviewFeed fakeFeed(FakeFirebaseFirestore db) => ReviewFeed(db, signIn: () async => 'vendor-uid');

/// ใส่รีวิวลง Firestore จำลอง (เหมือนนักศึกษาเพิ่งรีวิวจากแอปนักศึกษา)
Future<void> seedReview(FakeFirebaseFirestore db, int orderId, int rating,
        {int shopId = 1, String name = 'สมชาย ใ.', String comment = '', int day = 1}) =>
    db.collection('reviews').doc('order_$orderId').set({
      'shopId': shopId, 'orderId': orderId, 'rating': rating, 'comment': comment, 'authorName': name,
      'authorUid': 'student-$orderId', 'updatedAt': Timestamp.fromDate(DateTime(2026, 10, day, 12)),
    });

Future<AppState> signedInState(FakeVendorBackend backend, {FakeSound? sound, ReviewFeed? reviews}) async {
  final state = fakeState(backend, sound: sound, reviews: reviews);
  await state.login('shopa', '1234');
  state.restoring = false;
  return state;
}

Widget wrap(AppState state, Widget child) => ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: Scaffold(body: child)),
    );

void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
