import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme.dart';
import 'orders_screen.dart';
import 'menu_screen.dart';
import 'reviews_screen.dart';
import 'shop_screen.dart';

class VendorShell extends StatelessWidget {
  const VendorShell({super.key});

  static const _tabs = [
    (Icons.receipt_long_outlined, 'ออเดอร์'),
    (Icons.restaurant_menu, 'เมนู'),
    (Icons.star_outline_rounded, 'รีวิว'),
    (Icons.storefront_outlined, 'ร้านของฉัน'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      // IndexedStack: หน้าออเดอร์ยัง poll/แจ้งเตือนต่อแม้สลับไปแท็บอื่น
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (state.pendingCount > 0)
            // แถบเตือนทุกแท็บ จนกว่าร้านจะรับ/ปฏิเสธออเดอร์ใหม่ครบ (เสียงดังซ้ำควบคู่กัน)
            Material(
              color: AppColors.red,
              child: InkWell(
                onTap: () => state.goTab(0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.notifications_active, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('มีออเดอร์ใหม่ ${state.pendingCount} รายการ รอร้านกดรับ',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                    if (state.tab != 0) const Text('ดูออเดอร์ ›', style: TextStyle(color: Colors.white)),
                  ]),
                ),
              ),
            ),
          Expanded(child: IndexedStack(index: state.tab, children: const [OrdersScreen(), MenuScreen(), ReviewsScreen(), ShopScreen()])),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border(bottom: BorderSide(color: AppColors.pink.withValues(alpha: 0.6), width: 3)),
            boxShadow: cardShadow,
          ),
          child: Row(children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => state.goTab(i),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: state.tab == i ? AppColors.pink : Colors.transparent),
                      child: Icon(_tabs[i].$1, size: 22, color: state.tab == i ? Colors.white : AppColors.ink2),
                    ),
                    Text(_tabs[i].$2,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: state.tab == i ? FontWeight.w600 : FontWeight.w400,
                          color: state.tab == i ? AppColors.accent : AppColors.ink2,
                        )),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
