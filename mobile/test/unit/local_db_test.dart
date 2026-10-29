import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Unit test ของฐานข้อมูลในเครื่อง: รัน SQLite จริง (ผ่าน FFI) บนฐานข้อมูลในหน่วยความจำ
void main() {
  sqfliteFfiInit();
  late SqliteLocalStore store;

  setUp(() => store = SqliteLocalStore(databaseFactoryFfi, inMemoryDatabasePath));
  tearDown(() => store.close());

  final shop = {'id': 1, 'name': 'ร้าน A'};
  Map<String, dynamic> item(int id, int price) => {'id': id, 'shop_id': 1, 'name': 'เมนู $id', 'price': price};

  group('ตะกร้า', () {
    test('ยังไม่มีตะกร้า → null', () async {
      expect(await store.loadCart(), isNull);
    });

    test('บันทึกแล้วโหลดกลับได้ครบ เรียงตามลำดับที่ใส่', () async {
      await store.saveCart(SavedCart(shop: shop, items: [(item(3, 55), 1), (item(1, 50), 2)], note: 'ไม่ใส่ผัก'));
      final c = (await store.loadCart())!;
      expect(c.shop['name'], 'ร้าน A');
      expect(c.items.map((e) => (e.$1['id'], e.$2)), [(3, 1), (1, 2)]);
      expect(c.note, 'ไม่ใส่ผัก');
    });

    test('บันทึกทับของเดิม และบันทึก null = ล้างตะกร้า', () async {
      await store.saveCart(SavedCart(shop: shop, items: [(item(1, 50), 1), (item(2, 45), 1)]));
      await store.saveCart(SavedCart(shop: shop, items: [(item(2, 45), 3)]));
      expect((await store.loadCart())!.items.single.$2, 3);
      await store.saveCart(null);
      expect(await store.loadCart(), isNull);
    });

    test('ตะกร้าว่างไม่ถูกบันทึก', () async {
      await store.saveCart(SavedCart(shop: shop, items: []));
      expect(await store.loadCart(), isNull);
    });

    test('ฐานข้อมูลบังคับจำนวน 1-20 (CHECK constraint)', () async {
      expect(() => store.saveCart(SavedCart(shop: shop, items: [(item(1, 50), 21)])), throwsA(isA<DatabaseException>()));
      expect(await store.loadCart(), isNull); // transaction ถูก rollback ทั้งหมด
    });
  });

  group('แคชออเดอร์', () {
    test('ยังไม่เคยแคช → null (ต่างจากแคชแล้วแต่ว่าง)', () async {
      expect(await store.cachedOrders(history: false), isNull);
      await store.cacheOrders([], history: false);
      expect(await store.cachedOrders(history: false), isEmpty);
    });

    test('แยก active / history และแทนที่ของเดิมทั้งชุด', () async {
      await store.cacheOrders([{'id': 1, 'queue_no': 'A-001'}, {'id': 2, 'queue_no': 'A-002'}], history: false);
      await store.cacheOrders([{'id': 9, 'queue_no': 'B-009'}], history: true);
      expect((await store.cachedOrders(history: false))!.map((o) => o['id']), [1, 2]);
      await store.cacheOrders([{'id': 2, 'queue_no': 'A-002'}], history: false);
      expect((await store.cachedOrders(history: false))!.map((o) => o['id']), [2]);
      expect((await store.cachedOrders(history: true))!.single['queue_no'], 'B-009');
    });
  });

  group('แชท AI', () {
    test('บันทึกเรียงตามเวลา พร้อมเมนูที่ AI แนะนำ แล้วล้างได้', () async {
      await store.addChat(SavedChat(true, 'งบ 50'));
      await store.addChat(SavedChat(false, 'ลองข้าวมันไก่', [{'menu_item_id': 2, 'name': 'ข้าวมันไก่ทอด'}]));
      final chat = await store.chatHistory();
      expect(chat.map((m) => m.fromUser), [true, false]);
      expect(chat.last.picks.single['name'], 'ข้าวมันไก่ทอด');
      await store.clearChat();
      expect(await store.chatHistory(), isEmpty);
    });
  });

  test('clearAll ล้างทุกตาราง (ตอนออกจากระบบ)', () async {
    await store.saveCart(SavedCart(shop: shop, items: [(item(1, 50), 1)]));
    await store.cacheOrders([{'id': 1}], history: false);
    await store.addChat(SavedChat(true, 'hi'));
    await store.clearAll();
    expect(await store.loadCart(), isNull);
    expect(await store.cachedOrders(history: false), isNull);
    expect(await store.chatHistory(), isEmpty);
  });

  test('ข้อมูลยังอยู่หลังปิดแล้วเปิดฐานข้อมูลใหม่ (ไฟล์จริง)', () async {
    final path = '${(await databaseFactoryFfi.getDatabasesPath())}/foodcourt_test_${DateTime.now().microsecondsSinceEpoch}.db';
    final a = SqliteLocalStore(databaseFactoryFfi, path);
    await a.saveCart(SavedCart(shop: shop, items: [(item(1, 50), 2)]));
    await a.close();
    final b = SqliteLocalStore(databaseFactoryFfi, path);
    expect((await b.loadCart())!.items.single.$2, 2);
    await b.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });

  group('MemoryLocalStore (เว็บ) ทำงานเหมือนกัน', () {
    test('ตะกร้า / ออเดอร์ / แชท / ล้างทั้งหมด', () async {
      final m = MemoryLocalStore();
      await m.saveCart(SavedCart(shop: shop, items: [(item(1, 50), 1)]));
      expect((await m.loadCart())!.items.length, 1);
      await m.saveCart(SavedCart(shop: shop, items: []));
      expect(await m.loadCart(), isNull);
      await m.cacheOrders([{'id': 1}], history: true);
      expect(await m.cachedOrders(history: true), hasLength(1));
      expect(await m.cachedOrders(history: false), isNull);
      await m.addChat(SavedChat(true, 'hi'));
      expect(await m.chatHistory(), hasLength(1));
      await m.clearChat();
      expect(await m.chatHistory(), isEmpty);
      await m.addChat(SavedChat(true, 'hi'));
      await m.saveCart(SavedCart(shop: shop, items: [(item(1, 50), 1)]));
      await m.clearAll();
      expect(await m.loadCart(), isNull);
      expect(await m.chatHistory(), isEmpty);
      expect(await m.cachedOrders(history: true), isNull);
    });
  });
}
