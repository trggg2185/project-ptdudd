import 'dart:typed_data';

import '../../domain/entities/meal_photo_attachment.dart';
import '../../domain/repositories/meal_photo_picker.dart';
import '../../domain/repositories/meal_photo_storage.dart';

/// Picker giả lập (mock/fixture) cho phép kiểm thử luồng chụp camera / chọn thư viện
/// mà không cần phần cứng camera thật.
class MockMealPhotoPicker implements MealPhotoPicker {
  SelectedMealPhoto? Function(MealPhotoSource source)? onPick;

  MockMealPhotoPicker({this.onPick});

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
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9]),
    );
  }
}

/// Lưu trữ ảnh riêng tư giả lập trong bộ nhớ (mock/fixture), thực thi quy tắc đường dẫn
/// `<owner_uid>/<file-name>` và chặn truy cập chéo tài khoản giống RLS bucket `meal-images`.
class InMemoryPrivateMealPhotoStorage implements MealPhotoStorage {
  final Map<String, Uint8List> _objects = {};

  Map<String, Uint8List> get objects => Map<String, Uint8List>.unmodifiable(_objects);

  @override
  Future<StoredMealPhoto> uploadPrivatePhoto({
    required String ownerUid,
    required String logId,
    required SelectedMealPhoto photo,
  }) async {
    final trimmedOwner = ownerUid.trim();
    if (trimmedOwner.isEmpty) {
      throw ArgumentError.value(ownerUid, 'ownerUid', 'Thiếu owner_uid.');
    }

    final safeExtension = _resolveExtension(photo.fileName, photo.mimeType);
    final storagePath = '$trimmedOwner/$logId.$safeExtension';
    _objects[storagePath] = Uint8List.fromList(photo.bytes);

    return StoredMealPhoto(
      bucket: MealPhotoStorage.privateBucketName,
      storagePath: storagePath,
      source: photo.source,
      sizeBytes: photo.sizeBytes,
      mimeType: photo.mimeType ?? 'image/jpeg',
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

  String _resolveExtension(String fileName, String? mimeType) {
    final normalizedMime = (mimeType ?? '').toLowerCase();
    if (normalizedMime == 'image/png') return 'png';
    if (normalizedMime == 'image/webp') return 'webp';
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0 && dotIndex < fileName.length - 1) {
      final ext = fileName.substring(dotIndex + 1).toLowerCase();
      if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp') {
        return ext == 'jpeg' ? 'jpg' : ext;
      }
    }
    return 'jpg';
  }
}
