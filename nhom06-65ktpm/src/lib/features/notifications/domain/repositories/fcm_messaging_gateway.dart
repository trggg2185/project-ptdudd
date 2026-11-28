import '../entities/approved_plan_reminder_item.dart';

/// Dữ liệu thông báo đẩy FCM nhận được (chỉ đọc siêu dữ liệu kỹ thuật, không tin nội dung nhạy cảm).
///
/// **Hợp đồng phía server (bắt buộc):**
/// - Chỉ gửi **data-only** FCM payload (không gửi khối `notification` công khai) để thông báo ở
///   cả foreground, background lẫn terminated đều đi qua bộ chống trùng và nội dung trung tính private.
/// - Chỉ truyền siêu dữ liệu điều phối (`owner_uid`, `plan_id`, `item_id`, `item_type`,
///   `dedupe_key`, `scheduled_at`, `plan_status`, `item_status`); tuyệt đối không truyền
///   chỉ số cơ thể, dị ứng, bệnh lý, thuốc hay tọa độ GPS.
class IncomingFcmMessage {
  final String? messageId;
  final String? ownerUid;
  final String? planId;
  final String? itemId;
  final ReminderItemType itemType;
  final String? dedupeKey;
  final DateTime? scheduledAtUtc;
  final DateTime? sentTimeUtc;
  final PlanApprovalStatus? planStatus;
  final PlanItemStatus? itemStatus;

  /// `true` nếu server gửi kèm khối `notification` (vi phạm hợp đồng data-only; Android có thể
  /// đã tự hiển thị ở background/terminated nên handler không được phát đúp thêm lần nữa).
  final bool hasSystemNotificationPayload;

  const IncomingFcmMessage({
    this.messageId,
    this.ownerUid,
    this.planId,
    this.itemId,
    this.itemType = ReminderItemType.habit,
    this.dedupeKey,
    this.scheduledAtUtc,
    this.sentTimeUtc,
    this.planStatus,
    this.itemStatus,
    this.hasSystemNotificationPayload = false,
  });

  /// Kiểm tra trạng thái phê duyệt nếu payload có đính kèm `plan_status` / `item_status`.
  bool get isApprovedOrUnspecified =>
      (planStatus == null || planStatus == PlanApprovalStatus.approved) &&
      (itemStatus == null || itemStatus == PlanItemStatus.approved);

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
