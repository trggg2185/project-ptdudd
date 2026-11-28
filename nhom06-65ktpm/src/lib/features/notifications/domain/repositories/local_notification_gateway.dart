import '../entities/scheduled_reminder.dart';

/// Giao diện trừu tượng cho tầng gửi/lên lịch thông báo cục bộ trên thiết bị.
///
/// Cho phép dùng `FlutterLocalNotificationsGateway` trên Android thật
/// và `InMemoryLocalNotificationGateway` trong kiểm thử đơn vị / widget / chế độ demo.
abstract class LocalNotificationGateway {
  Future<void> initialize();

  Future<NotificationPermissionStatus> checkPermissionStatus();

  Future<NotificationPermissionStatus> requestPermission();

  /// Đặt lịch thông báo cục bộ theo múi giờ IANA của [reminder.timezoneName].
  Future<void> schedule(ScheduledReminder reminder);

  /// Hiển thị ngay một thông báo riêng tư (dùng kiểm thử máy thật hoặc cầu nối FCM foreground).
  Future<void> showImmediate(ScheduledReminder reminder);

  Future<void> cancel(int notificationId);

  /// Hủy toàn bộ thông báo đang chờ và đang hiển thị (bắt buộc gọi khi đăng xuất / đổi tài khoản).
  Future<void> cancelAll();

  Future<List<PendingDeviceNotification>> pendingNotifications();

  /// Phát hiện múi giờ hiện tại của thiết bị (IANA nếu xác định được, mặc định `Asia/Ho_Chi_Minh`).
  Future<String> detectDeviceTimezone();
}
