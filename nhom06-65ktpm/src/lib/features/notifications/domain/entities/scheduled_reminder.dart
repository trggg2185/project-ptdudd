import 'approved_plan_reminder_item.dart';

/// Trạng thái quyền gửi thông báo của thiết bị.
enum NotificationPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  unsupportedPlatform,
  unknown;

  bool get canScheduleLocal => this == NotificationPermissionStatus.granted;
}

/// Nguồn phát thông báo dùng cho cơ chế chống trùng Local / FCM.
enum NotificationChannelSource { local, fcm }

/// Lời nhắc cụ thể đã được tính toán để lên lịch trên thiết bị.
class ScheduledReminder {
  /// ID số nguyên dương 31-bit xác định duy nhất theo `(ownerUid, itemId)`.
  final int notificationId;
  final String ownerUid;
  final String planId;
  final String itemId;
  final ReminderItemType itemType;
  final String dedupeKey;

  /// Giờ gốc của mục lịch (UTC).
  final DateTime originalScheduledAtUtc;

  /// Giờ phát thực tế sau khi áp dụng tạm hoãn (snooze) và giờ yên lặng (UTC).
  final DateTime effectiveScheduledAtUtc;

  /// Múi giờ IANA được dùng để tính thời điểm phát.
  final String timezoneName;

  /// Đánh dấu lời nhắc đã bị lùi ra ngoài giờ yên lặng.
  final bool deferredByQuietHours;

  /// Đánh dấu lời nhắc đang ở trạng thái tạm hoãn (snooze).
  final bool isSnoozed;

  /// Nội dung an toàn tuyệt đối cho màn hình khóa (KHÔNG chứa chi tiết sức khỏe).
  final String lockScreenTitle;
  final String lockScreenBody;

  /// Nội dung hiển thị trong ứng dụng (đã mở khóa).
  final String inAppTitle;
  final String inAppBody;

  /// Bật cờ ẩn chi tiết sức khỏe trên màn hình khóa (Android `VISIBILITY_PRIVATE`).
  final bool hideDetailsOnLockScreen;

  const ScheduledReminder({
    required this.notificationId,
    required this.ownerUid,
    required this.planId,
    required this.itemId,
    required this.itemType,
    required this.dedupeKey,
    required this.originalScheduledAtUtc,
    required this.effectiveScheduledAtUtc,
    required this.timezoneName,
    required this.deferredByQuietHours,
    required this.isSnoozed,
    required this.lockScreenTitle,
    required this.lockScreenBody,
    required this.inAppTitle,
    required this.inAppBody,
    this.hideDetailsOnLockScreen = true,
  });

  /// Tiêu đề thực tế đẩy ra hệ thống thông báo thiết bị.
  String get systemNotificationTitle =>
      hideDetailsOnLockScreen ? lockScreenTitle : inAppTitle;

  /// Nội dung thực tế đẩy ra hệ thống thông báo thiết bị.
  String get systemNotificationBody =>
      hideDetailsOnLockScreen ? lockScreenBody : inAppBody;

  /// Dấu vân tay cấu hình để đối chiếu tránh đặt lại thừa khi không có thay đổi.
  String get scheduleFingerprint =>
      '$ownerUid|$itemId|${effectiveScheduledAtUtc.toUtc().toIso8601String()}|'
      '$timezoneName|$systemNotificationTitle|$systemNotificationBody';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ScheduledReminder &&
            other.notificationId == notificationId &&
            other.scheduleFingerprint == scheduleFingerprint &&
            other.deferredByQuietHours == deferredByQuietHours &&
            other.isSnoozed == isSnoozed);
  }

  @override
  int get hashCode => Object.hash(
    notificationId,
    scheduleFingerprint,
    deferredByQuietHours,
    isSnoozed,
  );
}

/// Đại diện thông báo đang chờ trên hệ điều hành (đọc từ `pendingNotificationRequests`).
class PendingDeviceNotification {
  final int notificationId;
  final String? ownerUid;
  final String? itemId;
  final String? dedupeKey;
  final String? fingerprint;
  final String? timezoneName;
  final DateTime? scheduledAtUtc;

  const PendingDeviceNotification({
    required this.notificationId,
    this.ownerUid,
    this.itemId,
    this.dedupeKey,
    this.fingerprint,
    this.timezoneName,
    this.scheduledAtUtc,
  });
}

/// Bản ghi token thiết bị ánh xạ bảng `public.device_tokens` trong Supabase.
class DeviceTokenRecord {
  final String id;
  final String ownerUid;
  final String token;

  /// Giá trị hợp lệ theo check constraint DB: `'android' | 'ios' | 'web'`.
  final String platform;
  final bool isActive;
  final DateTime? updatedAt;

  const DeviceTokenRecord({
    required this.id,
    required this.ownerUid,
    required this.token,
    required this.platform,
    this.isActive = true,
    this.updatedAt,
  });

  DeviceTokenRecord copyWith({bool? isActive, DateTime? updatedAt}) {
    return DeviceTokenRecord(
      id: id,
      ownerUid: ownerUid,
      token: token,
      platform: platform,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory DeviceTokenRecord.fromSupabaseMap(Map<String, dynamic> map) {
    return DeviceTokenRecord(
      id: map['id'] as String,
      ownerUid: map['owner_uid'] as String,
      token: map['token'] as String,
      platform: map['platform'] as String,
      isActive: map['is_active'] as bool? ?? true,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
    );
  }
}
