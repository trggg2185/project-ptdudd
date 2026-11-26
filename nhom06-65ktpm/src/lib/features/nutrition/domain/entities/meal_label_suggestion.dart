/// Trạng thái của phần mở rộng AI đề xuất nhãn món ăn từ ảnh (không nằm trong đường dẫn chặn cốt lõi).
enum MealLabelSuggestionStatus {
  /// Bản cốt lõi chưa bật AI mở rộng.
  disabled,

  /// Người dùng chưa cấp đồng ý riêng cho tính năng AI mở rộng.
  consentRequired,

  /// AI trả về nhãn tham khảo để người dùng tự kiểm tra và xác nhận tên món.
  suggestedForConfirmation,

  /// AI lỗi, quá thời gian hoặc không có nhãn hợp lệ -> fallback về nhập tay, không chặn luồng chính.
  fallbackToManual,
}

/// Kết quả đề xuất nhãn món ăn từ phần mở rộng AI (nếu được bật về sau).
///
/// Ràng buộc an toàn bất biến:
/// - Không bao giờ suy ra calo từ ảnh ([infersCaloriesFromPhoto] luôn `false`).
/// - Không bao giờ khẳng định món không chứa dị nguyên chỉ từ ảnh
///   ([infersAllergenSafetyFromPhoto] luôn `false`).
/// - Mọi nhãn chỉ mang tính tham khảo và luôn yêu cầu người dùng tự xác nhận ([requiresUserConfirmation] luôn `true`).
class MealLabelSuggestionResult {
  static const String photoSafetyDisclaimer =
      'Ảnh bữa ăn chỉ dùng để lưu nhật ký. Hệ thống không suy ra lượng calo hay khẳng định món ăn không chứa dị nguyên chỉ từ ảnh; người dùng tự xác nhận tên món.';

  final MealLabelSuggestionStatus status;
  final List<String> candidateLabels;
  final String userNotice;
  final bool requiresUserConfirmation;
  final bool infersCaloriesFromPhoto;
  final bool infersAllergenSafetyFromPhoto;

  const MealLabelSuggestionResult({
    required this.status,
    this.candidateLabels = const [],
    required this.userNotice,
  }) : requiresUserConfirmation = true,
       infersCaloriesFromPhoto = false,
       infersAllergenSafetyFromPhoto = false;

  bool get hasCandidates => candidateLabels.isNotEmpty;
}
