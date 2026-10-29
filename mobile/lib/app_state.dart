import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'google_auth.dart';
import 'local_db.dart';
import 'models.dart';

/// สถานะกลางของแอป: บัญชีผู้ใช้, แท็บปัจจุบัน, ร้านที่เลือก, ตะกร้า, เมนูโปรด
class AppState extends ChangeNotifier {
  final Api api;
  /// ฐานข้อมูลในเครื่อง: ตะกร้า / ออเดอร์ล่าสุด / แชท AI
  final LocalStore store;

  User? user;
  bool restoring = true;

  AppState({Api? api, LocalStore? store})
      : api = api ?? Api(),
        store = store ?? LocalStore.platformDefault() {
    this.api.onUnauthorized = logout;
  }

  // ---------- auth ----------
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token != null) {
        api.token = token;
        try {
          user = await api.me();
          await loadFavorites();
          await _restoreCart();
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

  Future<void> _signedIn(String token, User u) async {
    if (u.role != 'student') {
      throw ApiException(403, 'บัญชีร้านค้า/ผู้ดูแล กรุณาใช้งานผ่านเว็บหลังบ้าน');
    }
    api.token = token;
    user = u;
    try {
      await (await SharedPreferences.getInstance()).setString('token', token);
    } catch (e) {
      debugPrint('save token failed: $e'); // ล็อกอินได้ แค่ต้องล็อกอินใหม่เมื่อเปิดแอปครั้งหน้า
    }
    await loadFavorites().catchError((_) {});
    await _restoreCart();
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final (token, u) = await api.login(username.trim(), password);
    await _signedIn(token, u);
  }

  Future<void> loginWithGoogle(String idToken) async {
    final (token, u) = await api.loginWithGoogle(idToken);
    await _signedIn(token, u);
  }

  Future<void> logout() async {
    try {
      await GoogleAuth.signOut(); // กันไม่ให้ Google ล็อกอินบัญชีเดิมให้อัตโนมัติ
    } catch (_) {}
    api.token = null;
    user = null;
    tab = 0;
    selectedShopId = null;
    clearCart(persist: false);
    favoriteIds.clear();
    notifyListeners();
    try {
      await store.clearAll(); // เครื่องที่ใช้ร่วมกัน: คนถัดไปต้องไม่เห็นตะกร้า/ออเดอร์/แชทของเรา
    } catch (e) {
      debugPrint('clear local db failed: $e');
    }
    try {
      await (await SharedPreferences.getInstance()).remove('token');
    } catch (e) {
      debugPrint('clear token failed: $e');
    }
  }

  // ---------- navigation ----------
  int tab = 0;
  int? selectedShopId;

  void goTab(int i) {
    tab = i;
    notifyListeners();
  }

  void openShop(int shopId) {
    selectedShopId = shopId;
    tab = 1;
    notifyListeners();
  }

  // ---------- ตะกร้า (สั่งได้ทีละร้าน) ----------
  Shop? cartShop;
  final Map<int, MenuItem> _cartItems = {};
  final Map<int, int> cartQty = {};
  String cartNote = '';

  int qtyOf(int menuItemId) => cartQty[menuItemId] ?? 0;
  int get cartCount => cartQty.values.fold(0, (a, b) => a + b);
  int get cartTotal => cartQty.entries.fold(0, (sum, e) => sum + _cartItems[e.key]!.price * e.value);
  List<(MenuItem, int)> get cartLines => [for (final e in cartQty.entries) (_cartItems[e.key]!, e.value)];
  bool isOtherShop(Shop shop) => cartShop != null && cartShop!.id != shop.id && cartQty.isNotEmpty;

  void setQty(Shop shop, MenuItem item, int qty) {
    if (isOtherShop(shop)) clearCart(notify: false);
    cartShop = shop;
    if (qty <= 0) {
      cartQty.remove(item.id);
      _cartItems.remove(item.id);
    } else {
      cartQty[item.id] = qty.clamp(1, 20);
      _cartItems[item.id] = item;
    }
    if (cartQty.isEmpty) cartShop = null;
    _saveCart();
    notifyListeners();
  }

  void setCartNote(String note) {
    cartNote = note;
    _saveCart();
  }

  void clearCart({bool notify = true, bool persist = true}) {
    cartShop = null;
    cartQty.clear();
    _cartItems.clear();
    cartNote = '';
    if (persist) _saveCart();
    if (notify) notifyListeners();
  }

  /// บันทึกตะกร้าลงฐานข้อมูลในเครื่อง (ไม่รอผล — บันทึกไม่ได้ก็ยังสั่งอาหารได้ปกติ)
  Future<void> _saveCart() => store
      .saveCart(cartShop == null
          ? null
          : SavedCart(shop: cartShop!.toJson(), items: [for (final (m, q) in cartLines) (m.toJson(), q)], note: cartNote))
      .catchError((Object e) => debugPrint('save cart failed: $e'));

  Future<void> _restoreCart() async {
    try {
      final saved = await store.loadCart();
      if (saved == null) return;
      cartShop = Shop.fromJson(saved.shop);
      for (final (json, qty) in saved.items) {
        final item = MenuItem.fromJson(json);
        _cartItems[item.id] = item;
        cartQty[item.id] = qty;
      }
      cartNote = saved.note;
    } catch (e) {
      debugPrint('restore cart failed: $e');
    }
  }

  /// "สั่งอีกครั้ง" จากประวัติ: ใส่เมนูที่ยังมีขายลงตะกร้า คืนจำนวนเมนูที่หมดแล้ว
  Future<int> reorder(Order order) async {
    final shop = await api.shop(order.shopId);
    clearCart(notify: false);
    var missing = 0;
    for (final line in order.items) {
      final item = shop.menu.where((m) => m.id == line.menuItemId && m.isAvailable).firstOrNull;
      if (item == null) {
        missing++;
      } else {
        cartShop = shop;
        cartQty[item.id] = line.qty;
        _cartItems[item.id] = item;
      }
    }
    cartNote = order.note;
    selectedShopId = shop.id;
    _saveCart();
    notifyListeners();
    return missing;
  }

  // ---------- ออเดอร์ (ออนไลน์ก่อน ถ้าไม่มีเน็ตใช้ข้อมูลล่าสุดในเครื่อง) ----------
  /// คืน (รายการออเดอร์, เป็นข้อมูลออฟไลน์หรือไม่)
  Future<(List<Order>, bool)> loadOrders({bool history = false}) async {
    try {
      final json = await api.ordersJson(history: history);
      await store.cacheOrders(json, history: history).catchError((Object e) => debugPrint('cache orders failed: $e'));
      return (json.map(Order.fromJson).toList(), false);
    } on ApiException catch (e) {
      if (e.status != 0) rethrow; // เซิร์ฟเวอร์ตอบ error จริง ไม่ใช่เน็ตหลุด
      final cached = await store.cachedOrders(history: history);
      if (cached == null) rethrow;
      return (cached.map(Order.fromJson).toList(), true);
    }
  }

  // ---------- เมนูโปรด ----------
  final Set<int> favoriteIds = {};

  Future<void> loadFavorites() async {
    final favs = await api.favorites();
    favoriteIds
      ..clear()
      ..addAll(favs.map((f) => f.id));
  }

  Future<void> toggleFavorite(int menuItemId) async {
    final fav = !favoriteIds.contains(menuItemId);
    fav ? favoriteIds.add(menuItemId) : favoriteIds.remove(menuItemId);
    notifyListeners();
    try {
      await api.setFavorite(menuItemId, fav);
    } catch (_) {
      fav ? favoriteIds.remove(menuItemId) : favoriteIds.add(menuItemId);
      notifyListeners();
      rethrow;
    }
  }
}
