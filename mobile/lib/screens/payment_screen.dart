import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// หน้าชำระเงิน: QR พร้อมเพย์ของร้าน (มียอดเงินในตัว) + แนบสลิป
class PaymentScreen extends StatefulWidget {
  final int orderId;
  const PaymentScreen({super.key, required this.orderId});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  PaymentInfo? _info;
  String? _error;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await context.read<AppState>().api.payment(widget.orderId);
      if (mounted) setState(() { _info = info; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _attachSlip() async {
    // ย่อรูปก่อนอัปโหลด (สลิปอ่านได้ชัดที่ ~1280px) — ไฟล์เล็ก ส่งเร็ว ประหยัดพื้นที่
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await context.read<AppState>().api.uploadSlip(widget.orderId, await file.readAsBytes());
      await _load();
      if (mounted) showMsg(context, 'แนบสลิปแล้ว รอร้านตรวจสอบ');
    } catch (e) {
      if (mounted) showMsg(context, e, error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _done() {
    context.read<AppState>().goTab(2);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.chevron_left, size: 28), onPressed: () => Navigator.pop(context)),
              const Text('ชำระเงิน', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(child: RefreshIndicator(color: AppColors.accent, onRefresh: _load, child: _body())),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return ListView(children: [EmptyState(icon: Icons.wifi_off, text: _error!, action: TextButton(onPressed: _load, child: const Text('ลองใหม่')))]);
    }
    final p = _info;
    if (p == null) return const Center(child: CircularProgressIndicator(color: AppColors.pink));
    final paid = p.status == 'paid';
    final waiting = p.status == 'slip_uploaded';

    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: cardDecoration(radius: 20),
        child: Column(children: [
          Text('${p.shopName} · คิว ${p.queueNo}', style: const TextStyle(color: AppColors.ink2, fontSize: 13)),
          const SizedBox(height: 4),
          Text(baht(p.amount), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.accent)),
          const SizedBox(height: 12),
          if (paid)
            const _StatusBanner(icon: Icons.check_circle, color: AppColors.green, text: 'ร้านยืนยันรับเงินแล้ว')
          else if (p.qrPayload != null) ...[
            // ภาพ QR ต้องพื้นขาวเสมอ แอปธนาคารถึงสแกนได้แม่น
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF113566), borderRadius: BorderRadius.circular(6)),
                  child: const Text('PromptPay พร้อมเพย์', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                const SizedBox(height: 8),
                QrImageView(data: p.qrPayload!, size: 220, backgroundColor: Colors.white),
              ]),
            ),
            const SizedBox(height: 8),
            if (p.promptpayMasked != null)
              Text('โอนเข้าพร้อมเพย์ ${p.promptpayMasked}', style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      if (!paid) ...[
        if (waiting)
          const _StatusBanner(icon: Icons.hourglass_top, color: Color(0xFFA86400), text: 'แนบสลิปแล้ว รอร้านตรวจสอบ')
        else if (p.status == 'rejected')
          _StatusBanner(icon: Icons.error_outline, color: AppColors.red, text: 'สลิปไม่ผ่าน: ${p.note ?? '-'}\nกรุณาแนบสลิปใหม่'),
        const SizedBox(height: 12),
        const Text('วิธีชำระเงิน', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('1. เปิดแอปธนาคาร แล้วสแกน QR ด้านบน (ยอดเงินใส่ให้แล้ว)\n'
            '2. โอนเสร็จแล้ว บันทึกภาพสลิป\n'
            '3. กด "แนบสลิป" แล้วเลือกรูปสลิป',
            style: TextStyle(fontSize: 13, color: AppColors.ink2, height: 1.6)),
        const SizedBox(height: 16),
        PinkButton(
          onPressed: _attachSlip,
          loading: _uploading,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.receipt_long, size: 20),
            const SizedBox(width: 8),
            Text(p.hasSlip ? 'แนบสลิปใหม่' : 'แนบสลิป'),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      TextButton(onPressed: _done, child: const Text('ไปหน้าคำสั่งซื้อ', style: TextStyle(color: AppColors.accent))),
    ]);
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _StatusBanner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ]),
      );
}
