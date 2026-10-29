import 'dart:typed_data';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// แทนที่ตัวเลือกรูปของระบบ: คืนรูปที่กำหนด (หรือ null = ผู้ใช้กดยกเลิก)
class FakeImagePicker extends ImagePickerPlatform {
  Uint8List? next;
  ImageSource? lastSource;

  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    lastSource = source;
    final bytes = next;
    return bytes == null ? null : XFile.fromData(bytes, name: 'slip.png', mimeType: 'image/png');
  }
}

/// PNG ขนาดเล็ก (magic bytes ถูกต้อง)
final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, ...List.filled(32, 1)]);
