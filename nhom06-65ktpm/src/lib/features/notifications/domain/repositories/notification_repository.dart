import '../entities/approved_plan_reminder_item.dart';
import '../entities/reminder_preferences.dart';
import '../entities/scheduled_reminder.dart';

/// Lỗi đồng bộ tầng dữ liệu của module Nhắc lịch & Giờ yên lặng (Issue #6).
class NotificationSyncException implements Exception {
  final String message;
  final Object? cause;

  const NotificationSyncException(this.message, {this.cause});

  @override
  String toString() => message;
}

/// Xung đột phiên bản khi cấu hình nhắc lịch bị chỉnh sửa đồng thời trên thiết bị khác.
class NotificationConflictException extends NotificationSyncException {
  final int? serverVersion;
  final ReminderPreferences? serverPreferences;

  const NotificationConflictException(
    super.message, {
    this.serverVersion,
    this.serverPreferences,
    super.cause,
  });
}

/// Giao diện kho dữ liệu cho cấu hình nhắc lịch, mục lịch đã duyệt và token thiết bị.
abstract class NotificationRepository {
  Future<ReminderPreferences> getPreferences(String ownerUid);

  Future<ReminderPreferences> savePreferences(
    ReminderPreferences preferences, {
    int? expectedVersion,
  });

  /// Tải toàn bộ mục lịch của tài khoản (gồm cả `approved`, `draft`, `completed`, `skipped`)
  /// để bộ lập lịch tự lọc chặt chỉ đặt nhắc cho mục đã duyệt.
  Future<List<ApprovedPlanReminderItem>> getPlanItems(String ownerUid);

  /// Cập nhật trạng thái hoặc giờ của một mục lịch (dùng khi bỏ qua, sửa hoặc duyệt lịch).
  Future<void> upsertPlanItem(ApprovedPlanReminderItem item);

  /// Xóa mục lịch khỏi danh sách (phải đi kèm hủy thông báo cũ khi đồng bộ lại).
  Future<void> deletePlanItem({
    required String ownerUid,
    required String itemId,
  });

  Future<List<DeviceTokenRecord>> getDeviceTokens(String ownerUid);

  Future<void> registerDeviceToken({
    required String ownerUid,
    required String token,
    required String platform,
  });

  /// Hủy liên kết (`is_active = false`) token thiết bị của tài khoản khi đăng xuất / đổi tài khoản.
  Future<void> deactivateDeviceTokens(String ownerUid, {String? token});
}
