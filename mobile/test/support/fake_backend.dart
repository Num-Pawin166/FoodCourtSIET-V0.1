import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/api.dart';
import 'package:foodcourt_siet/app_state.dart';
import 'package:foodcourt_siet/local_db.dart';
import 'package:foodcourt_siet/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// backend จำลองในหน่วยความจำ: ตอบเหมือน API จริง (รูปแบบ JSON เดียวกับ backend/src)
/// ใช้ใน widget test และ integration test โดยไม่ต้องต่อเซิร์ฟเวอร์จริง
class FakeBackend {
  static const token = 'test-token';
  bool offline = false; // จำลองเน็ตหลุด
  bool promptpay = true;
  int? failStatus; // บังคับให้ทุก request ตอบ error นี้
  final requests = <http.Request>[];
  final orders = <Map<String, dynamic>>[];
  final favorites = <int>{1};
  String paymentStatus = 'unpaid';
  List<int>? slip;

  late final client = MockClient(_handle);

  Map<String, dynamic> get user => {
        'id': 7, 'username': '65010001', 'name': 'สมชาย ใจดี', 'role': 'student',
        'faculty': 'SIET - KMITL', 'email': null,
      };

  static Map<String, dynamic> menu(int id, int shopId, String name, int price, {bool available = true}) => {
        'id': id, 'shop_id': shopId, 'name': name, 'description': '', 'price': price,
        'is_available': available, 'image_url': null, 'sort_order': 0,
      };

  Map<String, dynamic> shop(int id) {
    final base = {
      1: {'code': 'A', 'name': 'ร้านข้าวขาหมูป้าแดง', 'category': 'อาหารจานเดียว', 'description': 'ข้าวขาหมู ข้าวมันไก่'},
      2: {'code': 'B', 'name': 'ก๋วยเตี๋ยวลุงชัย', 'category': 'เส้น', 'description': 'ก๋วยเตี๋ยวหมูน้ำใส'},
    }[id]!;
    return {
      'id': id, ...base, 'open_time': '07:30', 'close_time': '17:00', 'prep_min': 5, 'prep_max': 10,
      'is_open': true, 'open_now': true, 'image_url': null, 'queue_count': id == 1 ? 2 : 0,
      'promptpay_enabled': id == 1 && promptpay,
    };
  }

  List<Map<String, dynamic>> menuOf(int shopId) => shopId == 1
      ? [menu(1, 1, 'ข้าวขาหมู', 50), menu(2, 1, 'ข้าวมันไก่ทอด', 45), menu(3, 1, 'ข้าวหมูกรอบ', 55, available: false)]
      : [menu(5, 2, 'ก๋วยเตี๋ยวหมูน้ำใส', 45)];

  Map<String, dynamic> _order(Map<String, dynamic> body) {
    final shopId = body['shop_id'] as int;
    final items = [
      for (final it in body['items'] as List)
        () {
          final m = menuOf(shopId).firstWhere((m) => m['id'] == it['menu_item_id']);
          return {'menu_item_id': m['id'], 'name': m['name'], 'price': m['price'], 'qty': it['qty']};
        }(),
    ];
    final total = items.fold<int>(0, (s, i) => s + (i['price'] as int) * (i['qty'] as int));
    return {
      'id': 100 + orders.length, 'queue_no': '${shop(shopId)['code']}-${(orders.length + 1).toString().padLeft(3, '0')}',
      'status': 'pending', 'status_label': 'รอร้านรับออเดอร์', 'shop': {'id': shopId, 'name': shop(shopId)['name'], 'code': 'A'},
      'user': {'id': 7}, 'items': items, 'item_count': items.length, 'pickup_time': body['pickup_time'], 'note': body['note'] ?? '',
      'total': total, 'cancel_reason': null, 'queue_ahead': 1, 'payment_method': body['payment_method'] ?? 'cash',
      'payment_status': 'unpaid', 'has_slip': false, 'payment_note': null, 'paid_at': null,
      'created_at': '2026-10-20T04:00:00.000Z', 'accepted_at': null, 'cooking_at': null, 'ready_at': null,
      'completed_at': null, 'cancelled_at': null,
    };
  }

