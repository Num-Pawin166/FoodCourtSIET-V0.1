import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// ตะกร้าที่บันทึกไว้ในเครื่อง (ร้าน + เมนู + จำนวน + หมายเหตุ)
class SavedCart {
  final Map<String, dynamic> shop;
  final List<(Map<String, dynamic>, int)> items; // (เมนู, จำนวน) ตามลำดับที่ใส่
  final String note;
  SavedCart({required this.shop, required this.items, this.note = ''});
}

/// ข้อความแชท AI ที่บันทึกไว้
class SavedChat {
  final bool fromUser;
  final String text;
  final List<Map<String, dynamic>> picks;
  SavedChat(this.fromUser, this.text, [this.picks = const []]);
}

/// ฐานข้อมูลในเครื่อง (Local Database)
/// - ตะกร้า: ปิดแอปแล้วเปิดใหม่ ตะกร้ายังอยู่
/// - ออเดอร์ล่าสุด: ไม่มีเน็ตก็ยังเห็นเลขคิวและประวัติ
/// - ประวัติแชท AI
/// ข้อมูลทั้งหมดเป็นของผู้ใช้ที่ล็อกอินอยู่ → ล้างทิ้งเมื่อออกจากระบบ
abstract class LocalStore {
  /// Android/iOS ใช้ SQLite (sqflite) ส่วนเว็บเก็บในหน่วยความจำ
  factory LocalStore.platformDefault() => kIsWeb ? MemoryLocalStore() : SqliteLocalStore(databaseFactory, 'foodcourt.db');

  Future<SavedCart?> loadCart();
  Future<void> saveCart(SavedCart? cart);

  Future<List<Map<String, dynamic>>?> cachedOrders({required bool history});
  Future<void> cacheOrders(List<Map<String, dynamic>> orders, {required bool history});

  Future<List<SavedChat>> chatHistory();
  Future<void> addChat(SavedChat msg);
  Future<void> clearChat();

  /// ล้างข้อมูลทั้งหมด (ตอนออกจากระบบ)
  Future<void> clearAll();
}

class SqliteLocalStore implements LocalStore {
  static const _version = 1;
  final DatabaseFactory factory;
  final String path;
  Future<Database>? _db;

  SqliteLocalStore(this.factory, this.path);

