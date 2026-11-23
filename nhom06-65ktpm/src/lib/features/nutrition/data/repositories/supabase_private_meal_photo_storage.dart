import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/meal_photo_attachment.dart';
import '../../domain/entities/meal_photo_policy.dart';
import '../../domain/repositories/meal_photo_storage.dart';
import '../../domain/services/meal_photo_validator.dart';

/// Lớp dịch vụ upload ảnh bữa ăn lên bucket riêng tư `meal-images` của Supabase Storage.
/// Thực thi validate lại định dạng/kích thước/không còn EXIF ở phía dịch vụ và ép đường dẫn
/// `<owner_uid>/<log_id>.<ext>` khớp chính sách RLS Storage của dự án.
class SupabasePrivateMealPhotoStorage implements MealPhotoStorage {
  final SupabaseClient _client;
  final MealPhotoValidator validator;
  final String? Function()? currentOwnerUid;

  const SupabasePrivateMealPhotoStorage(
    this._client, {
    this.validator = const MealPhotoValidator(),
    this.currentOwnerUid,
  });

  @override
  Future<StoredMealPhoto> uploadPrivatePhoto({
    required String ownerUid,
    required String logId,
    required PreparedMealPhoto photo,
  }) async {
    final trimmedOwner = ownerUid.trim();
    final activeUid = currentOwnerUid?.call();
    if (activeUid != null && activeUid != trimmedOwner) {
      throw const MealPhotoException(
        MealPhotoFailureCode.invalidOwnerPath,
        'UID chủ sở hữu không khớp phiên đăng nhập hiện tại.',
      );
    }

    final verifiedMime = validator.validateForUpload(
      ownerUid: trimmedOwner,
      bytes: photo.bytes,
      declaredMimeType: photo.mimeType,
    );
    final ext = validator.extensionForMime(verifiedMime);
    final storagePath = '$trimmedOwner/$logId.$ext';

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
    if (!_isOwnedBy(ownerUid, storagePath)) {
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
    if (!_isOwnedBy(ownerUid, storagePath)) {
      throw const MealPhotoException(
        MealPhotoFailureCode.invalidOwnerPath,
        'Không được phép xóa ảnh thuộc tài khoản khác.',
      );
    }
    await _client.storage
        .from(MealPhotoStorage.privateBucketName)
        .remove([storagePath]);
  }

  bool _isOwnedBy(String ownerUid, String storagePath) {
    final trimmed = ownerUid.trim();
    return trimmed.isNotEmpty && storagePath.startsWith('$trimmed/');
  }
}
