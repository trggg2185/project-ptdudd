import 'dart:convert';
import 'dart:typed_data';

import '../entities/meal_photo_attachment.dart';
import '../entities/meal_photo_policy.dart';
import 'meal_photo_validator.dart';

/// Interface nén ảnh có thể thay thế bằng bộ nén native trên Android/iOS khi tích hợp thiết bị.
abstract interface class MealPhotoCompressor {
  Future<Uint8List> compress({
    required Uint8List bytes,
    required String mimeType,
    required int maxBytes,
    required int quality,
  });
}

/// Interface tiền xử lý ảnh bữa ăn trước khi upload: validate → bỏ EXIF → nén → kiểm tra lại.
abstract interface class MealPhotoProcessor {
  Future<PreparedMealPhoto> prepare(SelectedMealPhoto photo);
}

/// Bộ xử lý ảnh mặc định chạy thuần Dart trên mọi nền tảng (Android/Web/Test):
/// 1. Kiểm tra định dạng thật (magic bytes) và dung lượng gốc ở client.
/// 2. Loại bỏ triệt để metadata EXIF/GPS/XMP/IPTC/Comment ở mức nhị phân cho JPEG, PNG và WebP.
/// 3. Nén ảnh lặp theo các mức chất lượng (85 -> 70 -> 55 -> 40) nếu vượt giới hạn upload hoặc có bộ nén.
/// 4. Xóa lại EXIF sau khi nén và kiểm tra dung lượng cuối <= `maxUploadBytes`.
class DefaultMealPhotoProcessor implements MealPhotoProcessor {
  static const List<int> _compressionQualities = [85, 70, 55, 40];

  final MealPhotoValidator validator;
  final MealPhotoCompressor? compressor;

  const DefaultMealPhotoProcessor({
    this.validator = const MealPhotoValidator(),
    this.compressor,
  });

  @override
  Future<PreparedMealPhoto> prepare(SelectedMealPhoto photo) async {
    final mimeType = validator.validateClientSelection(photo);
    final originalSize = photo.sizeBytes;

    var workingBytes = stripMetadata(photo.bytes, mimeType: mimeType);
    var wasCompressed = false;

    final needsCompression =
        workingBytes.length > validator.policy.maxUploadBytes ||
        compressor != null;

    if (needsCompression && compressor != null) {
      for (final quality in _compressionQualities) {
        final candidate = await compressor!.compress(
          bytes: workingBytes,
          mimeType: mimeType,
          maxBytes: validator.policy.maxUploadBytes,
          quality: quality,
        );
        final candidateMime = validator.detectMimeType(candidate);
        if (candidateMime == null ||
            !validator.policy.allowedMimeTypes.contains(candidateMime)) {
          throw const MealPhotoException(
            MealPhotoFailureCode.corruptedImage,
            'Dữ liệu sau nén không phải ảnh hợp lệ.',
          );
        }
        // Xóa lại EXIF đề phòng bộ nén nền tảng tự chèn metadata.
        workingBytes = stripMetadata(candidate, mimeType: candidateMime);
        wasCompressed = true;
        if (workingBytes.length <= validator.policy.maxUploadBytes) {
          break;
        }
      }
    }

    final finalMime = validator.detectMimeType(workingBytes) ?? mimeType;
    if (workingBytes.length > validator.policy.maxUploadBytes) {
      final maxKb = (validator.policy.maxUploadBytes / 1024).round();
      throw MealPhotoException(
        MealPhotoFailureCode.compressedFileTooLarge,
        'Ảnh vẫn vượt giới hạn $maxKb KB sau khi xử lý. Vui lòng chọn ảnh nhẹ hơn hoặc nhập tay.',
      );
    }

    if (validator.containsExifOrSensitiveMetadata(
      workingBytes,
      mimeType: finalMime,
    )) {
      throw const MealPhotoException(
        MealPhotoFailureCode.exifNotRemoved,
        'Không thể xóa sạch metadata EXIF khỏi ảnh.',
      );
    }

    final extension = validator.extensionForMime(finalMime);
    return PreparedMealPhoto(
      source: photo.source,
      fileName: _sanitizeFileName(photo.fileName, extension),
      mimeType: finalMime,
      extension: extension,
      bytes: Uint8List.fromList(workingBytes),
      originalSizeBytes: originalSize,
      compressed: wasCompressed || workingBytes.length < originalSize,
      exifStripped: true,
    );
  }

  /// Loại bỏ toàn bộ metadata EXIF/GPS/XMP/IPTC/Comment ở mức nhị phân.
  Uint8List stripMetadata(Uint8List bytes, {required String mimeType}) {
    return switch (mimeType) {
      'image/jpeg' => _stripJpegMetadata(bytes),
      'image/png' => _stripPngMetadata(bytes),
      'image/webp' => _stripWebpMetadata(bytes),
      _ => bytes,
    };
  }

