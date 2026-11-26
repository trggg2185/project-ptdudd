import 'dart:typed_data';

import 'meal_photo_attachment.dart';

/// Quy định giới hạn loại tệp và dung lượng ảnh bữa ăn áp dụng chung cho cả client và dịch vụ.
class MealPhotoPolicy {
  /// Dung lượng tối đa cho tệp ảnh gốc trước khi nén ở client (10 MB).
  final int maxRawBytes;

  /// Dung lượng tối đa cho tệp ảnh sau khi nén trước khi upload lên Storage (1 MB).
  final int maxUploadBytes;

  /// Danh sách MIME ảnh được phép.
  final Set<String> allowedMimeTypes;

  /// Danh sách đuôi tệp được phép.
  final Set<String> allowedExtensions;

  const MealPhotoPolicy({
    this.maxRawBytes = 10 * 1024 * 1024,
    this.maxUploadBytes = 1024 * 1024,
    this.allowedMimeTypes = const {'image/jpeg', 'image/png', 'image/webp'},
    this.allowedExtensions = const {'jpg', 'jpeg', 'png', 'webp'},
  });
}

/// Mã lỗi chuẩn khi kiểm tra, nén hoặc xóa EXIF ảnh bữa ăn.
enum MealPhotoFailureCode {
  emptyFile,
  unsupportedFormat,
  mimeMismatch,
  corruptedImage,
  rawFileTooLarge,
  compressedFileTooLarge,
  exifNotRemoved,
  invalidOwnerPath,
}

/// Ngoại lệ nghiệp vụ khi tệp ảnh bữa ăn không đạt yêu cầu an toàn/kích thước/định dạng.
class MealPhotoException implements Exception {
  final MealPhotoFailureCode code;
  final String message;

  const MealPhotoException(this.code, this.message);

  @override
  String toString() => 'MealPhotoException($code): $message';
}

/// Ảnh bữa ăn đã qua kiểm tra định dạng, nén dung lượng và xóa EXIF/vị trí, sẵn sàng upload.
class PreparedMealPhoto {
  final MealPhotoSource source;
  final String fileName;
  final String mimeType;
  final String extension;
  final Uint8List bytes;
  final int originalSizeBytes;
  final bool compressed;
  final bool exifStripped;

  const PreparedMealPhoto({
    required this.source,
    required this.fileName,
    required this.mimeType,
    required this.extension,
    required this.bytes,
    required this.originalSizeBytes,
    required this.compressed,
    required this.exifStripped,
  });

  int get sizeBytes => bytes.length;
}
