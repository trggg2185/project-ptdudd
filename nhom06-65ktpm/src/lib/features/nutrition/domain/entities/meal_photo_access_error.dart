import 'meal_log.dart';
import 'meal_photo_policy.dart';

/// Mã lỗi thiết bị, quyền truy cập hoặc kết nối khi thao tác ảnh bữa ăn.
enum MealPhotoAccessFailureCode {
  cameraPermissionDenied,
  cameraPermissionPermanentlyDenied,
  galleryPermissionDenied,
  deviceUnavailable,
  captureFailed,
  networkOffline,
}

/// Ngoại lệ quyền/thiết bị/mạng khi chụp, chọn hoặc tải ảnh bữa ăn.
class MealPhotoAccessException implements Exception {
  final MealPhotoAccessFailureCode code;
  final String message;

  const MealPhotoAccessException(this.code, this.message);

  @override
  String toString() => 'MealPhotoAccessException($code): $message';
}

/// Kết quả chọn/chụp và tiền xử lý ảnh ở client; luôn hỗ trợ fallback nhập tay khi lỗi.
class MealPhotoPickOutcome {
  final PreparedMealPhoto? preparedPhoto;
  final bool cancelled;
  final bool manualFallbackRequired;
  final String? userMessage;
  final MealPhotoAccessFailureCode? accessError;
  final MealPhotoFailureCode? photoError;

  const MealPhotoPickOutcome({
    this.preparedPhoto,
    this.cancelled = false,
    this.manualFallbackRequired = false,
    this.userMessage,
    this.accessError,
    this.photoError,
  });

  bool get hasPhoto => preparedPhoto != null;
}

/// Kết quả lưu nhật ký bữa ăn kèm trạng thái ảnh (upload thành công, nhập tay,
/// chờ đồng bộ offline hoặc chỉ lưu được nhật ký nhập tay khi không có kho ảnh chờ).
class MealLogSaveResult {
  final MealLog log;
  final bool savedOfflineWithoutCloudPhoto;
  final bool photoQueuedForRetry;
  final String userMessage;

  const MealLogSaveResult({
    required this.log,
    required this.savedOfflineWithoutCloudPhoto,
    this.photoQueuedForRetry = false,
    required this.userMessage,
  });
}

/// Thông tin một ảnh chờ bị từ chối trong quá trình đồng bộ lại để báo rõ người dùng cần sửa ảnh nào.
class PendingMealPhotoRetryFailure {
  final String logId;
  final String mealName;
  final String fileName;
  final String reason;
  final String? statusCode;

  const PendingMealPhotoRetryFailure({
    required this.logId,
    required this.mealName,
    required this.fileName,
    required this.reason,
    this.statusCode,
  });
}

/// Kết quả chi tiết sau một lượt đồng bộ lại hàng đợi ảnh chờ.
class PendingMealPhotoRetryReport {
  final int uploadedCount;
  final List<PendingMealPhotoRetryFailure> rejectedPhotos;
  final int remainingPendingCount;
  final bool stoppedByNetworkError;
  final String userMessage;

  const PendingMealPhotoRetryReport({
    required this.uploadedCount,
    this.rejectedPhotos = const [],
    this.remainingPendingCount = 0,
    this.stoppedByNetworkError = false,
    required this.userMessage,
  });

  bool get hasRejectedPhotos => rejectedPhotos.isNotEmpty;
}
