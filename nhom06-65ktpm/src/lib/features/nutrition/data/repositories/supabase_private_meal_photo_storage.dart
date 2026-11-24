import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/meal_photo_attachment.dart';
import '../../domain/entities/meal_photo_policy.dart';
import '../../domain/repositories/meal_photo_storage.dart';
import '../../domain/services/meal_photo_validator.dart';

/// Lớp dịch vụ upload ảnh bữa ăn lên bucket riêng tư `meal-images` của Supabase Storage.
/// Thực thi validate lại định dạng/kích thước/không còn EXIF ở phía dịch vụ, đối chiếu
/// `ownerUid` với phiên Firebase hiện tại (đồng nhất với `SupabaseSyncTransport`) và ép đường dẫn
/// `<owner_uid>/<log_id>.<ext>` khớp chính sách RLS Storage của dự án.
class SupabasePrivateMealPhotoStorage implements MealPhotoStorage {
  static final RegExp _safeLogIdPattern = RegExp(r'^[a-zA-Z0-9_-]+$');

  final SupabaseClient _client;
  final MealPhotoValidator validator;
  final String? Function() currentOwnerUid;

  const SupabasePrivateMealPhotoStorage(
    this._client, {
    required this.currentOwnerUid,
    this.validator = const MealPhotoValidator(),
  });

  @override
  Future<StoredMealPhoto> uploadPrivatePhoto({
    required String ownerUid,
    required String logId,
    required PreparedMealPhoto photo,
  }) async {
    final trimmedOwner = _requireAuthenticatedOwner(ownerUid);
    final safeLogId = _validateLogId(logId);

    final verifiedMime = validator.validateForUpload(
      ownerUid: trimmedOwner,
      bytes: photo.bytes,
      declaredMimeType: photo.mimeType,
    );
    final ext = validator.extensionForMime(verifiedMime);
    final storagePath = '$trimmedOwner/$safeLogId.$ext';

    await _client.storage
        .from(MealPhotoStorage.privateBucketName)
        .uploadBinary(
          storagePath,
          photo.bytes,
          fileOptions: FileOptions(contentType: verifiedMime, upsert: false),
        );

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
    final trimmedOwner = ownerUid.trim();
    if (trimmedOwner.isEmpty ||
        currentOwnerUid() != trimmedOwner ||
        !_isOwnedBy(trimmedOwner, storagePath)) {
      return null;
    }
    return _client.storage
        .from(MealPhotoStorage.privateBucketName)
        .createSignedUrl(storagePath, expiresIn.inSeconds);
  }

  @override
  Future<void> deletePrivatePhoto({
    required String ownerUid,
    required String storagePath,
  }) async {
    final trimmedOwner = _requireAuthenticatedOwner(ownerUid);
    if (!_isOwnedBy(trimmedOwner, storagePath)) {
      throw const MealPhotoException(
        MealPhotoFailureCode.invalidOwnerPath,
        'Không được phép xóa ảnh thuộc tài khoản khác.',
      );
    }
    await _client.storage
        .from(MealPhotoStorage.privateBucketName)
        .remove([storagePath]);
  }

  String _requireAuthenticatedOwner(String ownerUid) {
    final trimmed = ownerUid.trim();
    if (trimmed.isEmpty || currentOwnerUid() != trimmed) {
      throw const MealPhotoException(
        MealPhotoFailureCode.invalidOwnerPath,
        'UID chủ sở hữu không khớp phiên đăng nhập hiện tại.',
      );
    }
    return trimmed;
  }

  String _validateLogId(String logId) {
    final trimmed = logId.trim();
    if (trimmed.isEmpty || !_safeLogIdPattern.hasMatch(trimmed)) {
      throw const MealPhotoException(
        MealPhotoFailureCode.invalidOwnerPath,
        'Định danh nhật ký không hợp lệ để tạo đường dẫn ảnh riêng tư.',
      );
    }
    return trimmed;
  }

  bool _isOwnedBy(String ownerUid, String storagePath) {
    return ownerUid.isNotEmpty &&
        !storagePath.contains('..') &&
        storagePath.startsWith('$ownerUid/');
  }
}
