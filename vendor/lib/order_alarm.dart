import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// เสียงที่ใช้เตือน (แยกออกมาเพื่อให้เทสต์ใส่ตัวจำลองแทนลำโพงจริงได้)
abstract class AlarmSound {
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

class AssetAlarmSound implements AlarmSound {
  final AudioPlayer _player = AudioPlayer();

  AssetAlarmSound() {
    _player.setReleaseMode(ReleaseMode.stop);
    _player.setVolume(1.0);
  }

  @override
  Future<void> play() async {
    await _player.stop();
    await _player.play(AssetSource('sounds/new_order.wav'));
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// เสียงเตือนออเดอร์ใหม่: ดัง + สั่นซ้ำทุก 3 วินาที ตราบใดที่ยังมีออเดอร์รอร้านรับ
/// (หยุดเองเมื่อร้านกดรับหรือปฏิเสธครบทุกออเดอร์)
class OrderAlarm {
  static const interval = Duration(seconds: 3);
  final AlarmSound Function() _createSound;
  AlarmSound? _sound; // สร้างเมื่อจะดังครั้งแรก
  Timer? _timer;

  OrderAlarm({AlarmSound Function()? sound}) : _createSound = sound ?? AssetAlarmSound.new;

  bool get ringing => _timer != null;

  /// เรียกทุกครั้งที่โหลดออเดอร์ใหม่
  void update(int pendingCount) => pendingCount > 0 ? _start() : stop();

  void _start() {
    if (_timer != null) return;
    _ring();
    _timer = Timer.periodic(interval, (_) => _ring());
  }

  Future<void> _ring() async {
    HapticFeedback.heavyImpact();
    try {
      await (_sound ??= _createSound()).play();
    } catch (e) {
      debugPrint('alarm sound failed: $e'); // เช่น เบราว์เซอร์บล็อกเสียงจนกว่าผู้ใช้จะแตะหน้าจอ
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _sound?.stop();
  }

  void dispose() {
    stop();
    _sound?.dispose();
    _sound = null;
  }
}
