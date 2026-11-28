import '../entities/approved_plan_reminder_item.dart';
import '../entities/reminder_preferences.dart';
import '../entities/scheduled_reminder.dart';
import 'notification_privacy_formatter.dart';

/// Kết quả tính toán đối chiếu giữa trạng thái lịch hiện tại và thông báo đang chờ trên thiết bị.
class ReminderReconcilePlan {
  /// Các ID thông báo cũ cần hủy (mục đã xóa/đổi giờ/bỏ qua/hoàn thành, đổi múi giờ,
  /// tắt nhắc lịch hoặc thuộc tài khoản cũ khác `ownerUid`).
  final List<int> notificationIdsToCancel;

  /// Các lời nhắc hợp lệ cần đặt lịch mới hoặc đặt lại trên thiết bị.
  final List<ScheduledReminder> remindersToSchedule;

  /// Toàn bộ lời nhắc mục tiêu sau đối chiếu (bao gồm cả mục đã khớp sẵn chưa cần đặt lại).
  final List<ScheduledReminder> desiredReminders;

  /// Đánh dấu có sự thay đổi múi giờ so với lần đồng bộ trước.
  final bool timezoneChanged;

  /// Số mục nháp / chưa duyệt bị bỏ qua đúng quy tắc nghiệp vụ.
  final int skippedUnapprovedCount;

  /// Số mục bị lùi giờ vì rơi vào giờ yên lặng.
  final int deferredByQuietHoursCount;

  const ReminderReconcilePlan({
    required this.notificationIdsToCancel,
    required this.remindersToSchedule,
    required this.desiredReminders,
    required this.timezoneChanged,
    required this.skippedUnapprovedCount,
    required this.deferredByQuietHoursCount,
  });
}

/// Bộ máy lập lịch & đối chiếu nhắc cục bộ thuần Dart (100% kiểm thử được không phụ thuộc nền tảng).
///
/// Bảo đảm toàn bộ tiêu chí nghiệp vụ của Issue #6:
/// 1. Chỉ đặt nhắc cho mục thuộc lịch **đã duyệt** (`planStatus == approved && itemStatus == approved`).
/// 2. Đổi giờ / xóa / hoàn thành / bỏ qua mục lịch → tự động đưa ID cũ vào danh sách hủy.
/// 3. ID thông báo xác định theo hàm băm ổn định `(ownerUid, itemId)` → chống trùng khi chạy lại.
/// 4. Tôn trọng **giờ yên lặng** (cả qua đêm `22:00–07:00` lẫn ca đêm ban ngày `08:00–15:00`) cho cả nhắc thường và tạm hoãn (snooze).
/// 5. Phát hiện **đổi múi giờ** hoặc **khôi phục sau khởi động lại** (`forceReschedule: true`) → hủy nhắc cũ và đặt lại toàn bộ theo múi giờ mới.
/// 6. Luôn hủy mọi thông báo đang chờ thuộc tài khoản khác (`pending.ownerUid != ownerUid`).
/// 7. Nội dung màn hình khóa luôn qua [NotificationPrivacyFormatter], không lộ chi tiết sức khỏe.
class ReminderSchedulerEngine {
  /// Sinh ID thông báo 31-bit dương ổn định (FNV-1a) cho cặp `(ownerUid, itemId)`.
  static int stableNotificationId({
    required String ownerUid,
    required String itemId,
  }) {
    const int fnvOffsetBasis = 0x811c9dc5;
    const int fnvPrime = 0x01000193;
    var hash = fnvOffsetBasis;
    final key = '$ownerUid::$itemId';
    for (final codeUnit in key.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0x7fffffff;
    }
    // Tránh giá trị 0 vì một số API Android không cho ID = 0.
    return hash == 0 ? 1 : hash;
  }

  /// Tính thời điểm tạm hoãn (snooze) có tôn trọng giờ yên lặng theo múi giờ người dùng.
  static ({DateTime effectiveUtc, bool deferredByQuietHours}) computeSnoozeTime({
    required DateTime nowUtc,
    required int snoozeMinutes,
    required ReminderPreferences preferences,
  }) {
    if (snoozeMinutes < 1 || snoozeMinutes > 240) {
      throw ArgumentError.value(
        snoozeMinutes,
        'snoozeMinutes',
        'Thời gian tạm hoãn phải từ 1 đến 240 phút.',
      );
    }
    final rawTarget = nowUtc.toUtc().add(Duration(minutes: snoozeMinutes));
    final adjusted = preferences.adjustForQuietHours(rawTarget);
    return (
      effectiveUtc: adjusted.effectiveUtc,
      deferredByQuietHours: adjusted.deferred,
    );
  }

