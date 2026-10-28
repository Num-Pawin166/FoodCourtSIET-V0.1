import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class Api {
  String? token;
  void Function()? onUnauthorized;

  /// ส่ง request: body เป็น JSON หรือ bytes (ไฟล์รูป) — คืน response ดิบเมื่อสำเร็จ
  Future<http.Response> _request(String method, String path, {Object? json, List<int>? bytes}) async {
    final req = http.Request(method, Uri.parse('$apiBase$path'))
      ..headers.addAll({if (token != null) 'Authorization': 'Bearer $token'});
    if (bytes != null) {
      req.headers['Content-Type'] = 'application/octet-stream'; // server ตรวจชนิดรูปจากเนื้อไฟล์เอง
      req.bodyBytes = bytes;
    } else {
      req.headers['Content-Type'] = 'application/json';
      if (json != null) req.body = jsonEncode(json);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 70)));
    } catch (_) {
      throw ApiException(0, 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ลองใหม่อีกครั้ง (เซิร์ฟเวอร์ฟรีอาจกำลังตื่น ~1 นาที)');
    }
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    if (res.statusCode >= 400) {
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {}
      throw ApiException(res.statusCode, (data is Map ? data['error'] : null) ?? 'เกิดข้อผิดพลาด (${res.statusCode})');
    }
    return res;
  }

  Future<dynamic> _send(String method, String path, [Object? body, List<int>? bytes]) async {
    final res = await _request(method, path, json: body, bytes: bytes);
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  // auth
  Future<(String, User)> login(String username, String password) async {
    final d = await _send('POST', '/auth/login', {'username': username, 'password': password});
    return (d['token'] as String, User.fromJson(d['user']));
  }

  Future<(String, User)> loginWithGoogle(String idToken) async {
    final d = await _send('POST', '/auth/google', {'id_token': idToken});
    return (d['token'] as String, User.fromJson(d['user']));
  }

  /// { google_client_id, allowed_domain } — client ID ตั้งไว้ที่ backend/.env ที่เดียว
  Future<Map<String, dynamic>> authConfig() async => Map<String, dynamic>.from(await _send('GET', '/auth/config'));

  Future<User> me() async => User.fromJson(await _send('GET', '/auth/me'));
  Future<Map<String, dynamic>> myStats() async => Map<String, dynamic>.from(await _send('GET', '/auth/me/stats'));

  // ร้าน
  Future<List<String>> categories() async => (await _send('GET', '/categories') as List).cast<String>();

  Future<List<Shop>> shops({String q = '', String category = ''}) async {
    final qs = Uri(queryParameters: {if (q.isNotEmpty) 'q': q, if (category.isNotEmpty) 'category': category}).query;
    return (await _send('GET', '/shops${qs.isEmpty ? '' : '?$qs'}') as List).map((e) => Shop.fromJson(e)).toList();
  }

  Future<Shop> shop(int id) async => Shop.fromJson(await _send('GET', '/shops/$id'));
  Future<List<String>> slots(int shopId) async => (await _send('GET', '/shops/$shopId/slots') as List).cast<String>();

  // เมนูโปรด
  Future<List<MenuItem>> favorites() async =>
      (await _send('GET', '/favorites') as List).map((e) => MenuItem.fromJson(e)).toList();
  Future<void> setFavorite(int menuItemId, bool fav) => _send(fav ? 'PUT' : 'DELETE', '/favorites/$menuItemId');

  // ออเดอร์
  Future<Order> createOrder({
    required int shopId, required Map<int, int> items, required String pickupTime, String note = '', String paymentMethod = 'cash',
  }) async {
    final d = await _send('POST', '/orders', {
      'shop_id': shopId,
      'items': [for (final e in items.entries) {'menu_item_id': e.key, 'qty': e.value}],
      'pickup_time': pickupTime,
      'note': note,
      'payment_method': paymentMethod,
    });
    return Order.fromJson(d);
  }

  // ชำระเงิน
  Future<PaymentInfo> payment(int orderId) async => PaymentInfo.fromJson(await _send('GET', '/orders/$orderId/payment'));
  Future<Order> uploadSlip(int orderId, List<int> imageBytes) async =>
      Order.fromJson(await _send('POST', '/orders/$orderId/slip', null, imageBytes));
  Future<List<int>> slipBytes(int orderId) async => (await _request('GET', '/orders/$orderId/slip')).bodyBytes;

  Future<List<Order>> orders({bool history = false}) async =>
      (await _send('GET', '/orders?scope=${history ? 'history' : 'active'}') as List).map((e) => Order.fromJson(e)).toList();

  Future<Order> cancelOrder(int id) async => Order.fromJson(await _send('POST', '/orders/$id/cancel'));

  // ผู้ช่วยแนะนำเมนู — messages: [{'role': 'user'|'assistant', 'text': ...}]
  Future<AiReply> aiChat(List<Map<String, String>> messages) async =>
      AiReply.fromJson(await _send('POST', '/ai/chat', {'messages': messages}));
}
