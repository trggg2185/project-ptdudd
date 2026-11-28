import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/core/local_database.dart';
import 'package:healthylife/features/notifications/data/gateways/firebase_messaging_gateway.dart';
import 'package:healthylife/features/notifications/data/gateways/in_memory_local_notification_gateway.dart';
import 'package:healthylife/features/notifications/data/stores/in_memory_notification_background_state_store.dart';
import 'package:healthylife/features/notifications/data/stores/sqlite_notification_background_state_store.dart';
import 'package:healthylife/features/notifications/domain/entities/approved_plan_reminder_item.dart';
import 'package:healthylife/features/notifications/domain/entities/reminder_preferences.dart';
import 'package:healthylife/features/notifications/domain/entities/scheduled_reminder.dart';
import 'package:healthylife/features/notifications/domain/logic/notification_privacy_formatter.dart';
import 'package:healthylife/features/notifications/domain/repositories/fcm_messaging_gateway.dart';
import 'package:healthylife/features/notifications/domain/repositories/notification_background_state_store.dart';
import 'package:healthylife/features/notifications/domain/services/fcm_background_message_processor.dart';
import 'package:healthylife/features/profile/domain/profile_time.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final daytimeUtc = tz.TZDateTime(
    profileLocation('Asia/Ho_Chi_Minh')!,
    2026,
    11,
    27,
    10,
    0,
  ).toUtc();

  final quietNightUtc = tz.TZDateTime(
    profileLocation('Asia/Ho_Chi_Minh')!,
    2026,
    11,
    27,
    23,
    15,
  ).toUtc();

  group('FCM Background / Terminated Handler & Cross-Isolate Dedupe Tests', () {
    test('mapRemoteMessage trích xuất đúng siêu dữ liệu data-only và phát hiện khối notification', () {
      final dataOnly = RemoteMessage(
        messageId: 'm-1',
        data: {
          'owner_uid': 'user-a',
          'plan_id': 'plan-1',
          'item_id': 'item-1',
          'item_type': 'exercise',
          'dedupe_key': 'user-a:exercise:item-1:2026-11-27T03:00:00.000Z',
          'scheduled_at': '2026-11-27T03:00:00.000Z',
          'plan_status': 'approved',
          'item_status': 'approved',
          // Dù server có gửi trường nhạy cảm cũng không được lưu vào IncomingFcmMessage
          'health_note': 'dị ứng hải sản 68 kg',
        },
      );
      final mappedDataOnly = FirebaseMessagingGateway.mapRemoteMessage(dataOnly);
      expect(mappedDataOnly.ownerUid, 'user-a');
      expect(mappedDataOnly.itemType, ReminderItemType.exercise);
      expect(mappedDataOnly.isApprovedOrUnspecified, isTrue);
      expect(mappedDataOnly.hasSystemNotificationPayload, isFalse);

      final withSystemNotification = RemoteMessage(
        messageId: 'm-2',
        notification: const RemoteNotification(
          title: 'Tiêu đề công khai không hợp lệ',
          body: 'Nội dung nhạy cảm',
        ),
        data: {'owner_uid': 'user-a', 'item_id': 'item-2'},
      );
      final mappedWithNotif = FirebaseMessagingGateway.mapRemoteMessage(
        withSystemNotification,
      );
      expect(mappedWithNotif.hasSystemNotificationPayload, isTrue);
    });

    test('xử lý FCM data-only ở background/terminated qua SQLite bền vững xuyên isolate, chống trùng Local ↔ FCM và giữ nội dung private', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'healthylife_fcm_bg_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final dbPath = p.join(tempDir.path, 'healthylife.db');

      // --- Isolate 1 (UI isolate): lưu cấu hình runtime & ghi nhận Local vừa phát ---
      final uiDb = LocalDatabase(databasePath: dbPath);
      final uiStore = SqliteNotificationBackgroundStateStore(uiDb);
      await uiStore.saveRuntimeState(
        NotificationRuntimeState.fromPreferences(
          const ReminderPreferences(
            ownerUid: 'user-bg-sqlite',
            remindersEnabled: true,
            quietHoursStartMinute: 22 * 60,
            quietHoursEndMinute: 7 * 60,
            timezone: 'Asia/Ho_Chi_Minh',
          ),
          updatedAtUtc: daytimeUtc,
        ),
      );
      final alreadyFiredKey =
          'user-bg-sqlite:habit:item-already-local:${daytimeUtc.toIso8601String()}';
      await uiStore.recordDispatchedKey(
        ownerUid: 'user-bg-sqlite',
        dedupeKey: alreadyFiredKey,
        source: NotificationChannelSource.local,
        nowUtc: daytimeUtc,
      );
      await uiDb.close();

      // --- Isolate 2 (Background / Terminated isolate): mở lại cùng file SQLite ---
      final bgDb = LocalDatabase(databasePath: dbPath);
      addTearDown(bgDb.close);
      final bgStore = SqliteNotificationBackgroundStateStore(bgDb);
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );
      final processor = FcmBackgroundMessageProcessor(
        gateway: gateway,
        stateStore: bgStore,
        nowProvider: () => daytimeUtc.add(const Duration(minutes: 2)),
      );

      // 1. FCM đến trễ cùng dedupeKey với Local đã phát -> bị chặn xuyên isolate
      final dupOutcome = await processor.process(
        IncomingFcmMessage(
          messageId: 'bg-dup-1',
          ownerUid: 'user-bg-sqlite',
          itemId: 'item-already-local',
          itemType: ReminderItemType.habit,
          dedupeKey: alreadyFiredKey,
          planStatus: PlanApprovalStatus.approved,
          itemStatus: PlanItemStatus.approved,
        ),
        isBackgroundIsolate: true,
      );
      expect(dupOutcome, FcmHandleOutcome.suppressedDuplicate);
      expect(gateway.shownReminders, isEmpty);

      // 2. FCM data-only hợp lệ mới -> phát thông báo trung tính an toàn màn hình khóa
      final validOutcome = await processor.process(
        IncomingFcmMessage(
          messageId: 'bg-valid-1',
          ownerUid: 'user-bg-sqlite',
          planId: 'plan-approved-1',
          itemId: 'item-server-bg-1',
          itemType: ReminderItemType.exercise,
          scheduledAtUtc: daytimeUtc.add(const Duration(minutes: 5)),
          planStatus: PlanApprovalStatus.approved,
          itemStatus: PlanItemStatus.approved,
        ),
        isBackgroundIsolate: true,
      );
      expect(validOutcome, FcmHandleOutcome.dispatched);
      expect(gateway.shownReminders, hasLength(1));
      final shown = gateway.shownReminders.single;
      expect(
        shown.systemNotificationTitle,
        NotificationPrivacyFormatter.neutralLockScreenTitle,
      );
      expect(
        shown.systemNotificationBody,
        NotificationPrivacyFormatter.neutralLockScreenBody,
      );
      expect(shown.hideDetailsOnLockScreen, isTrue);

      // 3. Server gửi lại đúng cùng sự kiện FCM đó -> bị chặn không phát đúp
      final retryOutcome = await processor.process(
        IncomingFcmMessage(
          messageId: 'bg-valid-1-retry',
          ownerUid: 'user-bg-sqlite',
          planId: 'plan-approved-1',
          itemId: 'item-server-bg-1',
          itemType: ReminderItemType.exercise,
          scheduledAtUtc: daytimeUtc.add(const Duration(minutes: 5)),
        ),
        isBackgroundIsolate: true,
      );
      expect(retryOutcome, FcmHandleOutcome.suppressedDuplicate);
      expect(gateway.shownReminders, hasLength(1));

      // 4. Sau khi UI đăng xuất (clearForOwner) -> background isolate lập tức chặn mọi tin của tài khoản cũ
      await bgStore.clearForOwner('user-bg-sqlite');
      final afterSignOutOutcome = await processor.process(
        IncomingFcmMessage(
          messageId: 'bg-after-logout',
          ownerUid: 'user-bg-sqlite',
          itemId: 'item-new-after-logout',
          scheduledAtUtc: daytimeUtc.add(const Duration(minutes: 10)),
        ),
        // Dù FirebaseAuth cache nền chưa kịp xóa UID vẫn bị store chặn tuyệt đối
        fallbackOwnerUid: 'user-bg-sqlite',
        isBackgroundIsolate: true,
      );
      expect(afterSignOutOutcome, FcmHandleOutcome.rejectedNoActiveSession);
      expect(gateway.shownReminders, hasLength(1));
    });

    test('chặn FCM nền khi Local Notification cùng dedupeKey đang chờ trên thiết bị, khi có notification payload, sai chủ tài khoản, bản nháp, giờ yên lặng hoặc tắt nhắc', () async {
      final store = InMemoryNotificationBackgroundStateStore();
      await store.saveRuntimeState(
        NotificationRuntimeState.fromPreferences(
          const ReminderPreferences(
            ownerUid: 'user-guard',
            remindersEnabled: true,
            quietHoursStartMinute: 22 * 60,
            quietHoursEndMinute: 7 * 60,
            timezone: 'Asia/Ho_Chi_Minh',
          ),
          updatedAtUtc: daytimeUtc,
        ),
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );

      // Đặt sẵn 1 nhắc cục bộ đang chờ trên thiết bị
      final pendingKey =
          'user-guard:meal:item-pending-local:${daytimeUtc.add(const Duration(minutes: 1)).toIso8601String()}';
      await gateway.schedule(
        ScheduledReminder(
          notificationId: 4242,
          ownerUid: 'user-guard',
          planId: 'plan-1',
          itemId: 'item-pending-local',
          itemType: ReminderItemType.meal,
          dedupeKey: pendingKey,
          originalScheduledAtUtc: daytimeUtc.add(const Duration(minutes: 1)),
          effectiveScheduledAtUtc: daytimeUtc.add(const Duration(minutes: 1)),
          timezoneName: 'Asia/Ho_Chi_Minh',
          deferredByQuietHours: false,
          isSnoozed: false,
          lockScreenTitle: NotificationPrivacyFormatter.neutralLockScreenTitle,
          lockScreenBody: NotificationPrivacyFormatter.neutralLockScreenBody,
          inAppTitle: 'Bữa trưa',
          inAppBody: 'Bữa trưa theo lịch đã duyệt',
        ),
      );

      final processor = FcmBackgroundMessageProcessor(
        gateway: gateway,
        stateStore: store,
        nowProvider: () => daytimeUtc,
      );

      // 1. Trùng với nhắc cục bộ đang chờ trên thiết bị -> ưu tiên Local, không phát đúp FCM
      expect(
        await processor.process(
          IncomingFcmMessage(
            ownerUid: 'user-guard',
            itemId: 'item-pending-local',
            itemType: ReminderItemType.meal,
            dedupeKey: pendingKey,
          ),
          isBackgroundIsolate: true,
        ),
        FcmHandleOutcome.suppressedDuplicate,
      );

      // 2. Vi phạm hợp đồng data-only (kèm khối notification ở nền) -> bỏ qua không phát đúp
      expect(
        await processor.process(
          const IncomingFcmMessage(
            ownerUid: 'user-guard',
            itemId: 'item-with-notif',
            hasSystemNotificationPayload: true,
          ),
          isBackgroundIsolate: true,
        ),
        FcmHandleOutcome.skippedSystemNotificationAlreadyShown,
      );

      // 3. Thuộc tài khoản khác -> từ chối
      expect(
        await processor.process(
          const IncomingFcmMessage(
            ownerUid: 'other-user',
            itemId: 'item-foreign',
          ),
          isBackgroundIsolate: true,
        ),
        FcmHandleOutcome.rejectedForeignOwner,
      );

      // 4. Lịch nháp / mục đã bỏ qua -> từ chối
      expect(
        await processor.process(
          const IncomingFcmMessage(
            ownerUid: 'user-guard',
            itemId: 'item-draft',
            planStatus: PlanApprovalStatus.draft,
            itemStatus: PlanItemStatus.approved,
          ),
          isBackgroundIsolate: true,
        ),
        FcmHandleOutcome.rejectedNotApproved,
      );

      // 5. Trong giờ yên lặng (23:15 Asia/Ho_Chi_Minh) -> chặn
      final quietProcessor = FcmBackgroundMessageProcessor(
        gateway: gateway,
        stateStore: store,
        nowProvider: () => quietNightUtc,
      );
      expect(
        await quietProcessor.process(
          const IncomingFcmMessage(
            ownerUid: 'user-guard',
            itemId: 'item-night',
          ),
          isBackgroundIsolate: true,
        ),
        FcmHandleOutcome.suppressedQuietHours,
      );

      // 6. Đã tắt nhắc lịch -> chặn
      await store.saveRuntimeState(
        NotificationRuntimeState.fromPreferences(
          const ReminderPreferences(
            ownerUid: 'user-guard',
            remindersEnabled: false,
            quietHoursStartMinute: 22 * 60,
            quietHoursEndMinute: 7 * 60,
            timezone: 'Asia/Ho_Chi_Minh',
          ),
          updatedAtUtc: daytimeUtc,
        ),
      );
      expect(
        await processor.process(
          const IncomingFcmMessage(
            ownerUid: 'user-guard',
            itemId: 'item-when-disabled',
          ),
          isBackgroundIsolate: true,
        ),
        FcmHandleOutcome.suppressedDisabled,
      );
      expect(gateway.shownReminders, isEmpty);
    });
  });
}
