import 'dart:convert';
import 'dart:typed_data';

import '../entities/meal_photo_attachment.dart';
import '../entities/meal_photo_policy.dart';

/// Bộ kiểm tra loại tệp (theo magic bytes thật), dung lượng và sự tồn tại của EXIF/GPS
/// dùng chung ở cả phía client và lớp dịch vụ upload Storage.
class MealPhotoValidator {
  final MealPhotoPolicy policy;

  const MealPhotoValidator({this.policy = const MealPhotoPolicy()});

  /// Nhận diện định dạng MIME thật từ magic bytes, không chỉ tin vào đuôi tệp.
  String? detectMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      // P
      return 'image/webp';
    }
    return null;
  }

  /// Trả về đuôi tệp chuẩn theo MIME đã xác minh.
  String extensionForMime(String mimeType) {
    return switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => throw MealPhotoException(
        MealPhotoFailureCode.unsupportedFormat,
        'Định dạng ảnh không được hỗ trợ ($mimeType).',
      ),
    };
  }

  /// Kiểm tra ở phía client ngay khi người dùng chụp/chọn ảnh.
  String validateClientSelection(SelectedMealPhoto photo) {
    if (photo.bytes.isEmpty) {
      throw const MealPhotoException(
        MealPhotoFailureCode.emptyFile,
        'Tệp ảnh rỗng, vui lòng chọn ảnh khác hoặc nhập tay.',
      );
    }

    if (photo.sizeBytes > policy.maxRawBytes) {
      final maxMb = (policy.maxRawBytes / (1024 * 1024)).toStringAsFixed(1);
      throw MealPhotoException(
        MealPhotoFailureCode.rawFileTooLarge,
        'Ảnh gốc vượt quá giới hạn $maxMb MB trước khi nén.',
      );
    }

    final detectedMime = detectMimeType(photo.bytes);
    if (detectedMime == null || !policy.allowedMimeTypes.contains(detectedMime)) {
      throw const MealPhotoException(
        MealPhotoFailureCode.unsupportedFormat,
        'Chỉ hỗ trợ tệp ảnh JPEG, PNG hoặc WebP hợp lệ.',
      );
    }

    final declaredExt = _extractExtension(photo.fileName);
    if (declaredExt != null && !policy.allowedExtensions.contains(declaredExt)) {
      throw MealPhotoException(
        MealPhotoFailureCode.unsupportedFormat,
        'Đuôi tệp ".$declaredExt" không được hỗ trợ.',
      );
    }

    final declaredMime = photo.mimeType?.trim().toLowerCase();
    if (declaredMime != null && declaredMime.isNotEmpty) {
      final normalizedDeclared = declaredMime == 'image/jpg'
          ? 'image/jpeg'
          : declaredMime;
      if (normalizedDeclared != detectedMime) {
        throw MealPhotoException(
          MealPhotoFailureCode.mimeMismatch,
          'Loại tệp khai báo ($declaredMime) không khớp nội dung ảnh thật ($detectedMime).',
        );
      }
    }

    _validateBinaryStructure(photo.bytes, detectedMime);
    return detectedMime;
  }

  /// Kiểm tra bắt buộc ở lớp dịch vụ trước khi upload vào bucket riêng tư `meal-images`.
  String validateForUpload({
    required String ownerUid,
    required Uint8List bytes,
    required String declaredMimeType,
  }) {
    if (ownerUid.trim().isEmpty) {
      throw const MealPhotoException(
        MealPhotoFailureCode.invalidOwnerPath,
        'Thiếu định danh chủ tài khoản cho đường dẫn ảnh riêng tư.',
      );
    }
    if (bytes.isEmpty) {
      throw const MealPhotoException(
        MealPhotoFailureCode.emptyFile,
        'Ảnh chuẩn bị tải lên bị rỗng.',
      );
    }
    if (bytes.length > policy.maxUploadBytes) {
      final maxKb = (policy.maxUploadBytes / 1024).round();
      throw MealPhotoException(
        MealPhotoFailureCode.compressedFileTooLarge,
        'Ảnh sau nén (${(bytes.length / 1024).round()} KB) vẫn vượt quá giới hạn $maxKb KB.',
      );
    }

    final detectedMime = detectMimeType(bytes);
    if (detectedMime == null || !policy.allowedMimeTypes.contains(detectedMime)) {
      throw const MealPhotoException(
        MealPhotoFailureCode.unsupportedFormat,
        'Dịch vụ chỉ chấp nhận ảnh JPEG, PNG hoặc WebP hợp lệ.',
      );
    }
    if (declaredMimeType.trim().toLowerCase() != detectedMime) {
      throw MealPhotoException(
        MealPhotoFailureCode.mimeMismatch,
        'Content-Type ($declaredMimeType) không khớp dữ liệu ảnh ($detectedMime).',
      );
    }

    _validateBinaryStructure(bytes, detectedMime);

    if (containsExifOrSensitiveMetadata(bytes, mimeType: detectedMime)) {
      throw const MealPhotoException(
        MealPhotoFailureCode.exifNotRemoved,
        'Ảnh vẫn còn metadata EXIF/vị trí nên dịch vụ từ chối tải lên.',
      );
    }

    return detectedMime;
  }

  /// Kiểm tra ảnh có còn chứa EXIF/XMP/IPTC/GPS hoặc chunk văn bản nhạy cảm hay không.
  bool containsExifOrSensitiveMetadata(Uint8List bytes, {String? mimeType}) {
    final resolvedMime = mimeType ?? detectMimeType(bytes);
    return switch (resolvedMime) {
      'image/jpeg' => _jpegContainsSensitiveMetadata(bytes),
      'image/png' => _pngContainsSensitiveMetadata(bytes),
      'image/webp' => _webpContainsSensitiveMetadata(bytes),
      _ => false,
    };
  }

  void _validateBinaryStructure(Uint8List bytes, String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        _validateJpegStructure(bytes);
        break;
      case 'image/png':
        _validatePngStructure(bytes);
        break;
      case 'image/webp':
        _validateWebpStructure(bytes);
        break;
    }
  }

  void _validateJpegStructure(Uint8List bytes) {
    if (bytes.length < 4 ||
        bytes[0] != 0xFF ||
        bytes[1] != 0xD8 ||
        bytes[bytes.length - 2] != 0xFF ||
        bytes[bytes.length - 1] != 0xD9) {
      throw const MealPhotoException(
        MealPhotoFailureCode.corruptedImage,
        'Tệp ảnh JPEG bị lỗi hoặc cắt cụt.',
      );
    }
    var offset = 2;
    while (offset < bytes.length - 2) {
      if (bytes[offset] != 0xFF) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Cấu trúc marker JPEG không hợp lệ.',
        );
      }
      while (offset < bytes.length && bytes[offset] == 0xFF) {
        offset++;
      }
      if (offset >= bytes.length) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Tệp JPEG kết thúc đột ngột.',
        );
      }
      final marker = bytes[offset++];
      if (marker == 0xD9 || marker == 0xDA) {
        return; // EOI hoặc SOS (dữ liệu nén ảnh bắt đầu)
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        continue; // Standalone markers không có độ dài
      }
      if (offset + 2 > bytes.length) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Segment JPEG bị thiếu độ dài.',
        );
      }
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Độ dài segment JPEG vượt quá kích thước tệp.',
        );
      }
      offset += length;
    }
  }

  void _validatePngStructure(Uint8List bytes) {
    if (bytes.length < 24) {
      throw const MealPhotoException(
        MealPhotoFailureCode.corruptedImage,
        'Tệp ảnh PNG quá ngắn hoặc bị hỏng.',
      );
    }
    var offset = 8;
    var hasIend = false;
    while (offset + 12 <= bytes.length) {
      final length = _readUint32BigEndian(bytes, offset);
      final type = ascii.decode(
        bytes.sublist(offset + 4, offset + 8),
        allowInvalid: true,
      );
      final chunkEnd = offset + 12 + length;
      if (chunkEnd > bytes.length) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Chunk PNG bị cắt cụt.',
        );
      }
      if (type == 'IEND') {
        hasIend = true;
        break;
      }
      offset = chunkEnd;
    }
    if (!hasIend) {
      throw const MealPhotoException(
        MealPhotoFailureCode.corruptedImage,
        'Tệp PNG thiếu khối kết thúc IEND.',
      );
    }
  }

  void _validateWebpStructure(Uint8List bytes) {
    if (bytes.length < 20) {
      throw const MealPhotoException(
        MealPhotoFailureCode.corruptedImage,
        'Tệp WebP quá ngắn hoặc bị hỏng.',
      );
    }
    final riffSize = _readUint32LittleEndian(bytes, 4);
    if (riffSize + 8 > bytes.length) {
      throw const MealPhotoException(
        MealPhotoFailureCode.corruptedImage,
        'Kích thước header WebP không khớp dữ liệu tệp.',
      );
    }
  }

  bool _jpegContainsSensitiveMetadata(Uint8List bytes) {
    var offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset] != 0xFF) break;
      while (offset < bytes.length && bytes[offset] == 0xFF) {
        offset++;
      }
      if (offset >= bytes.length) break;
      final marker = bytes[offset++];
      if (marker == 0xD9 || marker == 0xDA) break;
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
      if (offset + 2 > bytes.length) break;
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) break;

      // APP1 (EXIF/GPS/XMP), APP13 (IPTC/Photoshop), COM (Comment)
      if (marker == 0xE1 || marker == 0xED || marker == 0xFE) {
        return true;
      }
      offset += length;
    }
    return false;
  }

  bool _pngContainsSensitiveMetadata(Uint8List bytes) {
    const sensitiveChunks = {'eXIf', 'tEXt', 'iTXt', 'zTXt'};
    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = _readUint32BigEndian(bytes, offset);
      final type = ascii.decode(
        bytes.sublist(offset + 4, offset + 8),
        allowInvalid: true,
      );
      if (sensitiveChunks.contains(type)) {
        return true;
      }
      final chunkEnd = offset + 12 + length;
      if (chunkEnd > bytes.length || type == 'IEND') break;
      offset = chunkEnd;
    }
    return false;
  }

  bool _webpContainsSensitiveMetadata(Uint8List bytes) {
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final fourCc = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final chunkSize = _readUint32LittleEndian(bytes, offset + 4);
      if (fourCc == 'EXIF' || fourCc == 'XMP ') {
        return true;
      }
      final paddedSize = chunkSize + (chunkSize.isOdd ? 1 : 0);
      final nextOffset = offset + 8 + paddedSize;
      if (nextOffset > bytes.length) break;
      offset = nextOffset;
    }
    return false;
  }

  static String? _extractExtension(String fileName) {
    final trimmed = fileName.trim();
    final dotIndex = trimmed.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= trimmed.length - 1) return null;
    return trimmed.substring(dotIndex + 1).toLowerCase();
  }

  static int _readUint32BigEndian(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static int _readUint32LittleEndian(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}
