import '../entities/approved_plan_reminder_item.dart';

/// Nội dung thông báo đã được tách rõ giữa lớp công khai (màn hình khóa) và lớp nội bộ (trong app).
class FormattedNotificationCopy {
  final String lockScreenTitle;
  final String lockScreenBody;
  final String inAppTitle;
  final String inAppBody;

  const FormattedNotificationCopy({
    required this.lockScreenTitle,
    required this.lockScreenBody,
    required this.inAppTitle,
    required this.inAppBody,
  });
}

/// Bộ định dạng đảm bảo **màn hình khóa tuyệt đối không lộ thông tin sức khỏe** (Issue #6).
///
/// Nguyên tắc:
/// 1. Nội dung màn hình khóa (`lockScreenTitle` / `lockScreenBody`) luôn trung tính,
///    không bao giờ chèn tiêu đề thói quen/bữa ăn/môn tập, chỉ số cân nặng/BMI/calo,
///    thông tin dị ứng, bệnh lý, thuốc, chất lượng giấc ngủ hay tọa độ GPS.
/// 2. Ngay cả khi người dùng tắt tùy chọn rút gọn trên màn hình khóa, chuỗi hệ thống vẫn đi qua
///    bộ lọc kiểm tra nhạy cảm để tránh rò rỉ dữ liệu sức khỏe nhạy cảm ra thanh trạng thái.
class NotificationPrivacyFormatter {
  static const String neutralLockScreenTitle = 'HealthyLife';
  static const String neutralLockScreenBody =
      'Bạn có một hoạt động theo lịch đã duyệt. Mở ứng dụng để xem chi tiết.';

  /// Mẫu phát hiện thông tin sức khỏe / dị ứng / bệnh lý / chỉ số cơ thể / tọa độ nhạy cảm.
  static final RegExp _sensitiveHealthPattern = RegExp(
    r'(\b\d+([.,]\d+)?\s*(kg|kcal|calo|bpm|mmhg|mg/dl|mmol|bmi)\b'
    r'|dị ứng|bệnh|thuốc|tiểu đường|huyết áp|trầm cảm|rối loạn|mất ngủ'
    r'|cân nặng|giảm cân|tăng cân|mệt mỏi|suy nhược|chẩn đoán|điều trị'
    r'|allerg|diabet|medic|diagnos|symptom|blood\s*pressure|heart\s*rate'
    r'|\b-?\d{1,2}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}\b)',
    caseSensitive: false,
  );

  /// Kiểm tra một chuỗi có chứa dữ liệu sức khỏe hoặc tọa độ nhạy cảm hay không.
  static bool containsSensitiveHealthInfo(String text) {
    return _sensitiveHealthPattern.hasMatch(text);
  }

  /// Tạo cặp nội dung an toàn cho màn hình khóa và hiển thị nội bộ trong ứng dụng.
  static FormattedNotificationCopy format(
    ApprovedPlanReminderItem item, {
    required bool isSnoozed,
    required bool deferredByQuietHours,
  }) {
    final String lockBody = isSnoozed
        ? 'Nhắc lại hoạt động theo lịch đã duyệt. Mở ứng dụng để xem chi tiết.'
        : deferredByQuietHours
        ? 'Bạn có hoạt động đã dời qua giờ yên lặng. Mở ứng dụng để xem chi tiết.'
        : neutralLockScreenBody;

    final String safeInAppTitle = 'HealthyLife • ${item.itemType.displayLabel}';
    final String rawTitle = item.title.trim();
    final String safeActivityLabel =
        rawTitle.isEmpty || containsSensitiveHealthInfo(rawTitle)
        ? 'Mục ${item.itemType.displayLabel.toLowerCase()} theo lịch đã duyệt'
        : rawTitle;

    final String statusSuffix = isSnoozed
        ? ' (đã tạm hoãn)'
        : deferredByQuietHours
        ? ' (nhắc sau giờ yên lặng)'
        : '';

    return FormattedNotificationCopy(
      lockScreenTitle: neutralLockScreenTitle,
      lockScreenBody: lockBody,
      inAppTitle: safeInAppTitle,
      inAppBody: 'Đến giờ: $safeActivityLabel$statusSuffix.',
    );
  }
}
