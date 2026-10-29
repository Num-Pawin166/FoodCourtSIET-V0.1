import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodcourt_siet/screens/ai_chat_screen.dart';
import 'package:foodcourt_siet/screens/cart_screen.dart';
import 'package:foodcourt_siet/screens/home_screen.dart';
import 'package:foodcourt_siet/screens/login_screen.dart';
import 'package:foodcourt_siet/screens/main_shell.dart';
import 'package:foodcourt_siet/screens/orders_screen.dart';
import 'package:foodcourt_siet/screens/profile_screen.dart';
import 'package:foodcourt_siet/screens/shop_menu_screen.dart';
import 'package:foodcourt_siet/app_state.dart';
import 'package:foodcourt_siet/local_db.dart';
import 'package:foodcourt_siet/models.dart';
import 'package:foodcourt_siet/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
  });

  group('หน้า Login', () {
    testWidgets('แสดงโลโก้ ช่องกรอก และแจ้งว่ายังไม่ตั้งค่า Google', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(fakeState(backend), const LoginScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(FoodCourtLogo), findsOneWidget);
      expect(find.text('ยังไม่ได้ตั้งค่า Google Sign-In ที่เซิร์ฟเวอร์'), findsOneWidget);
      expect(find.textContaining('@kmitl.ac.th'), findsOneWidget);
    });

    testWidgets('กด Login โดยไม่กรอก → เตือนให้กรอกให้ครบ', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(fakeState(backend), const LoginScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Login'));
      await tester.pump();
      expect(find.text('กรุณากรอกข้อมูลให้ครบ'), findsOneWidget);
    });

    testWidgets('รหัสผ่านผิด → แสดงข้อความจากเซิร์ฟเวอร์', (tester) async {
      usePhoneScreen(tester);
      final state = fakeState(backend);
      await tester.pumpWidget(wrap(state, const LoginScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '65010001');
      await tester.enterText(find.byType(TextField).at(1), 'wrong');
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.text('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
      expect(state.user, isNull);
    });

    testWidgets('ปุ่มรูปตาสลับการซ่อนรหัสผ่าน', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(fakeState(backend), const LoginScreen()));
      await tester.pumpAndSettle();
      TextField password() => tester.widget<TextField>(find.byType(TextField).at(1));
      expect(password().obscureText, isTrue);
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();
      expect(password().obscureText, isFalse);
    });

    testWidgets('ล็อกอินสำเร็จด้วยการกด Enter', (tester) async {
      usePhoneScreen(tester);
      final state = fakeState(backend);
      await tester.pumpWidget(wrap(state, const LoginScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '65010001');
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(state.user?.name, 'สมชาย ใจดี');
    });
  });

  group('หน้า Home', () {
    testWidgets('แสดงร้าน หมวดหมู่ คิว และสถานะเปิด', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(await signedInState(backend), const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('ร้านข้าวขาหมูป้าแดง'), findsOneWidget);
      expect(find.text('ก๋วยเตี๋ยวลุงชัย'), findsOneWidget);
      expect(find.text(' คิว 2'), findsOneWidget);
      expect(find.text('เปิดอยู่'), findsNWidgets(2));
      expect(find.text('ทั้งหมด'), findsOneWidget);
      expect(find.text('ถาม AI ช่วยเลือกเมนู'), findsOneWidget);
    });

    testWidgets('กรองตามหมวด', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(await signedInState(backend), const HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'เส้น'));
      await tester.pumpAndSettle();
      expect(find.text('ร้านข้าวขาหมูป้าแดง'), findsNothing);
      expect(find.text('ก๋วยเตี๋ยวลุงชัย'), findsOneWidget);
    });

    testWidgets('ค้นหาชื่อเมนู (หน่วงเวลาก่อนค้น) และกรณีไม่พบ', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(await signedInState(backend), const HomeScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ก๋วยเตี๋ยว');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('ร้านข้าวขาหมูป้าแดง'), findsNothing);
      await tester.enterText(find.byType(TextField), 'พิซซ่า');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('ไม่พบร้านหรือเมนูที่ค้นหา'), findsOneWidget);
    });

    testWidgets('เน็ตหลุด → แสดง error และกดลองใหม่ได้', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      backend.offline = true;
      await tester.pumpWidget(wrap(state, const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      backend.offline = false;
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.text('ร้านข้าวขาหมูป้าแดง'), findsOneWidget);
    });

    testWidgets('กดการ์ดร้าน → ไปแท็บเมนูของร้านนั้น', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ก๋วยเตี๋ยวลุงชัย'));
      expect((state.tab, state.selectedShopId), (1, 2));
    });
  });

  group('หน้าเมนูร้าน', () {
    testWidgets('ยังไม่เลือกร้าน → ชวนไปหน้า Home', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: null)));
      expect(find.textContaining('ยังไม่ได้เลือกร้าน'), findsOneWidget);
      await tester.tap(find.text('ไปหน้า Home'));
      expect(state.tab, 0);
    });

    testWidgets('แสดงเมนู ราคา เมนูหมด และเพิ่มลงตะกร้า', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      expect(find.text('ข้าวขาหมู'), findsOneWidget);
      expect(find.text('฿50'), findsOneWidget);
      expect(find.text('หมดแล้ว'), findsOneWidget);
      expect(find.text('7.30 - 17:00'.replaceFirst('7.30', '07:30')), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
      expect(state.qtyOf(1), 2);
      expect(find.text('เพิ่มลงตะกร้า'), findsOneWidget);
      expect(find.text('฿100'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pump();
      expect(state.qtyOf(1), 1);
    });

    testWidgets('ปุ่ม + ของเมนูที่หมดกดไม่ได้', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add).at(2));
      await tester.pump();
      expect(state.qtyOf(3), 0);
    });

    testWidgets('กดหัวใจเพิ่มเมนูโปรด', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget); // เมนู 1 เป็นเมนูโปรดอยู่แล้ว
      await tester.tap(find.byIcon(Icons.favorite_border).first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsNWidgets(2));
      expect(backend.favorites, contains(2));
    });

    testWidgets('ตะกร้ามีร้านอื่นอยู่ → ถามก่อนล้าง (กดยกเลิก = ตะกร้าเดิมอยู่)', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      final other = Shop.fromJson({...backend.shop(2), 'menu': backend.menuOf(2)});
      state.setQty(other, other.menu.first, 1);
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      expect(find.text('เริ่มตะกร้าใหม่?'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(state.cartShop!.id, 2);

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ล้างตะกร้า'));
      await tester.pumpAndSettle();
      expect(state.cartShop!.id, 1);
    });

    testWidgets('ปุ่มย้อนกลับไปหน้า Home', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      state.goTab(1);
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_left));
      expect(state.tab, 0);
    });

    testWidgets('โหลดร้านไม่ได้ → error', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      backend.offline = true;
      await tester.pumpWidget(wrap(state, const ShopMenuScreen(shopId: 1)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });
  });

  group('หน้าตะกร้า', () {
    Future<AppState> openCart(WidgetTester tester, {bool promptpay = true}) async {
      backend.promptpay = promptpay;
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      final shop = Shop.fromJson({...backend.shop(1), 'menu': backend.menuOf(1)});
      state.setQty(shop, shop.menu[0], 2);
      await tester.pumpWidget(wrap(state, const CartScreen()));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('สรุปรายการ ช่วงเวลา และยอดรวม', (tester) async {
      await openCart(tester);
      expect(find.text('2×'), findsOneWidget);
      expect(find.text('11:15'), findsOneWidget);
      expect(find.text('11:15 น.'), findsOneWidget); // เลือกช่วงแรกให้อัตโนมัติ
      expect(find.text('ยืนยันคำสั่งซื้อ  ฿100'), findsOneWidget);
      expect(find.text('สแกน QR แล้วแนบสลิป'), findsOneWidget);
    });

    testWidgets('เปลี่ยนเวลา / จำนวน / วิธีจ่าย / หมายเหตุ', (tester) async {
      final state = await openCart(tester);
      await tester.tap(find.text('11:45'));
      await tester.pump();
      expect(find.text('11:45 น.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
      expect(find.text('3×'), findsOneWidget);

      await tester.tap(find.text('จ่ายที่ร้าน'));
      await tester.pump();
      expect(find.text('จ่ายที่ร้าน'), findsNWidgets(2)); // ตัวเลือก + บรรทัดสรุป

      await tester.enterText(find.byType(TextField), 'แยกน้ำซุป');
      expect(state.cartNote, 'แยกน้ำซุป');
    });

    testWidgets('ร้านที่ไม่รับพร้อมเพย์ → บังคับจ่ายที่ร้าน', (tester) async {
      await openCart(tester, promptpay: false);
      expect(find.text('ร้านนี้ยังไม่รับโอน'), findsOneWidget);
      await tester.tap(find.text('โอนพร้อมเพย์'));
      await tester.pump();
      expect(find.text('จ่ายที่ร้าน'), findsNWidgets(2));
    });

    testWidgets('ลดจนหมด → ตะกร้าว่าง', (tester) async {
      await openCart(tester);
      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pump();
      expect(find.text('ตะกร้าว่าง'), findsOneWidget);
    });
  });

  group('หน้าคำสั่งซื้อ', () {
    testWidgets('ยังไม่มีออเดอร์ / สลับไปดูประวัติ', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(wrap(await signedInState(backend), const OrdersScreen()));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีออเดอร์ที่กำลังดำเนินการ'), findsOneWidget);
      await tester.tap(find.text('ประวัติ'));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีประวัติการสั่งซื้อ'), findsOneWidget);
    });

    testWidgets('ออเดอร์ที่กำลังทำ: เลขคิว ไทม์ไลน์ ปุ่มชำระเงิน และยกเลิก', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await state.api.createOrder(shopId: 1, items: {1: 2}, pickupTime: '11:15', paymentMethod: 'promptpay');
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      expect(find.text('A - 001'), findsOneWidget);
      expect(find.text('11:15 น.'), findsOneWidget);
      expect(find.text('1 ออเดอร์'), findsOneWidget);
      expect(find.text('รอร้านยืนยันออเดอร์...'), findsOneWidget);
      expect(find.text('รอโอนเงิน'), findsOneWidget);
      expect(find.text('ชำระเงิน'), findsOneWidget);

      await tester.tap(find.text('ยกเลิกออเดอร์'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ไม่ใช่'));
      await tester.pumpAndSettle();
      expect(backend.orders.single['status'], 'pending');

      await tester.tap(find.text('ยกเลิกออเดอร์'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'ยกเลิกออเดอร์'));
      await tester.pumpAndSettle();
      expect(backend.orders.single['status'], 'cancelled');
      expect(find.text('ยังไม่มีออเดอร์ที่กำลังดำเนินการ'), findsOneWidget);
    });

    testWidgets('อาหารพร้อม: ข้อความเปลี่ยนเป็นสีเขียว และไทม์ไลน์ครบ', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await state.api.createOrder(shopId: 1, items: {1: 1}, pickupTime: '11:15');
      backend.orders.single.addAll({
        'status': 'ready', 'accepted_at': '2026-10-20T04:01:00Z', 'cooking_at': '2026-10-20T04:02:00Z', 'ready_at': '2026-10-20T04:09:00Z',
        'payment_status': 'paid',
      });
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      expect(find.text('อาหารพร้อมแล้ว! แสดงหมายเลขนี้ที่ร้าน'), findsOneWidget);
      expect(find.textContaining('เริ่ม '), findsOneWidget);
      expect(find.text('ชำระเงินแล้ว'), findsOneWidget);
      expect(find.text('ยกเลิกออเดอร์'), findsNothing);
    });

    testWidgets('สลิปถูกปฏิเสธ → แสดงเหตุผล', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await state.api.createOrder(shopId: 1, items: {1: 1}, pickupTime: '11:15', paymentMethod: 'promptpay');
      backend.orders.single.addAll({'payment_status': 'rejected', 'payment_note': 'ยอดไม่ตรง'});
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      expect(find.text('สลิปไม่ผ่าน: ยอดไม่ตรง'), findsOneWidget);
    });

    testWidgets('ประวัติ: แสดงออเดอร์ที่ยกเลิก และกดสั่งอีกครั้ง', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await state.api.createOrder(shopId: 1, items: {1: 1, 3: 1}, pickupTime: '11:15');
      backend.orders.single.addAll({'status': 'cancelled', 'cancel_reason': 'ของหมด'});
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ประวัติ'));
      await tester.pumpAndSettle();
      expect(find.text('ยกเลิก: ของหมด'), findsOneWidget);
      expect(find.textContaining('ข้าวขาหมูx1'), findsOneWidget);
      await tester.tap(find.text('สั่งอีกครั้ง'));
      await tester.pumpAndSettle();
      expect(find.byType(CartScreen), findsOneWidget);
      expect(find.text('มี 1 เมนูที่หมดแล้ว ถูกตัดออกจากตะกร้า'), findsOneWidget);
      expect(state.qtyOf(1), 1);
    });

    testWidgets('ออฟไลน์ → แสดงแถบ "ออฟไลน์" พร้อมข้อมูลล่าสุดในเครื่อง', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend, store: MemoryLocalStore());
      await state.api.createOrder(shopId: 1, items: {1: 1}, pickupTime: '11:15');
      await state.loadOrders(); // เคยโหลดสำเร็จ → มีแคช
      backend.offline = true;
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('ออฟไลน์'), findsOneWidget);
      expect(find.text('A - 001'), findsOneWidget);
    });

    testWidgets('อัปเดตสถานะอัตโนมัติทุก 5 วินาที', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await state.api.createOrder(shopId: 1, items: {1: 1}, pickupTime: '11:15');
      await tester.pumpWidget(wrap(state, const OrdersScreen()));
      await tester.pumpAndSettle();
      backend.orders.single['accepted_at'] = '2026-10-20T04:01:00Z';
      backend.orders.single['status'] = 'accepted';
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('รอร้านยืนยันออเดอร์...'), findsNothing);
      expect(find.text('ยกเลิกออเดอร์'), findsNothing);
    });
  });

  group('หน้าบัญชีของฉัน', () {
    testWidgets('ข้อมูลผู้ใช้ สถิติ เมนูโปรด และออกจากระบบ', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await state.api.createOrder(shopId: 1, items: {1: 2}, pickupTime: '11:15');
      await tester.pumpWidget(wrap(state, const ProfileScreen()));
      await tester.pumpAndSettle();
      expect(find.text('สมชาย ใจดี'), findsOneWidget);
      expect(find.text('รหัสนักศึกษา 65010001'), findsOneWidget);
      expect(find.text('฿100'), findsOneWidget);
      expect(find.text('ข้าวขาหมู'), findsOneWidget);

      await tester.tap(find.text('ข้าวขาหมู'));
      expect((state.tab, state.selectedShopId), (1, 1));

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();
      expect(find.text('กดรูปหัวใจที่เมนูเพื่อเก็บไว้เป็นเมนูโปรด'), findsOneWidget);

      await tester.tap(find.text('ออกจากระบบ'));
      await tester.pump();
      expect(state.user, isNull);
    });
  });

  group('ผู้ช่วย AI', () {
    testWidgets('ส่งข้อความ → ได้คำตอบพร้อมการ์ดเมนู → กดไปที่ร้าน', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, Builder(builder: (c) => TextButton(
            onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const AiChatScreen())),
            child: const Text('open'),
          ))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('สวัสดี!'), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(3));

      await tester.enterText(find.byType(TextField), 'งบ 50');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.text('งบ 50'), findsOneWidget);
      expect(find.text('ได้เลย! สำหรับ "งบ 50" ลองเมนูนี้'), findsOneWidget);
      expect(find.text('ข้าวมันไก่ทอด'), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);

      // คำถามถัดไปส่งประวัติแชทไปด้วย (ไม่รวมข้อความทักทาย)
      await tester.tap(find.byIcon(Icons.send_rounded)); // ช่องว่าง → ไม่ส่ง
      await tester.pump();
      expect(backend.requests.where((r) => r.url.path.endsWith('/ai/chat')), hasLength(1));

      await tester.tap(find.text('ไปที่ร้าน ›'));
      await tester.pumpAndSettle();
      expect((state.tab, state.selectedShopId), (1, 1));
      expect(find.byType(AiChatScreen), findsNothing);
    });

    testWidgets('แชทถูกบันทึกในเครื่อง เปิดใหม่ยังอยู่ และล้างได้', (tester) async {
      usePhoneScreen(tester);
      final store = MemoryLocalStore();
      final state = await signedInState(backend, store: store);
      await tester.pumpWidget(wrap(state, const AiChatScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();
      expect(await store.chatHistory(), hasLength(2));

      await tester.pumpWidget(wrap(state, const SizedBox()));
      await tester.pumpWidget(wrap(state, const AiChatScreen()));
      await tester.pumpAndSettle();
      expect(find.text('ข้าวมันไก่ทอด'), findsOneWidget);

      await tester.tap(find.byTooltip('ล้างประวัติแชท'));
      await tester.pumpAndSettle();
      expect(find.text('ข้าวมันไก่ทอด'), findsNothing);
      expect(await store.chatHistory(), isEmpty);
    });

    testWidgets('AI ตอบไม่ได้ → แสดงข้อความขอโทษ', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const AiChatScreen()));
      await tester.pumpAndSettle();
      backend.failStatus = 429;
      await tester.enterText(find.byType(TextField), 'หิว');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(find.textContaining('ขอโทษนะ ตอนนี้ตอบไม่ได้'), findsOneWidget);
    });
  });

  group('แถบเมนูล่าง (MainShell)', () {
    testWidgets('สลับแท็บ 4 หน้า และ badge จำนวนในตะกร้า', (tester) async {
      usePhoneScreen(tester);
      final state = await signedInState(backend);
      await tester.pumpWidget(wrap(state, const MainShell()));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsOneWidget);

      await tester.tap(find.text('User'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      final shop = Shop.fromJson({...backend.shop(1), 'menu': backend.menuOf(1)});
      state.setQty(shop, shop.menu.first, 3);
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(find.byType(ShopMenuScreen), findsOneWidget);
      expect(find.text('3'), findsWidgets);
    });
  });
}
