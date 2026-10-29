import 'dart:async';
import 'package:google_fonts/google_fonts.dart';

/// ตั้งค่าที่ใช้กับทุกไฟล์เทสต์: ใช้ฟอนต์ที่ฝังในแอป ไม่ดาวน์โหลดจากเน็ต
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
