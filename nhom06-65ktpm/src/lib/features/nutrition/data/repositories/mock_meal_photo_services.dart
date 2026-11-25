import 'dart:typed_data';

import '../../domain/entities/meal_photo_attachment.dart';
import '../../domain/entities/meal_photo_policy.dart';
import '../../domain/repositories/meal_photo_picker.dart';
import '../../domain/repositories/meal_photo_storage.dart';
import '../../domain/services/meal_photo_validator.dart';

/// Picker giả lập (mock/fixture) cho phép kiểm thử luồng chụp camera / chọn thư viện
/// mà không cần phần cứng camera thật.
class MockMealPhotoPicker implements MealPhotoPicker {
  SelectedMealPhoto? Function(MealPhotoSource source)? onPick;

  MockMealPhotoPicker({this.onPick});

  /// Tạo một ảnh JPEG tối giản hợp lệ có cấu trúc SOI -> APP0 -> SOS -> EOI.
  static Uint8List buildMinimalValidJpeg({List<int>? app1ExifPayload}) {
    final builder = BytesBuilder(copy: false);
    builder.add(const [0xFF, 0xD8]); // SOI
    // APP0 JFIF segment (length = 16)
    builder.add(const [
      0xFF,
      0xE0,
      0x00,
      0x10,
      0x4A,
      0x46,
      0x49,
      0x46,
      0x00,
      0x01,
      0x01,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x00,
    ]);
    if (app1ExifPayload != null) {
      final segmentLen = app1ExifPayload.length + 2;
      builder.add([0xFF, 0xE1, (segmentLen >> 8) & 0xFF, segmentLen & 0xFF]);
      builder.add(app1ExifPayload);
    }
    // SOS + 2 bytes dummy scan data + EOI
    builder.add(const [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x11, 0x22]);
    builder.add(const [0xFF, 0xD9]); // EOI
    return builder.toBytes();
  }

  @override
  Future<SelectedMealPhoto?> pickPhoto(MealPhotoSource source) async {
    if (onPick != null) {
      return onPick!(source);
    }
    return SelectedMealPhoto(
      source: source,
      fileName: source == MealPhotoSource.camera
          ? 'camera_meal.jpg'
          : 'gallery_meal.jpg',
      mimeType: 'image/jpeg',
      bytes: buildMinimalValidJpeg(),
    );
  }
}

/// Lưu trữ ảnh riêng tư giả lập trong bộ nhớ (mock/fixture), thực thi:
/// - Validate lại loại/kích thước/sạch EXIF ở lớp dịch vụ trước khi lưu.
/// - Quy tắc đường dẫn `<owner_uid>/<file-name>` và chặn truy cập chéo tài khoản
///   giống RLS bucket `meal-images`.
class InMemoryPrivateMealPhotoStorage implements MealPhotoStorage {
  final MealPhotoValidator validator;
  final Map<String, Uint8List> _objects = {};

  InMemoryPrivateMealPhotoStorage({
    this.validator = const MealPhotoValidator(),
  });

  Map<String, Uint8List> get objects => Map<String, Uint8List>.unmodifiable(_objects);

  @override
  Future<StoredMealPhoto> uploadPrivatePhoto({
    required String ownerUid,
    required String logId,
    required PreparedMealPhoto photo,
    bool isRetry = false,
  }) async {
    final trimmedOwner = ownerUid.trim();
    final verifiedMime = validator.validateForUpload(
      ownerUid: trimmedOwner,
      bytes: photo.bytes,
      declaredMimeType: photo.mimeType,
    );
    final safeExtension = validator.extensionForMime(verifiedMime);
    final storagePath = '$trimmedOwner/$logId.$safeExtension';
    _objects[storagePath] = Uint8List.fromList(photo.bytes);

    return StoredMealPhoto(
      bucket: MealPhotoStorage.privateBucketName,
      storagePath: storagePath,
      source: photo.source,
      sizeBytes: photo.sizeBytes,
      mimeType: verifiedMime,
      exifStripped: true,
      uploadStatus: MealPhotoUploadStatus.uploaded,
    );
  }

  @override
  Future<String?> createShortLivedSignedUrl({
    required String ownerUid,
    required String storagePath,
    Duration expiresIn = const Duration(minutes: 10),
  }) async {
    if (!_isOwnedBy(ownerUid, storagePath) || !_objects.containsKey(storagePath)) {
      return null;
    }
    final expirySeconds = expiresIn.inSeconds;
    return 'signed://${MealPhotoStorage.privateBucketName}/$storagePath?expiresIn=$expirySeconds';
  }

  @override
  Future<void> deletePrivatePhoto({
    required String ownerUid,
    required String storagePath,
  }) async {
    if (!_isOwnedBy(ownerUid, storagePath)) {
      throw StateError('Không được phép xóa ảnh thuộc tài khoản khác.');
    }
    _objects.remove(storagePath);
  }

  bool _isOwnedBy(String ownerUid, String storagePath) {
    final prefix = '${ownerUid.trim()}/';
    return ownerUid.trim().isNotEmpty && storagePath.startsWith(prefix);
  }
}
