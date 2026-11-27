import '../../../profile/domain/profile_time.dart';
import '../../domain/entities/scheduled_reminder.dart';
import '../../domain/repositories/local_notification_gateway.dart';

/// Gateway thông báo cục bộ In-Memory phục vụ unit/widget test và chế độ demo ngoại tuyến.
///
/// Cho phép mô phỏng đầy đủ các tình huống thực tế của Issue #6:
/// - Từ chối/thu hồi quyền thông báo (`permissionStatus`)
/// - Đổi múi giờ thiết bị (`deviceTimezone`)
/// - Khởi động lại thiết bị làm mất lịch chờ trong hệ điều hành (`simulateDeviceReboot`)
/// - Theo dõi chính xác danh sách thông báo đang chờ, đã hủy và đã phát.
class InMemoryLocalNotificationGateway implements LocalNotificationGateway {
  NotificationPermissionStatus permissionStatus;
  NotificationPermissionStatus permissionStatusAfterRequest;
  String deviceTimezone;

  final Map<int, ScheduledReminder> _scheduledById = {};
  final List<ScheduledReminder> shownReminders = [];
  final List<int> canceledIds = [];
  int cancelAllCallCount = 0;
  int scheduleCallCount = 0;
  bool initialized = false;

  InMemoryLocalNotificationGateway({
    this.permissionStatus = NotificationPermissionStatus.granted,
    this.permissionStatusAfterRequest = NotificationPermissionStatus.granted,
    this.deviceTimezone = defaultProfileZone,
  });

  List<ScheduledReminder> get scheduledReminders =>
      List.unmodifiable(_scheduledById.values);

  /// Mô phỏng khởi động lại thiết bị khiến hàng đợi alarm trong RAM hệ điều hành bị xóa sạch.
  void simulateDeviceReboot() {
    _scheduledById.clear();
  }

  /// Mô phỏng người dùng tắt quyền thông báo trong Cài đặt Android.
  void simulatePermissionRevoked({bool permanently = false}) {
    permissionStatus = permanently
        ? NotificationPermissionStatus.permanentlyDenied
        : NotificationPermissionStatus.denied;
  }

  /// Mô phỏng thiết bị chuyển sang múi giờ mới (ví dụ bay sang `Asia/Tokyo`).
  void simulateTimezoneChange(String newIanaTimezone) {
    deviceTimezone = newIanaTimezone;
  }

  @override
  Future<void> initialize() async {
    profileLocation(defaultProfileZone);
    initialized = true;
  }

  @override
  Future<NotificationPermissionStatus> checkPermissionStatus() async =>
      permissionStatus;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    if (permissionStatus == NotificationPermissionStatus.unsupportedPlatform) {
      return permissionStatus;
    }
    permissionStatus = permissionStatusAfterRequest;
    return permissionStatus;
  }

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    scheduleCallCount++;
    _scheduledById[reminder.notificationId] = reminder;
  }

  @override
  Future<void> showImmediate(ScheduledReminder reminder) async {
    shownReminders.add(reminder);
  }

  @override
  Future<void> cancel(int notificationId) async {
    canceledIds.add(notificationId);
    _scheduledById.remove(notificationId);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCallCount++;
    _scheduledById.clear();
  }

  @override
  Future<List<PendingDeviceNotification>> pendingNotifications() async {
    return _scheduledById.values
        .map(
          (r) => PendingDeviceNotification(
            notificationId: r.notificationId,
            ownerUid: r.ownerUid,
            itemId: r.itemId,
            dedupeKey: r.dedupeKey,
            fingerprint: r.scheduleFingerprint,
            timezoneName: r.timezoneName,
            scheduledAtUtc: r.effectiveScheduledAtUtc,
          ),
        )
        .toList();
  }

  @override
  Future<String> detectDeviceTimezone() async => deviceTimezone;
}
