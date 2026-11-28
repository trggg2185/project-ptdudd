import '../entities/reminder_preferences.dart';
import '../entities/scheduled_reminder.dart';

/// Ảnh chụp cấu hình kỹ thuật tối thiểu được chia sẻ giữa UI isolate và FCM background isolate.
///
/// Tuyệt đối KHÔNG lưu dữ liệu sức khỏe nhạy cảm, tên hoạt động hay tọa độ GPS — chỉ giữ
/// `activeOwnerUid` và cấu hình bật/tắt, khung giờ yên lặng và múi giờ IANA.
class NotificationRuntimeState {
  final String? activeOwnerUid;
  final bool remindersEnabled;
  final int? quietHoursStartMinute;
  final int? quietHoursEndMinute;
  final String timezone;
  final DateTime updatedAtUtc;

  const NotificationRuntimeState({
    required this.activeOwnerUid,
    required this.remindersEnabled,
    required this.quietHoursStartMinute,
    required this.quietHoursEndMinute,
    required this.timezone,
    required this.updatedAtUtc,
  });

  factory NotificationRuntimeState.fromPreferences(
    ReminderPreferences preferences, {
    required DateTime updatedAtUtc,
  }) {
    return NotificationRuntimeState(
      activeOwnerUid: preferences.ownerUid,
      remindersEnabled: preferences.remindersEnabled,
      quietHoursStartMinute: preferences.quietHoursStartMinute,
      quietHoursEndMinute: preferences.quietHoursEndMinute,
      timezone: preferences.timezone,
      updatedAtUtc: updatedAtUtc.toUtc(),
    );
  }

  ReminderPreferences? toPreferences() {
    final uid = activeOwnerUid;
    if (uid == null || uid.trim().isEmpty) return null;
    return ReminderPreferences(
      ownerUid: uid,
      remindersEnabled: remindersEnabled,
      quietHoursStartMinute: quietHoursStartMinute,
      quietHoursEndMinute: quietHoursEndMinute,
      timezone: timezone,
    );
  }
}

/// Kho lưu bền vững trạng thái runtime & khóa chống trùng Local ↔ FCM giữa các isolate
/// (UI isolate và background/terminated isolate của `FirebaseMessaging.onBackgroundMessage`).
abstract class NotificationBackgroundStateStore {
  Future<void> saveRuntimeState(NotificationRuntimeState state);

  Future<NotificationRuntimeState?> readRuntimeState();

  /// Kiểm tra & chiếm khóa chống trùng `(ownerUid, dedupeKey)` trong cửa sổ [window].
  /// Trả `true` nếu chưa bị phát gần đây; `false` nếu bị trùng Local ↔ FCM.
  Future<bool> tryAcquireDedupeKey({
    required String ownerUid,
    required String dedupeKey,
    required NotificationChannelSource source,
    required DateTime nowUtc,
    Duration window = const Duration(minutes: 15),
  });

  /// Ghi nhận khóa đã phát (dùng khi Local Notification vừa phát để chặn FCM đến trễ ở background).
  Future<void> recordDispatchedKey({
    required String ownerUid,
    required String dedupeKey,
    required NotificationChannelSource source,
    required DateTime nowUtc,
  });

  /// Xóa sạch khóa chống trùng và trạng thái phiên của tài khoản cũ khi đăng xuất / đổi tài khoản.
  Future<void> clearForOwner(String ownerUid);
}
