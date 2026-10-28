import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  final api = Api();
  Vendor? user;
  bool restoring = true;
  int tab = 0;

  AppState() {
    api.onUnauthorized = logout;
  }

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('vendor_token');
      if (token != null) {
        api.token = token;
        try {
          user = await api.me();
          if (user!.role != 'vendor') user = null;
        } catch (_) {
          api.token = null;
        }
      }
    } catch (e) {
      // อ่านข้อมูลที่บันทึกไว้ไม่ได้ → ไปหน้า Login แทนการค้างที่หน้าโหลด
      debugPrint('restore failed: $e');
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    final (token, u) = await api.login(username.trim(), password);
    if (u.role != 'vendor') throw ApiException(403, 'แอปนี้สำหรับบัญชีร้านค้าเท่านั้น');
    api.token = token;
    user = u;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString('vendor_token', token);
    } catch (e) {
      debugPrint('save token failed: $e');
    }
  }

  Future<void> logout() async {
    api.token = null;
    user = null;
    tab = 0;
    pendingCount = 0;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).remove('vendor_token');
    } catch (e) {
      debugPrint('clear token failed: $e');
    }
  }

  void setUser(Vendor u) {
    user = u;
    notifyListeners();
  }

  /// จำนวนออเดอร์ใหม่ที่รอร้านรับ (ใช้แสดงแถบเตือนทุกแท็บ)
  int pendingCount = 0;

  void setPendingCount(int n) {
    if (n == pendingCount) return;
    pendingCount = n;
    notifyListeners();
  }

  void goTab(int i) {
    tab = i;
    notifyListeners();
  }
}
