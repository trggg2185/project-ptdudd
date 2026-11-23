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

/// Kết quả lưu nhật ký bữa ăn kèm trạng thái ảnh (upload thành công, nhập tay hoặc chờ đồng bộ offline).
class MealLogSaveResult {
  final MealLog log;
  final bool savedOfflineWithoutCloudPhoto;
  final String userMessage;

  const MealLogSaveResult({
    required this.log,
    required this.savedOfflineWithoutCloudPhoto,
    required this.userMessage,
  });
}
