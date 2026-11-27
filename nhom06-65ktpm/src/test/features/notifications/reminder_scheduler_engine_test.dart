import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/notifications/domain/entities/approved_plan_reminder_item.dart';
import 'package:healthylife/features/notifications/domain/entities/reminder_preferences.dart';
import 'package:healthylife/features/notifications/domain/entities/scheduled_reminder.dart';
import 'package:healthylife/features/notifications/domain/logic/notification_deduplicator.dart';
import 'package:healthylife/features/notifications/domain/logic/notification_privacy_formatter.dart';
import 'package:healthylife/features/notifications/domain/logic/reminder_scheduler_engine.dart';
import 'package:healthylife/features/profile/domain/profile_time.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  const userA = 'firebase-user-a';
  const userB = 'firebase-user-b';

  DateTime vnClockToUtc(int year, int month, int day, int hour, int minute) {
    final loc = profileLocation('Asia/Ho_Chi_Minh')!;
    return tz.TZDateTime(loc, year, month, day, hour, minute).toUtc();
  }

  group('ReminderPreferences & Quiet Hours Tests', () {
    test('giờ yên lặng qua đêm (22:00–07:00) tự lùi mục 22:30 sang 07:00 hôm sau và 03:15 sang 07:00 cùng ngày', () {
      const prefs = ReminderPreferences(
        ownerUid: userA,
        quietHoursStartMinute: 22 * 60,
        quietHoursEndMinute: 7 * 60,
        timezone: 'Asia/Ho_Chi_Minh',
      );

      final lateNight = vnClockToUtc(2026, 11, 28, 22, 30);
      final lateAdjusted = prefs.adjustForQuietHours(lateNight);
      expect(lateAdjusted.deferred, isTrue);
      expect(
        lateAdjusted.effectiveUtc,
        equals(vnClockToUtc(2026, 11, 29, 7, 0)),
      );

      final earlyMorning = vnClockToUtc(2026, 11, 29, 3, 15);
      final earlyAdjusted = prefs.adjustForQuietHours(earlyMorning);
      expect(earlyAdjusted.deferred, isTrue);
      expect(
        earlyAdjusted.effectiveUtc,
        equals(vnClockToUtc(2026, 11, 29, 7, 0)),
      );

      final normalDaytime = vnClockToUtc(2026, 11, 28, 17, 30);
      final normalAdjusted = prefs.adjustForQuietHours(normalDaytime);
      expect(normalAdjusted.deferred, isFalse);
      expect(normalAdjusted.effectiveUtc, equals(normalDaytime));
    });

    test('giờ yên lặng ca đêm ngủ ban ngày (08:00–15:00) lùi mục 10:30 sang 15:00 và giữ nguyên mục 23:30', () {
      const shiftPrefs = ReminderPreferences(
        ownerUid: userA,
        quietHoursStartMinute: 8 * 60,
        quietHoursEndMinute: 15 * 60,
        timezone: 'Asia/Ho_Chi_Minh',
      );

      final daytimeSlot = vnClockToUtc(2026, 11, 28, 10, 30);
      final deferred = shiftPrefs.adjustForQuietHours(daytimeSlot);
      expect(deferred.deferred, isTrue);
      expect(deferred.effectiveUtc, equals(vnClockToUtc(2026, 11, 28, 15, 0)));

      final nightShiftSlot = vnClockToUtc(2026, 11, 28, 23, 30);
      final untouched = shiftPrefs.adjustForQuietHours(nightShiftSlot);
      expect(untouched.deferred, isFalse);
      expect(untouched.effectiveUtc, equals(nightShiftSlot));
    });

    test('giờ yên lặng xử lý an toàn qua mốc chuyển đổi DST tại America/New_York', () {
      const nyPrefs = ReminderPreferences(
        ownerUid: userA,
        quietHoursStartMinute: 22 * 60,
        quietHoursEndMinute: 7 * 60,
        timezone: 'America/New_York',
      );
      final nyLoc = profileLocation('America/New_York')!;
      // Đêm trước ngày đổi giờ mùa hè (2026-03-08 02:00 nhảy lên 03:00 EDT)
      final beforeSpringForward = tz.TZDateTime(nyLoc, 2026, 3, 7, 23, 0).toUtc();
      final adjusted = nyPrefs.adjustForQuietHours(beforeSpringForward);
      final adjustedLocal = tz.TZDateTime.from(adjusted.effectiveUtc, nyLoc);
      expect(adjusted.deferred, isTrue);
      expect(adjustedLocal.year, 2026);
      expect(adjustedLocal.month, 3);
      expect(adjustedLocal.day, 8);
      expect(adjustedLocal.hour, 7);
      expect(adjustedLocal.minute, 0);
    });

    test('tạm hoãn (snooze) rơi vào giờ yên lặng sẽ tự đẩy ra sau giờ kết thúc yên lặng', () {
      const prefs = ReminderPreferences(
        ownerUid: userA,
        quietHoursStartMinute: 22 * 60,
        quietHoursEndMinute: 7 * 60,
        timezone: 'Asia/Ho_Chi_Minh',
      );

      final nowAt2155 = vnClockToUtc(2026, 11, 28, 21, 55);
      final snoozed = ReminderSchedulerEngine.computeSnoozeTime(
        nowUtc: nowAt2155,
        snoozeMinutes: 15,
        preferences: prefs,
      );
      expect(snoozed.deferredByQuietHours, isTrue);
      expect(snoozed.effectiveUtc, equals(vnClockToUtc(2026, 11, 29, 7, 0)));
    });

    test('ReminderPreferences ánh xạ đúng định dạng Postgres time và kiểm tra dữ liệu hợp lệ', () {
      const prefs = ReminderPreferences(
        ownerUid: userA,
        remindersEnabled: true,
        quietHoursStartMinute: 22 * 60 + 30,
        quietHoursEndMinute: 6 * 60 + 45,
        timezone: 'Asia/Tokyo',
        version: 3,
      );
      final map = prefs.toSupabaseMap();
      expect(map['quiet_hours_start'], '22:30:00');
      expect(map['quiet_hours_end'], '06:45:00');
      expect(map['timezone'], 'Asia/Tokyo');
      expect(map['version'], 3);

      final restored = ReminderPreferences.fromSupabaseMap(map);
      expect(restored.quietHoursStartMinute, 22 * 60 + 30);
      expect(restored.quietHoursEndMinute, 6 * 60 + 45);
      expect(restored.timezone, 'Asia/Tokyo');
      expect(restored.version, 3);

      expect(
        () => const ReminderPreferences(
          ownerUid: userA,
          timezone: 'Invalid/Zone',
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => const ReminderPreferences(
          ownerUid: userA,
          quietHoursStartMinute: 22 * 60,
          quietHoursEndMinute: 22 * 60,
        ).validate(),
        throwsFormatException,
      );
    });
  });

  group('ReminderSchedulerEngine Reconciliation Tests', () {
    test('chỉ đặt nhắc cho lịch đã duyệt (approved), bỏ qua draft/completed/skipped và mục quá khứ', () {
      final now = vnClockToUtc(2026, 11, 28, 8, 0);
      const prefs = ReminderPreferences(
        ownerUid: userA,
        quietHoursStartMinute: 22 * 60,
        quietHoursEndMinute: 7 * 60,
        timezone: 'Asia/Ho_Chi_Minh',
      );
      final items = [
        ApprovedPlanReminderItem(
          itemId: 'approved-future',
          planId: 'plan-1',
          ownerUid: userA,
          itemType: ReminderItemType.exercise,
          title: 'Đi bộ chiều',
          startsAt: vnClockToUtc(2026, 11, 28, 17, 30),
          planStatus: PlanApprovalStatus.approved,
          itemStatus: PlanItemStatus.approved,
        ),
        ApprovedPlanReminderItem(
          itemId: 'draft-plan-item',
          planId: 'plan-draft',
          ownerUid: userA,
          itemType: ReminderItemType.meal,
          title: 'Bữa trưa nháp',
          startsAt: vnClockToUtc(2026, 11, 28, 12, 0),
          planStatus: PlanApprovalStatus.draft,
          itemStatus: PlanItemStatus.approved,
        ),
        ApprovedPlanReminderItem(
          itemId: 'draft-item-in-approved-plan',
          planId: 'plan-1',
          ownerUid: userA,
          itemType: ReminderItemType.habit,
          title: 'Mục nháp',
          startsAt: vnClockToUtc(2026, 11, 28, 13, 0),
          planStatus: PlanApprovalStatus.approved,
          itemStatus: PlanItemStatus.draft,
        ),
        ApprovedPlanReminderItem(
          itemId: 'completed-item',
          planId: 'plan-1',
          ownerUid: userA,
          itemType: ReminderItemType.habit,
          title: 'Đã hoàn thành',
          startsAt: vnClockToUtc(2026, 11, 28, 14, 0),
          planStatus: PlanApprovalStatus.approved,
          itemStatus: PlanItemStatus.completed,
        ),
        ApprovedPlanReminderItem(
          itemId: 'past-approved-item',
          planId: 'plan-1',
          ownerUid: userA,
          itemType: ReminderItemType.habit,
          title: 'Đã qua giờ',
          startsAt: vnClockToUtc(2026, 11, 28, 7, 30),
          planStatus: PlanApprovalStatus.approved,
          itemStatus: PlanItemStatus.approved,
        ),
      ];

      final plan = ReminderSchedulerEngine.reconcile(
        ownerUid: userA,
        preferences: prefs,
        planItems: items,
        pendingOnDevice: const [],
        nowUtc: now,
      );

      expect(plan.remindersToSchedule, hasLength(1));
      expect(plan.remindersToSchedule.single.itemId, 'approved-future');
      expect(plan.skippedUnapprovedCount, 3);
    });

    test('đổi giờ hoặc xóa mục lịch hủy đúng ID cũ, chạy lại không tạo trùng (idempotent)', () {
      final now = vnClockToUtc(2026, 11, 28, 8, 0);
      const prefs = ReminderPreferences(
        ownerUid: userA,
        quietHoursStartMinute: null,
        quietHoursEndMinute: null,
        timezone: 'Asia/Ho_Chi_Minh',
      );
      final item1 = ApprovedPlanReminderItem(
        itemId: 'item-1',
        planId: 'plan-1',
        ownerUid: userA,
        itemType: ReminderItemType.exercise,
        title: 'Chạy bộ nhẹ',
        startsAt: vnClockToUtc(2026, 11, 28, 17, 0),
        planStatus: PlanApprovalStatus.approved,
        itemStatus: PlanItemStatus.approved,
      );
      final item2 = ApprovedPlanReminderItem(
        itemId: 'item-2',
        planId: 'plan-1',
        ownerUid: userA,
        itemType: ReminderItemType.habit,
        title: 'Uống nước',
        startsAt: vnClockToUtc(2026, 11, 28, 10, 0),
        planStatus: PlanApprovalStatus.approved,
        itemStatus: PlanItemStatus.approved,
      );

      final initial = ReminderSchedulerEngine.reconcile(
        ownerUid: userA,
        preferences: prefs,
        planItems: [item1, item2],
        pendingOnDevice: const [],
        nowUtc: now,
      );
      expect(initial.remindersToSchedule, hasLength(2));

      final pending = initial.desiredReminders
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

      // Chạy đối chiếu lại khi không đổi gì -> không hủy, không đặt lại thừa
      final idempotent = ReminderSchedulerEngine.reconcile(
        ownerUid: userA,
        preferences: prefs,
        planItems: [item1, item2],
        pendingOnDevice: pending,
        nowUtc: now,
      );
      expect(idempotent.notificationIdsToCancel, isEmpty);
      expect(idempotent.remindersToSchedule, isEmpty);

      // Xóa item2 và đổi giờ item1 từ 17:00 -> 18:00
      final item1Moved = item1.copyWith(
        startsAt: vnClockToUtc(2026, 11, 28, 18, 0),
      );
      final updated = ReminderSchedulerEngine.reconcile(
        ownerUid: userA,
        preferences: prefs,
        planItems: [item1Moved],
        pendingOnDevice: pending,
        nowUtc: now,
      );

      final id1 = ReminderSchedulerEngine.stableNotificationId(
        ownerUid: userA,
        itemId: 'item-1',
      );
      final id2 = ReminderSchedulerEngine.stableNotificationId(
        ownerUid: userA,
        itemId: 'item-2',
      );
      expect(updated.notificationIdsToCancel, containsAll([id1, id2]));
      expect(updated.remindersToSchedule, hasLength(1));
      expect(updated.remindersToSchedule.single.notificationId, id1);
      expect(
        updated.remindersToSchedule.single.effectiveScheduledAtUtc,
        equals(vnClockToUtc(2026, 11, 28, 18, 0)),
      );
    });

    test('đổi múi giờ và thông báo thuộc tài khoản cũ đều bị hủy và đặt lại sạch sẽ', () {
      final now = vnClockToUtc(2026, 11, 28, 8, 0);
      final foreignPendingId = ReminderSchedulerEngine.stableNotificationId(
        ownerUid: userB,
        itemId: 'foreign-item',
      );
      final ownId = ReminderSchedulerEngine.stableNotificationId(
        ownerUid: userA,
        itemId: 'item-tz',
      );
      final item = ApprovedPlanReminderItem(
        itemId: 'item-tz',
        planId: 'plan-1',
        ownerUid: userA,
        itemType: ReminderItemType.habit,
        title: 'Giãn cơ',
        startsAt: vnClockToUtc(2026, 11, 28, 16, 0),
        planStatus: PlanApprovalStatus.approved,
        itemStatus: PlanItemStatus.approved,
      );

      final plan = ReminderSchedulerEngine.reconcile(
        ownerUid: userA,
        preferences: const ReminderPreferences(
          ownerUid: userA,
          timezone: 'Asia/Tokyo',
        ),
        planItems: [item],
        pendingOnDevice: [
          PendingDeviceNotification(
            notificationId: foreignPendingId,
            ownerUid: userB,
            itemId: 'foreign-item',
          ),
          PendingDeviceNotification(
            notificationId: ownId,
            ownerUid: userA,
            itemId: 'item-tz',
            timezoneName: 'Asia/Ho_Chi_Minh',
          ),
        ],
        nowUtc: now,
        previousTimezone: 'Asia/Ho_Chi_Minh',
      );

      expect(plan.timezoneChanged, isTrue);
      expect(plan.notificationIdsToCancel, containsAll([foreignPendingId, ownId]));
      expect(plan.remindersToSchedule.single.timezoneName, 'Asia/Tokyo');
    });
  });

  group('Lock-Screen Privacy & Local/FCM Deduplication Tests', () {
    test('màn hình khóa tuyệt đối không lộ dữ liệu sức khỏe, dị ứng, chỉ số hay tọa độ GPS', () {
      final sensitiveItem = ApprovedPlanReminderItem(
        itemId: 'sensitive-1',
        planId: 'plan-1',
        ownerUid: userA,
        itemType: ReminderItemType.meal,
        title:
            'Uống thuốc huyết áp 140/90 mmHg, tránh dị ứng đậu phộng, mục tiêu 62 kg, 10.7626, 106.6601',
        startsAt: vnClockToUtc(2026, 11, 28, 12, 0),
        planStatus: PlanApprovalStatus.approved,
        itemStatus: PlanItemStatus.approved,
      );

      final copy = NotificationPrivacyFormatter.format(
        sensitiveItem,
        isSnoozed: false,
        deferredByQuietHours: false,
      );

      expect(
        NotificationPrivacyFormatter.containsSensitiveHealthInfo(
          copy.lockScreenTitle,
        ),
        isFalse,
      );
      expect(
        NotificationPrivacyFormatter.containsSensitiveHealthInfo(
          copy.lockScreenBody,
        ),
        isFalse,
      );
      expect(copy.lockScreenBody, isNot(contains('huyết áp')));
      expect(copy.lockScreenBody, isNot(contains('dị ứng')));
      expect(copy.lockScreenBody, isNot(contains('62 kg')));
      expect(copy.lockScreenBody, isNot(contains('10.7626')));
      // Ngay cả inAppBody cũng tự ẩn chuỗi nhạy cảm
      expect(
        NotificationPrivacyFormatter.containsSensitiveHealthInfo(
          copy.inAppBody,
        ),
        isFalse,
      );
    });

    test('NotificationDeduplicator chặn phát trùng Local ↔ FCM trong cửa sổ TTL và cô lập theo tài khoản', () {
      final dedupe = NotificationDeduplicator(
        dedupeWindow: const Duration(minutes: 15),
      );
      final t0 = DateTime.utc(2026, 11, 28, 10, 0);
      const key = '$userA:exercise:item-1:2026-11-28T10:00:00.000Z';

      // Local phát trước -> hợp lệ
      expect(
        dedupe.tryAcquire(
          ownerUid: userA,
          dedupeKey: key,
          source: NotificationChannelSource.local,
          nowUtc: t0,
        ),
        isTrue,
      );

      // FCM tới sau 2 phút với cùng khóa -> bị chặn trùng
      expect(
        dedupe.tryAcquire(
          ownerUid: userA,
          dedupeKey: key,
          source: NotificationChannelSource.fcm,
          nowUtc: t0.add(const Duration(minutes: 2)),
        ),
        isFalse,
      );

      // Tài khoản khác không bị ảnh hưởng
      expect(
        dedupe.tryAcquire(
          ownerUid: userB,
          dedupeKey: key,
          source: NotificationChannelSource.fcm,
          nowUtc: t0.add(const Duration(minutes: 2)),
        ),
        isTrue,
      );

      // Sau khi hết TTL 15 phút -> được phép phát lại
      expect(
        dedupe.tryAcquire(
          ownerUid: userA,
          dedupeKey: key,
          source: NotificationChannelSource.local,
          nowUtc: t0.add(const Duration(minutes: 16)),
        ),
        isTrue,
      );

      // Đăng xuất tài khoản A -> xóa sạch bộ nhớ tài khoản A, giữ nguyên tài khoản B
      dedupe.clearForOwner(userA);
      expect(dedupe.activeCountForOwner(userA), 0);
      expect(dedupe.activeCountForOwner(userB), 1);
    });
  });
}