  Uint8List _stripJpegMetadata(Uint8List bytes) {
    final output = BytesBuilder(copy: false);
    output.add(const [0xFF, 0xD8]); // SOI

    var offset = 2;
    while (offset < bytes.length) {
      if (bytes[offset] != 0xFF) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Dữ liệu JPEG bị hỏng khi xóa EXIF.',
        );
      }
      final markerStart = offset;
      while (offset < bytes.length && bytes[offset] == 0xFF) {
        offset++;
      }
      if (offset >= bytes.length) break;
      final marker = bytes[offset++];

      if (marker == 0xD9) {
        output.add(const [0xFF, 0xD9]);
        break;
      }

      if (marker == 0xDA) {
        // SOS: giữ nguyên phần dữ liệu ảnh nén cho đến hết EOI
        output.add(bytes.sublist(markerStart));
        break;
      }

      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        output.add([0xFF, marker]);
        continue;
      }

      if (offset + 2 > bytes.length) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Segment JPEG bị thiếu độ dài.',
        );
      }
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      final segmentEnd = offset + length;
      if (length < 2 || segmentEnd > bytes.length) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Segment JPEG vượt quá kích thước tệp.',
        );
      }

      // Loại bỏ APP1 (EXIF/GPS/XMP), APP13 (IPTC/Photoshop), COM (Comment)
      final shouldStrip = marker == 0xE1 || marker == 0xED || marker == 0xFE;
      if (!shouldStrip) {
        output.add([0xFF, marker]);
        output.add(bytes.sublist(offset, segmentEnd));
      }
      offset = segmentEnd;
    }

    return output.toBytes();
  }

  Uint8List _stripPngMetadata(Uint8List bytes) {
    const sensitiveChunks = {'eXIf', 'tEXt', 'iTXt', 'zTXt'};
    final output = BytesBuilder(copy: false);
    output.add(bytes.sublist(0, 8)); // PNG signature

    var offset = 8;
    while (offset + 12 <= bytes.length) {
      final length = (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      final type = ascii.decode(
        bytes.sublist(offset + 4, offset + 8),
        allowInvalid: true,
      );
      final chunkEnd = offset + 12 + length;
      if (chunkEnd > bytes.length) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Chunk PNG bị cắt cụt khi xóa metadata.',
        );
      }
      if (!sensitiveChunks.contains(type)) {
        output.add(bytes.sublist(offset, chunkEnd));
      }
      offset = chunkEnd;
      if (type == 'IEND') break;
    }

    return output.toBytes();
  }

  Uint8List _stripWebpMetadata(Uint8List bytes) {
    final body = BytesBuilder(copy: false);
    body.add(const [0x57, 0x45, 0x42, 0x50]); // WEBP

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final fourCc = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final chunkSize = bytes[offset + 4] |
          (bytes[offset + 5] << 8) |
          (bytes[offset + 6] << 16) |
          (bytes[offset + 7] << 24);
      final paddedSize = chunkSize + (chunkSize.isOdd ? 1 : 0);
      final chunkEnd = offset + 8 + paddedSize;
      if (chunkEnd > bytes.length) {
        throw const MealPhotoException(
          MealPhotoFailureCode.corruptedImage,
          'Chunk WebP bị cắt cụt khi xóa EXIF.',
        );
      }

      if (fourCc != 'EXIF' && fourCc != 'XMP ') {
        final chunkBytes = Uint8List.fromList(bytes.sublist(offset, chunkEnd));
        // Nếu có VP8X extended header, xóa bit cờ EXIF (bit 3) và XMP (bit 2).
        if (fourCc == 'VP8X' && chunkBytes.length >= 9) {
          chunkBytes[8] = chunkBytes[8] & ~0x0C;
        }
        body.add(chunkBytes);
      }
      offset = chunkEnd;
    }

    final bodyBytes = body.toBytes();
    final riffSize = bodyBytes.length;
    final header = Uint8List(8)
      ..[0] = 0x52 // R
      ..[1] = 0x49 // I
      ..[2] = 0x46 // F
      ..[3] = 0x46 // F
      ..[4] = riffSize & 0xFF
      ..[5] = (riffSize >> 8) & 0xFF
      ..[6] = (riffSize >> 16) & 0xFF
      ..[7] = (riffSize >> 24) & 0xFF;

    final result = BytesBuilder(copy: false)
      ..add(header)
      ..add(bodyBytes);
    return result.toBytes();
  }

  static String _sanitizeFileName(String rawName, String extension) {
    final baseName = rawName.trim().split(RegExp(r'[/\\]')).last;
    final dotIndex = baseName.lastIndexOf('.');
    final stem = (dotIndex > 0 ? baseName.substring(0, dotIndex) : baseName)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeStem = stem.isEmpty ? 'meal_photo' : stem;
    return '$safeStem.$extension';
  }
}
