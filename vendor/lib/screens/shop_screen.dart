import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  Shop? _shop;
  final _desc = TextEditingController();
  final _promptpay = TextEditingController();
  String _open = '07:30';
  String _close = '17:00';
  int _prepMin = 5;
  int _prepMax = 10;
  bool _isOpen = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _desc.dispose();
    _promptpay.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await context.read<AppState>().api.shop();
      if (!mounted) return;
      setState(() {
        _shop = s;
        _desc.text = s.description;
        _promptpay.text = s.promptpayId ?? '';
        _open = s.openTime;
        _close = s.closeTime;
        _prepMin = s.prepMin;
        _prepMax = s.prepMax;
        _isOpen = s.isOpen;
      });
    } catch (e) {
      if (mounted) showMsg(context, e, error: true);
    }
  }

  Future<void> _pickTime(bool isOpen) async {
    final cur = (isOpen ? _open : _close).split(':').map(int.parse).toList();
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur[0], minute: cur[1]),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => isOpen ? _open = v : _close = v);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final s = await context.read<AppState>().api.updateShop({
        'description': _desc.text.trim(), 'open_time': _open, 'close_time': _close,
        'prep_min': _prepMin, 'prep_max': _prepMax, 'is_open': _isOpen,
        'promptpay_id': _promptpay.text.trim(),
      });
      if (!mounted) return;
      setState(() => _shop = s);
      showMsg(context, 'บันทึกข้อมูลร้านแล้ว');
    } catch (e) {
      if (mounted) showMsg(context, e, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- โปรไฟล์ ----------
  bool _busyImage = false;

  Future<void> _changeShopImage() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('ถ่ายรูป'), onTap: () => Navigator.pop(c, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('เลือกจากคลังภาพ'), onTap: () => Navigator.pop(c, 'gallery')),
          if (_shop?.imageUrl != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.red),
              title: const Text('ลบรูปร้าน', style: TextStyle(color: AppColors.red)),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final api = context.read<AppState>().api;
    List<int>? bytes;
    if (choice != 'remove') {
      final file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 80);
      if (file == null) return;
      bytes = await file.readAsBytes();
    }
    setState(() => _busyImage = true);
    try {
      final s = bytes == null ? await api.deleteShopImage() : await api.uploadShopImage(bytes);
      if (mounted) setState(() => _shop = s);
      if (mounted) showMsg(context, bytes == null ? 'ลบรูปร้านแล้ว' : 'เปลี่ยนรูปร้านแล้ว');
    } catch (e) {
      if (mounted) showMsg(context, e, error: true);
    } finally {
      if (mounted) setState(() => _busyImage = false);
    }
  }

  Future<void> _editName() async {
    final state = context.read<AppState>();
    final ctrl = TextEditingController(text: state.user?.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ชื่อเจ้าของร้าน'),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 100, decoration: const InputDecoration(counterText: '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('บันทึก')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      state.setUser(await state.api.updateMe(name));
      if (mounted) showMsg(context, 'บันทึกชื่อแล้ว');
    } catch (e) {
      if (mounted) showMsg(context, e, error: true);
    }
  }

  Future<void> _changePassword() async {
    final cur = TextEditingController(), next = TextEditingController(), confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('เปลี่ยนรหัสผ่าน'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cur, obscureText: true, decoration: const InputDecoration(hintText: 'รหัสผ่านปัจจุบัน')),
          const SizedBox(height: 10),
          TextField(controller: next, obscureText: true, decoration: const InputDecoration(hintText: 'รหัสผ่านใหม่ (อย่างน้อย 4 ตัว)')),
          const SizedBox(height: 10),
          TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(hintText: 'ยืนยันรหัสผ่านใหม่')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('เปลี่ยนรหัสผ่าน')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (next.text != confirm.text) return showMsg(context, 'รหัสผ่านใหม่ทั้งสองช่องไม่ตรงกัน', error: true);
    try {
      await context.read<AppState>().api.changePassword(cur.text, next.text);
      if (mounted) showMsg(context, 'เปลี่ยนรหัสผ่านแล้ว');
    } catch (e) {
      if (mounted) showMsg(context, e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_shop == null) return const Center(child: CircularProgressIndicator(color: AppColors.pink));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      const Text('ร้านของฉัน', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      // โปรไฟล์: รูปร้าน + ชื่อเจ้าของ + รหัสผ่าน
      Container(
        padding: const EdgeInsets.all(14),
        decoration: cardDecoration(),
        child: Column(children: [
          Row(children: [
            GestureDetector(
              onTap: _busyImage ? null : _changeShopImage,
              child: Stack(children: [
                _busyImage
                    ? Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(color: AppColors.pinkSoft, borderRadius: BorderRadius.circular(16)),
                        child: const Center(child: CircularProgressIndicator(color: AppColors.pink, strokeWidth: 2)),
                      )
                    : FoodImage(width: 72, height: 72, icon: Icons.storefront, imageUrl: _shop!.imageUrl),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.photo_camera, size: 14, color: AppColors.accent),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_shop!.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                Text('${_shop!.category} · คิวขึ้นต้นด้วย ${_shop!.code}', style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
                const Text('แตะรูปเพื่อเปลี่ยนรูปร้าน', style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ]),
            ),
          ]),
          const Divider(color: AppColors.line, height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.person_outline, color: AppColors.ink2),
            title: Text(state.user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('ชื่อผู้ใช้ ${state.user?.username}'),
            trailing: const Icon(Icons.edit, size: 18, color: AppColors.accent),
            onTap: _editName,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.lock_outline, color: AppColors.ink2),
            title: const Text('เปลี่ยนรหัสผ่าน'),
            trailing: const Icon(Icons.chevron_right, color: AppColors.accent),
            onTap: _changePassword,
          ),
        ]),
      ),
      const SizedBox(height: 14),
      _section(Column(children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('เปิดรับออเดอร์', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(_isOpen ? 'ลูกค้าสั่งได้ในเวลาทำการ' : 'ร้านปิด ลูกค้าจะสั่งไม่ได้', style: const TextStyle(fontSize: 12)),
          value: _isOpen,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.green,
          onChanged: (v) => setState(() => _isOpen = v),
        ),
        const Divider(color: AppColors.line),
        Row(children: [
          Expanded(child: _timeBox('เวลาเปิด', _open, () => _pickTime(true))),
          const SizedBox(width: 10),
          Expanded(child: _timeBox('เวลาปิด', _close, () => _pickTime(false))),
        ]),
        const SizedBox(height: 12),
        _stepper('เวลารอขั้นต่ำ', _prepMin, (v) => setState(() { _prepMin = v; if (_prepMax < v) _prepMax = v; })),
        _stepper('เวลารอสูงสุด', _prepMax, (v) => setState(() => _prepMax = v < _prepMin ? _prepMin : v)),
      ])),
      const SizedBox(height: 14),
      _section(TextField(
        controller: _desc,
        maxLines: 2,
        maxLength: 300,
        decoration: const InputDecoration(labelText: 'คำอธิบายร้าน (แสดงในแอปนักศึกษา)', counterText: ''),
      )),
      const SizedBox(height: 14),
      _section(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.qr_code_2, color: AppColors.accent),
          SizedBox(width: 8),
          Text('รับโอนพร้อมเพย์', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        const Text('ใส่เบอร์มือถือหรือเลขบัตรประชาชนที่ผูกพร้อมเพย์ ลูกค้าจะเห็น QR พร้อมยอดเงินแล้วแนบสลิปมาให้ตรวจ\n'
            'เว้นว่าง = รับเฉพาะจ่ายที่ร้าน',
            style: TextStyle(fontSize: 12, color: AppColors.ink2)),
        const SizedBox(height: 10),
        TextField(
          controller: _promptpay,
          keyboardType: TextInputType.number,
          maxLength: 15,
          decoration: const InputDecoration(hintText: 'เช่น 0812345678', counterText: '', prefixIcon: Icon(Icons.phone_iphone, color: AppColors.ink2)),
        ),
      ])),
      const SizedBox(height: 18),
      PinkButton(onPressed: _save, loading: _saving, child: const Text('บันทึก')),
      const SizedBox(height: 6),
      const Text('ชื่อร้าน หมวดหมู่ และรหัสคิว แก้ไขได้โดยผู้ดูแลศูนย์อาหาร',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 24),
      SizedBox(
        height: 46,
        child: OutlinedButton(
          onPressed: state.logout,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.red,
            side: const BorderSide(color: AppColors.red),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('ออกจากระบบ', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }

  Widget _section(Widget child) => Container(padding: const EdgeInsets.all(14), decoration: cardDecoration(), child: child);

  Widget _timeBox(String label, String value, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: AppColors.pinkSoft, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
            Text('$value น.', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _stepper(String label, int value, ValueChanged<int> onChanged) => Row(children: [
        Expanded(child: Text(label)),
        QtyButton(icon: Icons.remove, onTap: value > 0 ? () => onChanged(value - 1) : null),
        SizedBox(width: 64, child: Text('$value นาที', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
        QtyButton(icon: Icons.add, filled: true, onTap: value < 120 ? () => onChanged(value + 1) : null),
      ]);
}
