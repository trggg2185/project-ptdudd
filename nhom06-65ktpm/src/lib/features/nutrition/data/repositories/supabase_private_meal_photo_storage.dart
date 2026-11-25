import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/meal_photo_access_error.dart';
import '../../domain/entities/meal_photo_attachment.dart';
import '../../domain/entities/meal_photo_policy.dart';
import '../../domain/repositories/meal_photo_storage.dart';
import '../../domain/services/meal_photo_validator.dart';

/// Lớp dịch vụ upload ảnh bữa ăn lên bucket riêng tư `meal-images` của Supabase Storage.
/// Thực thi validate lại định dạng/kích thước/không còn EXIF ở phía ứng dụng trước khi gửi,
/// đối chiếu `ownerUid` với phiên Firebase hiện tại (đồng nhất với `SupabaseSyncTransport`),
/// ép đường dẫn `<owner_uid>/<log_id>.<ext>` khớp chính sách RLS Storage và hỗ trợ retry
/// idempotent cùng `(ownerUid, logId)` khi object đã được Storage lưu sau ca mất phản hồi.
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
    bool isRetry = false,
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

    try {
      await _client.storage
          .from(MealPhotoStorage.privateBucketName)
          .uploadBinary(
            storagePath,
            photo.bytes,
            fileOptions: FileOptions(
              contentType: verifiedMime,
              upsert: isRetry,
            ),
          );
    } on StorageException catch (error, stackTrace) {
      if (_isAlreadyExistsError(error)) {
        // Object tại đúng đường dẫn `<owner_uid>/<log_id>.<ext>` đã tồn tại
        // trên Storage (ví dụ: lần upload trước đã ghi xong nhưng mất phản hồi HTTP).
        // Trả kết quả đã upload để cập nhật `image_path` cho đúng nhật ký mà không kẹt retry.
      } else if (_isTransientStorageError(error)) {
        Error.throwWithStackTrace(
          const MealPhotoAccessException(
            MealPhotoAccessFailureCode.networkOffline,
            'Kết nối tới Storage bị gián đoạn khi tải ảnh bữa ăn.',
          ),
          stackTrace,
        );
      } else {
        rethrow;
      }
    } on MealPhotoException {
      rethrow;
    } on MealPhotoAccessException {
      rethrow;
    } catch (error, stackTrace) {
      if (_isTransportError(error)) {
        Error.throwWithStackTrace(
          const MealPhotoAccessException(
            MealPhotoAccessFailureCode.networkOffline,
            'Mất phản hồi hoặc lỗi kết nối mạng khi tải ảnh bữa ăn lên Storage.',
          ),
          stackTrace,
        );
      }
      rethrow;
    }

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

  static bool _isAlreadyExistsError(StorageException error) {
    final status = error.statusCode?.trim();
    if (status == '401' || status == '403') {
      return false;
    }
    if (status == '409') {
      return true;
    }
    final code = error.error?.trim().toLowerCase() ?? '';
    if (code == 'duplicate' || code == 'resourcealreadyexists') {
      return true;
    }
    final message = error.message.toLowerCase();
    return message.contains('already exists');
  }

  static bool _isTransientStorageError(StorageException error) {
    final status = error.statusCode?.trim() ?? '';
    return status == '408' ||
        status == '502' ||
        status == '503' ||
        status == '504' ||
        status.contains('ClientException') ||
        status.contains('SocketException') ||
        status.contains('TimeoutException') ||
        status.contains('HttpException');
  }

  static bool _isTransportError(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException ||
        error is HandshakeException) {
      return true;
    }
    final typeName = error.runtimeType.toString();
    return typeName.contains('ClientException');
  }
}
