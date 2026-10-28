import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// เสียงเตือนออเดอร์ใหม่: ดัง + สั่นซ้ำทุก 3 วินาที ตราบใดที่ยังมีออเดอร์รอร้านรับ
/// (หยุดเองเมื่อร้านกดรับหรือปฏิเสธครบทุกออเดอร์)
class OrderAlarm {
  static const _interval = Duration(seconds: 3);
  final AudioPlayer _player = AudioPlayer();
  Timer? _timer;

  OrderAlarm() {
    _player.setReleaseMode(ReleaseMode.stop);
    _player.setVolume(1.0);
  }

  bool get ringing => _timer != null;

  /// เรียกทุกครั้งที่โหลดออเดอร์ใหม่
  void update(int pendingCount) => pendingCount > 0 ? _start() : stop();

  void _start() {
    if (_timer != null) return;
    _ring();
    _timer = Timer.periodic(_interval, (_) => _ring());
  }

  Future<void> _ring() async {
    HapticFeedback.heavyImpact();
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/new_order.wav'));
    } catch (e) {
      debugPrint('alarm sound failed: $e'); // เช่น เบราว์เซอร์บล็อกเสียงจนกว่าผู้ใช้จะแตะหน้าจอ
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _player.stop();
  }

  void dispose() {
    stop();
    _player.dispose();
  }
}
