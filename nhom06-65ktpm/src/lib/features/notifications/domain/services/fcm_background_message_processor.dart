import '../entities/reminder_preferences.dart';
import '../entities/scheduled_reminder.dart';
import '../logic/notification_privacy_formatter.dart';
import '../logic/reminder_scheduler_engine.dart';
import '../repositories/fcm_messaging_gateway.dart';
import '../repositories/local_notification_gateway.dart';
import '../repositories/notification_background_state_store.dart';

/// Kết quả xử lý một sự kiện FCM data-only ở chế độ background / terminated (hoặc foreground).
enum FcmHandleOutcome {
  dispatched,
  skippedSystemNotificationAlreadyShown,
  rejectedNoActiveSession,
  rejectedForeignOwner,
  rejectedNotApproved,
  suppressedDisabled,
  suppressedQuietHours,
  suppressedDuplicate,
  suppressedNoPermission,
}

/// Bộ xử lý tập trung cho thông báo FCM data-only ở background / terminated (Issue #6).
///
/// Bảo đảm dù ứng dụng đang ở nền hay đã bị đóng hoàn toàn:
/// 1. Nếu server lỡ gửi kèm khối `notification` (`hasSystemNotificationPayload`), không phát đúp.
/// 2. Đối chiếu chặt `ownerUid` với phiên đang hoạt động; bỏ qua ngay sau khi đăng xuất/đổi tài khoản.
/// 3. Chỉ chấp nhận lịch đã duyệt (`approved`) nếu payload có trạng thái.
/// 4. Tôn trọng `remindersEnabled` và giờ yên lặng (`22:00–07:00` lẫn ca đêm `08:00–15:00`) theo múi giờ IANA.
/// 5. Chống trùng Local ↔ FCM hai lớp:
///    - Đối chiếu danh sách nhắc cục bộ đang chờ trên thiết bị (`pendingNotifications()`).
///    - Đối chiếu sổ chống trùng bền vững chia sẻ qua SQLite giữa UI isolate và background isolate.
/// 6. Luôn hiển thị qua `LocalNotificationGateway` với nội dung trung tính an toàn màn hình khóa
///    (`NotificationVisibility.private`, `hideDetailsOnLockScreen = true`).
class FcmBackgroundMessageProcessor {
  final LocalNotificationGateway gateway;
  final NotificationBackgroundStateStore stateStore;
  final Duration dedupeWindow;
  final DateTime Function() _nowProvider;

  FcmBackgroundMessageProcessor({
    required this.gateway,
    required this.stateStore,
    this.dedupeWindow = const Duration(minutes: 15),
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  Future<FcmHandleOutcome> process(
    IncomingFcmMessage message, {
    String? fallbackOwnerUid,
    ReminderPreferences? preferencesOverride,
    bool isBackgroundIsolate = true,
  }) async {
    // 1. Không phát đúp nếu server gửi sai hợp đồng data-only (đính kèm notification block ở nền).
    if (isBackgroundIsolate && message.hasSystemNotificationPayload) {
      return FcmHandleOutcome.skippedSystemNotificationAlreadyShown;
    }

    // 2. Xác minh tài khoản đang hoạt động; ở background isolate, nếu vừa đăng xuất
    //    (`activeOwnerUid == null` trong store) thì chặn ngay để tài khoản cũ không nhận thông báo nền.
    final runtimeState = await stateStore.readRuntimeState();
    final String? resolvedOwnerUid = isBackgroundIsolate
        ? (runtimeState != null ? runtimeState.activeOwnerUid : fallbackOwnerUid)
        : (fallbackOwnerUid ?? runtimeState?.activeOwnerUid);
    if (resolvedOwnerUid == null || resolvedOwnerUid.trim().isEmpty) {
      return FcmHandleOutcome.rejectedNoActiveSession;
    }

    if (message.ownerUid != null &&
        message.ownerUid!.isNotEmpty &&
        message.ownerUid != resolvedOwnerUid) {
      return FcmHandleOutcome.rejectedForeignOwner;
    }

    // 3. Chặn các mục nháp / đã hủy / đã bỏ qua nếu payload có gắn trạng thái.
    if (!message.isApprovedOrUnspecified) {
      return FcmHandleOutcome.rejectedNotApproved;
    }

    // 4. Tôn trọng tắt nhắc và giờ yên lặng đã lưu.
    final nowUtc = _nowProvider().toUtc();
    final prefs = preferencesOverride ?? runtimeState?.toPreferences();
    if (prefs != null) {
      if (!prefs.remindersEnabled) {
        return FcmHandleOutcome.suppressedDisabled;
      }
      if (prefs.isInQuietHours(nowUtc)) {
        return FcmHandleOutcome.suppressedQuietHours;
      }
    }

    await gateway.initialize();
    final dedupeKey = message.effectiveDedupeKey(resolvedOwnerUid);

    // 5a. Nếu đã có Local Notification đang chờ trên thiết bị cho đúng khóa này -> ưu tiên Local,
    //     không phát đúp FCM.
    final pendingOnDevice = await gateway.pendingNotifications();
    final hasMatchingLocalPending = pendingOnDevice.any(
      (pending) =>
          pending.dedupeKey == dedupeKey &&
          (pending.ownerUid == null || pending.ownerUid == resolvedOwnerUid),
    );
    if (hasMatchingLocalPending) {
      return FcmHandleOutcome.suppressedDuplicate;
    }

    // 5b. Chống trùng xuyên isolate (Local vừa phát hoặc FCM gửi lại trong TTL 15 phút).
    final acquired = await stateStore.tryAcquireDedupeKey(
      ownerUid: resolvedOwnerUid,
      dedupeKey: dedupeKey,
      source: NotificationChannelSource.fcm,
      nowUtc: nowUtc,
      window: dedupeWindow,
    );
    if (!acquired) {
      return FcmHandleOutcome.suppressedDuplicate;
    }

    // 6. Kiểm tra quyền thông báo hệ thống & phát nội dung trung tính an toàn màn hình khóa.
    final permission = await gateway.checkPermissionStatus();
    if (!permission.canScheduleLocal) {
      return FcmHandleOutcome.suppressedNoPermission;
    }

    final syntheticItemId =
        (message.itemId != null && message.itemId!.isNotEmpty)
        ? message.itemId!
        : (message.messageId ?? 'fcm-${nowUtc.millisecondsSinceEpoch}');
    final reminder = ScheduledReminder(
      notificationId: ReminderSchedulerEngine.stableNotificationId(
        ownerUid: resolvedOwnerUid,
        itemId: syntheticItemId,
      ),
      ownerUid: resolvedOwnerUid,
      planId: message.planId ?? 'fcm-server-event',
      itemId: syntheticItemId,
      itemType: message.itemType,
      dedupeKey: dedupeKey,
      originalScheduledAtUtc: message.scheduledAtUtc ?? nowUtc,
      effectiveScheduledAtUtc: nowUtc,
      timezoneName: prefs?.timezone ?? 'Asia/Ho_Chi_Minh',
      deferredByQuietHours: false,
      isSnoozed: false,
      lockScreenTitle: NotificationPrivacyFormatter.neutralLockScreenTitle,
      lockScreenBody: NotificationPrivacyFormatter.neutralLockScreenBody,
      inAppTitle: 'HealthyLife • ${message.itemType.displayLabel}',
      inAppBody: NotificationPrivacyFormatter.neutralLockScreenBody,
      hideDetailsOnLockScreen: true,
    );

    await gateway.showImmediate(reminder);
    return FcmHandleOutcome.dispatched;
  }
}
