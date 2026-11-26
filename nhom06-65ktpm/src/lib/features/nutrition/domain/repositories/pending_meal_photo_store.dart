import '../entities/meal_photo_policy.dart';

/// Bản ghi ảnh đã xóa EXIF đang chờ tải lên lại khi thiết bị có mạng.
class PendingMealPhoto {
  final String ownerUid;
  final String logId;
  final PreparedMealPhoto photo;
  final DateTime queuedAt;

  const PendingMealPhoto({
    required this.ownerUid,
    required this.logId,
    required this.photo,
    required this.queuedAt,
  });
}

/// Hàng đợi cục bộ giữ ảnh đã tiền xử lý khi mất mạng để retry mà không mất nhật ký
/// và cô lập hoàn toàn theo `ownerUid`.
abstract interface class PendingMealPhotoStore {
  Future<void> savePendingPhoto({
    required String ownerUid,
    required String logId,
    required PreparedMealPhoto photo,
  });

  Future<List<PendingMealPhoto>> getPendingPhotos({required String ownerUid});

  Future<void> removePendingPhoto({
    required String ownerUid,
    required String logId,
  });

  Future<void> clearForOwner(String ownerUid);
}