  Future<Database> get db => _db ??= factory.openDatabase(path,
      options: OpenDatabaseOptions(version: _version, onCreate: (db, _) => _createSchema(db)));

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch()
      ..execute('''CREATE TABLE cart_items (
          menu_item_id INTEGER PRIMARY KEY,
          item_json    TEXT NOT NULL,
          qty          INTEGER NOT NULL CHECK (qty BETWEEN 1 AND 20),
          position     INTEGER NOT NULL)''')
      // ค่าเดี่ยวๆ เช่น ร้านของตะกร้า, หมายเหตุ
      ..execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
      ..execute('''CREATE TABLE order_cache (
          order_id INTEGER NOT NULL,
          scope    TEXT NOT NULL CHECK (scope IN ('active','history')),
          position INTEGER NOT NULL,
          data     TEXT NOT NULL,
          PRIMARY KEY (scope, order_id))''')
      ..execute('''CREATE TABLE chat_messages (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          from_user  INTEGER NOT NULL,
          text       TEXT NOT NULL,
          picks_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL)''');
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    if (_db != null) await (await db).close();
    _db = null;
  }

  // ---------- ตะกร้า ----------
  @override
  Future<SavedCart?> loadCart() async {
    final d = await db;
    final shop = await d.query('kv', where: 'key = ?', whereArgs: ['cart_shop']);
    if (shop.isEmpty) return null;
    final note = await d.query('kv', where: 'key = ?', whereArgs: ['cart_note']);
    final rows = await d.query('cart_items', orderBy: 'position');
    if (rows.isEmpty) return null;
    return SavedCart(
      shop: jsonDecode(shop.first['value'] as String),
      items: [for (final r in rows) (jsonDecode(r['item_json'] as String) as Map<String, dynamic>, r['qty'] as int)],
      note: note.isEmpty ? '' : note.first['value'] as String,
    );
  }

  @override
  Future<void> saveCart(SavedCart? cart) async {
    final d = await db;
    await d.transaction((tx) async {
      await tx.delete('cart_items');
      await tx.delete('kv', where: "key IN ('cart_shop','cart_note')");
      if (cart == null || cart.items.isEmpty) return;
      await tx.insert('kv', {'key': 'cart_shop', 'value': jsonEncode(cart.shop)});
      await tx.insert('kv', {'key': 'cart_note', 'value': cart.note});
      for (var i = 0; i < cart.items.length; i++) {
        final (item, qty) = cart.items[i];
        await tx.insert('cart_items', {'menu_item_id': item['id'], 'item_json': jsonEncode(item), 'qty': qty, 'position': i});
      }
    });
  }

  // ---------- ออเดอร์ (แคชไว้ดูตอนออฟไลน์) ----------
  @override
  Future<List<Map<String, dynamic>>?> cachedOrders({required bool history}) async {
    final d = await db;
    final scope = history ? 'history' : 'active';
    final saved = await d.query('kv', where: 'key = ?', whereArgs: ['orders_$scope']);
    if (saved.isEmpty) return null; // ยังไม่เคยโหลดสำเร็จ
    final rows = await d.query('order_cache', where: 'scope = ?', whereArgs: [scope], orderBy: 'position');
    return [for (final r in rows) jsonDecode(r['data'] as String) as Map<String, dynamic>];
  }

  @override
  Future<void> cacheOrders(List<Map<String, dynamic>> orders, {required bool history}) async {
    final d = await db;
    final scope = history ? 'history' : 'active';
    await d.transaction((tx) async {
      await tx.delete('order_cache', where: 'scope = ?', whereArgs: [scope]);
      for (var i = 0; i < orders.length; i++) {
        await tx.insert('order_cache', {'order_id': orders[i]['id'], 'scope': scope, 'position': i, 'data': jsonEncode(orders[i])});
      }
      await tx.insert('kv', {'key': 'orders_$scope', 'value': DateTime.now().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  // ---------- แชท AI ----------
  @override
  Future<List<SavedChat>> chatHistory() async {
    final rows = await (await db).query('chat_messages', orderBy: 'id');
    return [
      for (final r in rows)
        SavedChat(r['from_user'] == 1, r['text'] as String, (jsonDecode(r['picks_json'] as String) as List).cast<Map<String, dynamic>>()),
    ];
  }

  @override
  Future<void> addChat(SavedChat msg) async {
    await (await db).insert('chat_messages', {
      'from_user': msg.fromUser ? 1 : 0,
      'text': msg.text,
      'picks_json': jsonEncode(msg.picks),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> clearChat() async => (await db).delete('chat_messages');

  @override
  Future<void> clearAll() async {
    final d = await db;
    final batch = d.batch();
    for (final t in ['cart_items', 'kv', 'order_cache', 'chat_messages']) {
      batch.delete(t);
    }
    await batch.commit(noResult: true);
  }
}

/// ใช้บนเว็บ (sqflite ไม่รองรับเว็บ) — พฤติกรรมเหมือนกันแต่หายเมื่อปิดแท็บ
class MemoryLocalStore implements LocalStore {
  SavedCart? _cart;
  final Map<bool, List<Map<String, dynamic>>> _orders = {};
  final List<SavedChat> _chat = [];

  @override
  Future<SavedCart?> loadCart() async => _cart;
  @override
  Future<void> saveCart(SavedCart? cart) async => _cart = cart == null || cart.items.isEmpty ? null : cart;
  @override
  Future<List<Map<String, dynamic>>?> cachedOrders({required bool history}) async => _orders[history];
  @override
  Future<void> cacheOrders(List<Map<String, dynamic>> orders, {required bool history}) async => _orders[history] = List.of(orders);
  @override
  Future<List<SavedChat>> chatHistory() async => List.of(_chat);
  @override
  Future<void> addChat(SavedChat msg) async => _chat.add(msg);
  @override
  Future<void> clearChat() async => _chat.clear();
  @override
  Future<void> clearAll() async {
    _cart = null;
    _orders.clear();
    _chat.clear();
  }
}
