import 'dart:math';

/// Bộ sinh định danh UUID v4 thuần Dart không phụ thuộc package ngoài.
class IdGenerator {
  static final Random _random = Random.secure();

  /// Sinh chuỗi UUID v4 chuẩn dạng 8-4-4-4-12 ký tự hex.
  static String generateUuid() {
    final values = List<int>.generate(16, (i) => _random.nextInt(256));
    // Set version to 0100 (UUID v4)
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to 10xx (RFC 4122)
    values[8] = (values[8] & 0x3f) | 0x80;

    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
