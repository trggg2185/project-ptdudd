import 'dart:typed_data';

/// Nguồn ảnh bữa ăn do người dùng lựa chọn.
enum MealPhotoSource { camera, gallery }

/// Trạng thái xử lý/tải lên ảnh bữa ăn riêng tư.
enum MealPhotoUploadStatus { none, pendingLocal, uploaded, failed }

/// Ảnh bữa ăn vừa được chụp từ camera hoặc chọn từ thư viện trước khi kiểm tra/lưu.
class SelectedMealPhoto {
  final MealPhotoSource source;
  final String fileName;
  final String? mimeType;
  final Uint8List bytes;
  final String? localPath;

  const SelectedMealPhoto({
    required this.source,
    required this.fileName,
    required this.bytes,
    this.mimeType,
    this.localPath,
  });

  int get sizeBytes => bytes.length;
}

/// Thông tin ảnh bữa ăn đã được lưu trữ trong bucket riêng tư `meal-images`.
class StoredMealPhoto {
  final String bucket;
  final String storagePath;
  final MealPhotoSource source;
  final int sizeBytes;
  final String mimeType;
  final bool exifStripped;
  final MealPhotoUploadStatus uploadStatus;

  const StoredMealPhoto({
    this.bucket = 'meal-images',
    required this.storagePath,
    required this.source,
    required this.sizeBytes,
    required this.mimeType,
    this.exifStripped = false,
    this.uploadStatus = MealPhotoUploadStatus.uploaded,
  });
}