  /// Đối chiếu danh sách lịch hiện tại với danh sách thông báo đang chờ trên thiết bị.
  static ReminderReconcilePlan reconcile({
    required String ownerUid,
    required ReminderPreferences preferences,
    required List<ApprovedPlanReminderItem> planItems,
    required List<PendingDeviceNotification> pendingOnDevice,
    required DateTime nowUtc,
    Map<String, DateTime> activeSnoozesUtc = const {},
    String? previousTimezone,
    bool forceReschedule = false,
  }) {
    final normalizedNow = nowUtc.toUtc();
    final timezoneChanged =
        previousTimezone != null &&
        previousTimezone.isNotEmpty &&
        previousTimezone != preferences.timezone;

    final pendingById = <int, PendingDeviceNotification>{
      for (final p in pendingOnDevice) p.notificationId: p,
    };

    var skippedUnapproved = 0;
    var deferredCount = 0;
    final desiredById = <int, ScheduledReminder>{};

    if (preferences.remindersEnabled) {
      for (final item in planItems) {
        if (item.ownerUid != ownerUid) continue;
        if (!item.isEligibleForReminder) {
          skippedUnapproved++;
          continue;
        }

        final snoozedUntil = activeSnoozesUtc[item.itemId]?.toUtc();
        final bool isSnoozed =
            snoozedUntil != null && snoozedUntil.isAfter(normalizedNow);
        final DateTime candidateUtc = isSnoozed
            ? snoozedUntil
            : item.startsAtUtc;

        final adjusted = preferences.adjustForQuietHours(candidateUtc);
        if (!adjusted.effectiveUtc.isAfter(normalizedNow)) {
          // Bỏ qua các mục đã qua thời điểm thực hiện.
          continue;
        }
        if (adjusted.deferred) {
          deferredCount++;
        }

        final copy = NotificationPrivacyFormatter.format(
          item,
          isSnoozed: isSnoozed,
          deferredByQuietHours: adjusted.deferred,
        );

        final id = stableNotificationId(
          ownerUid: ownerUid,
          itemId: item.itemId,
        );
        desiredById[id] = ScheduledReminder(
          notificationId: id,
          ownerUid: ownerUid,
          planId: item.planId,
          itemId: item.itemId,
          itemType: item.itemType,
          dedupeKey: item.dedupeKey,
          originalScheduledAtUtc: item.startsAtUtc,
          effectiveScheduledAtUtc: adjusted.effectiveUtc,
          timezoneName: preferences.timezone,
          deferredByQuietHours: adjusted.deferred,
          isSnoozed: isSnoozed,
          lockScreenTitle: copy.lockScreenTitle,
          lockScreenBody: copy.lockScreenBody,
          inAppTitle: copy.inAppTitle,
          inAppBody: copy.inAppBody,
          hideDetailsOnLockScreen: preferences.hideHealthDetailsOnLockScreen,
        );
      }
    } else {
      for (final item in planItems) {
        if (item.ownerUid == ownerUid && !item.isEligibleForReminder) {
          skippedUnapproved++;
        }
      }
    }

    final idsToCancel = <int>{};
    final toSchedule = <ScheduledReminder>[];

    // 1. Hủy mọi thông báo cũ không còn nằm trong tập mục tiêu, thuộc tài khoản khác,
    //    đã đổi múi giờ, hoặc đã thay đổi giờ / nội dung / yêu cầu đặt lại.
    for (final pending in pendingOnDevice) {
      final isForeignAccount =
          pending.ownerUid != null && pending.ownerUid != ownerUid;
      final desired = desiredById[pending.notificationId];
      if (isForeignAccount ||
          desired == null ||
          timezoneChanged ||
          forceReschedule ||
          pending.fingerprint != desired.scheduleFingerprint) {
        idsToCancel.add(pending.notificationId);
      }
    }

    // 2. Đặt lịch cho mọi mục mới hoặc mục vừa phải hủy để đặt lại.
    final sortedDesired = desiredById.values.toList()
      ..sort(
        (a, b) => a.effectiveScheduledAtUtc.compareTo(
          b.effectiveScheduledAtUtc,
        ),
      );
    for (final reminder in sortedDesired) {
      final existing = pendingById[reminder.notificationId];
      final needsSchedule =
          existing == null ||
          idsToCancel.contains(reminder.notificationId) ||
          timezoneChanged ||
          forceReschedule ||
          existing.fingerprint != reminder.scheduleFingerprint;
      if (needsSchedule) {
        toSchedule.add(reminder);
      }
    }

    return ReminderReconcilePlan(
      notificationIdsToCancel: idsToCancel.toList()..sort(),
      remindersToSchedule: toSchedule,
      desiredReminders: sortedDesired,
      timezoneChanged: timezoneChanged,
      skippedUnapprovedCount: skippedUnapproved,
      deferredByQuietHoursCount: deferredCount,
    );
  }
}
