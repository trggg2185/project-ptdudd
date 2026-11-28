import '../entities/approved_plan_reminder_item.dart';

/// Dữ liệu thông báo đẩy FCM nhận được ở foreground (chỉ đọc siêu dữ liệu, không tin nội dung nhạy cảm).
class IncomingFcmMessage {
  final String? messageId;
  final String? ownerUid;
  final String? planId;
  final String? itemId;
  final ReminderItemType itemType;
  final String? dedupeKey;
  final DateTime? scheduledAtUtc;
  final DateTime? sentTimeUtc;

  const IncomingFcmMessage({
    this.messageId,
    this.ownerUid,
    this.planId,
    this.itemId,
    this.itemType = ReminderItemType.habit,
    this.dedupeKey,
    this.scheduledAtUtc,
    this.sentTimeUtc,
  });

  /// Sinh khóa chống trùng thống nhất cùng định dạng với `ApprovedPlanReminderItem.dedupeKey`.
  String effectiveDedupeKey(String activeOwnerUid) {
    final explicit = dedupeKey?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final resolvedItem = (itemId != null && itemId!.trim().isNotEmpty)
        ? itemId!.trim()
        : (messageId ?? 'fcm-event');
    final slot = (scheduledAtUtc ?? sentTimeUtc)?.toUtc().toIso8601String() ??
        'unspecified';
    return '$activeOwnerUid:${itemType.name}:$resolvedItem:$slot';
  }
}

/// Giao diện trừu tượng cho Firebase Cloud Messaging (FCM) để tích hợp thực tế và kiểm thử cục bộ.
abstract class FcmMessagingGateway {
  /// Tên nền tảng hợp lệ theo ràng buộc DB `device_tokens.platform`: `'android' | 'ios' | 'web'`.
  String get platformName;

  /// Lấy token FCM hiện tại của thiết bị (trả `null` nếu thiết bị/Web chưa hỗ trợ).
  Future<String?> getToken();

  /// Xóa token FCM cục bộ khi đăng xuất để tránh thiết bị tiếp tục nhận push của tài khoản cũ.
  Future<void> deleteToken();

  /// Luồng phát khi FCM cấp token mới (rotation).
  Stream<String> get onTokenRefresh;

  /// Luồng sự kiện FCM nhận khi ứng dụng đang mở (foreground) để đi qua bộ chống trùng Local/FCM.
  Stream<IncomingFcmMessage> get onForegroundMessage;
}