  http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  Future<http.Response> _handle(http.Request req) async {
    requests.add(req);
    if (offline) throw http.ClientException('offline');
    if (failStatus != null) return _json({'error': 'เซิร์ฟเวอร์ผิดพลาด'}, failStatus!);
    final path = req.url.path.replaceFirst(RegExp(r'^.*/api'), '');
    final q = req.url.queryParameters;
    final authed = req.headers['Authorization'] == 'Bearer $token';
    Map<String, dynamic> body() => req.body.isEmpty ? {} : jsonDecode(req.body);

    switch ((req.method, path)) {
      case ('GET', '/auth/config'):
        return _json({'google_client_id': null, 'allowed_domain': 'kmitl.ac.th'});
      case ('POST', '/auth/login'):
        final b = body();
        if (b['username'] == 'shopa') {
          return _json({'token': 'vendor-token', 'user': {...user, 'username': 'shopa', 'role': 'vendor'}});
        }
        if (b['username'] != '65010001' || b['password'] != '1234') return _json({'error': 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'}, 401);
        return _json({'token': token, 'user': user});
      case ('GET', '/categories'):
        return _json(['อาหารจานเดียว', 'เส้น']);
      case ('GET', '/shops'):
        final all = [shop(1), shop(2)];
        final query = q['q'] ?? '';
        final cat = q['category'] ?? '';
        return _json(all.where((s) =>
            (query.isEmpty || '${s['name']}${menuOf(s['id'] as int).map((m) => m['name']).join()}'.contains(query)) &&
            (cat.isEmpty || s['category'] == cat)).toList());
    }
    final shopMatch = RegExp(r'^/shops/(\d+)(/slots)?$').firstMatch(path);
    if (shopMatch != null) {
      final id = int.parse(shopMatch[1]!);
      if (shopMatch[2] != null) return _json(['11:15', '11:30', '11:45']);
      return _json({...shop(id), 'menu': menuOf(id), 'pickup_slots': ['11:15', '11:30', '11:45']});
    }

    // ต่อจากนี้ต้องล็อกอิน
    if (!authed) return _json({'error': 'กรุณาเข้าสู่ระบบ'}, 401);
    switch ((req.method, path)) {
      case ('GET', '/auth/me'):
        return _json(user);
      case ('GET', '/auth/me/stats'):
        return _json({'orders_this_month': orders.length, 'spent_this_month': orders.fold<int>(0, (s, o) => s + (o['total'] as int))});
      case ('GET', '/favorites'):
        return _json([for (final id in favorites) {...menuOf(1).firstWhere((m) => m['id'] == id), 'shop_name': 'ร้านข้าวขาหมูป้าแดง'}]);
      case ('GET', '/orders'):
        final history = q['scope'] == 'history';
        return _json(orders.where((o) => ['completed', 'cancelled'].contains(o['status']) == history).toList().reversed.toList());
      case ('POST', '/orders'):
        final o = _order(body());
        orders.add(o);
        return _json(o, 201);
      case ('POST', '/ai/chat'):
        final text = ((body()['messages'] as List).last as Map)['text'] as String;
        return _json({
          'reply': 'ได้เลย! สำหรับ "$text" ลองเมนูนี้',
          'items': [
            {'menu_item_id': 2, 'name': 'ข้าวมันไก่ทอด', 'price': 45, 'shop_id': 1, 'shop_name': 'ร้านข้าวขาหมูป้าแดง', 'reason': 'คิวน้อย', 'image_url': null},
          ],
          'source': 'rules',
        });
    }
    final fav = RegExp(r'^/favorites/(\d+)$').firstMatch(path);
    if (fav != null) {
      final id = int.parse(fav[1]!);
      req.method == 'PUT' ? favorites.add(id) : favorites.remove(id);
      return _json({'ok': true});
    }
    final ord = RegExp(r'^/orders/(\d+)(?:/(\w+))?$').firstMatch(path);
    if (ord != null) {
      final o = orders.where((o) => o['id'] == int.parse(ord[1]!)).firstOrNull;
      if (o == null) return _json({'error': 'ไม่พบออเดอร์นี้'}, 404);
      switch ((req.method, ord[2])) {
        case ('POST', 'cancel'):
          o['status'] = 'cancelled';
          o['cancel_reason'] = 'ลูกค้ายกเลิก';
          return _json(o);
        case ('GET', 'payment'):
          return _json({
            'order_id': o['id'], 'queue_no': o['queue_no'], 'amount': o['total'], 'shop_name': o['shop']['name'],
            'method': o['payment_method'], 'status': paymentStatus, 'note': paymentStatus == 'rejected' ? 'ยอดไม่ตรง' : null,
            'has_slip': slip != null, 'promptpay_masked': '081-xxx-5678',
            'qr_payload': paymentStatus == 'paid' ? null : '00020101021229370016A000000677010111011300668123456785303764540550.005802TH6304ABCD',
          });
        case ('POST', 'slip'):
          slip = req.bodyBytes;
          paymentStatus = 'slip_uploaded';
          return _json({...o, 'payment_status': paymentStatus, 'has_slip': true});
      }
    }
    return _json({'error': 'ไม่พบ endpoint นี้'}, 404);
  }
}

/// สร้าง AppState ที่ต่อกับ backend จำลอง + ฐานข้อมูลในหน่วยความจำ
AppState fakeState(FakeBackend backend, {LocalStore? store}) =>
    AppState(api: Api(client: backend.client), store: store ?? MemoryLocalStore());

/// ล็อกอินไว้ก่อน (ข้ามหน้า Login)
Future<AppState> signedInState(FakeBackend backend, {LocalStore? store}) async {
  final state = fakeState(backend, store: store);
  await state.login('65010001', '1234');
  state.restoring = false;
  return state;
}

/// ห่อหน้าจอด้วย Provider + ธีมของแอป
Widget wrap(AppState state, Widget child) => ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: Scaffold(body: child)),
    );

/// จอขนาดมือถือ (390×844) ให้เลย์เอาต์เหมือนใช้จริง
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
