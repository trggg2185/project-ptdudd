import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/notifications/data/gateways/in_memory_local_notification_gateway.dart';
import 'package:healthylife/features/notifications/data/repositories/in_memory_notification_repository.dart';
import 'package:healthylife/features/notifications/domain/entities/approved_plan_reminder_item.dart';
import 'package:healthylife/features/notifications/domain/entities/scheduled_reminder.dart';
import 'package:healthylife/features/notifications/domain/repositories/notification_repository.dart';
import 'package:healthylife/features/notifications/domain/services/notification_account_coordinator.dart';
import 'package:healthylife/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:healthylife/features/profile/domain/profile_time.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  final fixedNow = tz.TZDateTime(
    profileLocation('Asia/Ho_Chi_Minh')!,
    2026,
    11,
    27,
    10,
    0,
  ).toUtc();

  group('NotificationController, Account Coordinator & Resilience Tests', () {
    test('đăng xuất hủy toàn bộ nhắc cục bộ và vô hiệu hóa device_tokens của đúng tài khoản cũ', () async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );
      final coordinator = NotificationAccountCoordinator(
        gateway: gateway,
        repositoryResolver: () => repo,
      );

      await repo.registerDeviceToken(
        ownerUid: 'user-a',
        token: 'fcm-token-a',
        platform: 'android',
      );
      await repo.registerDeviceToken(
        ownerUid: 'user-b',
        token: 'fcm-token-b',
        platform: 'android',
      );

      final controllerA = NotificationController(
        repository: repo,
        gateway: gateway,
        currentUserId: 'user-a',
        accountCoordinator: coordinator,
        nowProvider: () => fixedNow,
      );
      addTearDown(controllerA.dispose);

      await controllerA.loadAll();
      // 3 mục approved được lên lịch, 2 mục draft/completed bị loại
      expect(gateway.scheduledReminders, hasLength(3));
      expect(controllerA.excludedItems, hasLength(2));

      // Đăng xuất tài khoản A
      await controllerA.cleanupForSignOut();

      expect(gateway.cancelAllCallCount, greaterThanOrEqualTo(1));
      expect(gateway.scheduledReminders, isEmpty);

      final tokensA = await repo.getDeviceTokens('user-a');
      final tokensB = await repo.getDeviceTokens('user-b');
      expect(tokensA.single.isActive, isFalse);
      expect(tokensB.single.isActive, isTrue);
    });

    test('khôi phục nhắc lịch sau khi thiết bị khởi động lại (simulateDeviceReboot)', () async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );
      final controller = NotificationController(
        repository: repo,
        gateway: gateway,
        currentUserId: 'user-reboot',
        nowProvider: () => fixedNow,
      );
      addTearDown(controller.dispose);

      await controller.loadAll();
      expect(gateway.scheduledReminders, hasLength(3));

      // Thiết bị khởi động lại -> alarm trên OS bị mất
      gateway.simulateDeviceReboot();
      expect(gateway.scheduledReminders, isEmpty);

      // Mở lại ứng dụng -> tự đối chiếu và đặt lại đủ 3 nhắc đã duyệt
      await controller.refreshOnAppResumed();
      expect(gateway.scheduledReminders, hasLength(3));
      expect(controller.statusMessage, contains('khôi phục'));
    });

    test('tắt quyền thông báo không crash, giữ danh sách trong app và đồng bộ ngay khi được cấp lại', () async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.denied,
        permissionStatusAfterRequest: NotificationPermissionStatus.granted,
      );
      final controller = NotificationController(
        repository: repo,
        gateway: gateway,
        currentUserId: 'user-perm',
        nowProvider: () => fixedNow,
      );
      addTearDown(controller.dispose);

      await controller.loadAll();
      expect(controller.loadError, isNull);
      expect(controller.permissionStatus, NotificationPermissionStatus.denied);
      // Không gọi đặt alarm hệ thống khi bị tắt quyền, nhưng vẫn hiển thị đủ 3 mục trong app
      expect(gateway.scheduledReminders, isEmpty);
      expect(controller.scheduledReminders, hasLength(3));

      // Người dùng cấp quyền thông báo -> tự động đặt lịch đủ 3 mục ngay lập tức
      await controller.requestNotificationPermission();
      expect(controller.permissionStatus, NotificationPermissionStatus.granted);
      expect(gateway.scheduledReminders, hasLength(3));
    });

    test('đổi múi giờ thiết bị, tạm hoãn (snooze), bỏ qua và xóa mục hủy đúng nhắc cũ', () async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
        deviceTimezone: 'Asia/Tokyo',
      );
      final controller = NotificationController(
        repository: repo,
        gateway: gateway,
        currentUserId: 'user-ops',
        nowProvider: () => fixedNow,
      );
      addTearDown(controller.dispose);

      await controller.loadAll();
      expect(controller.hasTimezoneMismatch, isTrue);

      // Cập nhật sang múi giờ thiết bị (Asia/Tokyo) -> hủy 3 nhắc cũ, đặt lại 3 nhắc mới
      final applied = await controller.applyDeviceTimezone('Asia/Tokyo');
      expect(applied, isTrue);
      expect(controller.preferences.timezone, 'Asia/Tokyo');
      expect(controller.hasTimezoneMismatch, isFalse);
      expect(
        gateway.scheduledReminders.every((r) => r.timezoneName == 'Asia/Tokyo'),
        isTrue,
      );

      // Tạm hoãn mục buổi sáng +15 phút
      final snoozed = await controller.snoozeReminder(
        'plan-item-habit-morning',
        minutes: 15,
      );
      expect(snoozed, isTrue);
      final snoozedReminder = gateway.scheduledReminders.firstWhere(
        (r) => r.itemId == 'plan-item-habit-morning',
      );
      expect(snoozedReminder.isSnoozed, isTrue);

      // Bỏ qua mục buổi sáng -> bị loại khỏi OS alarms
      await controller.skipPlanItem('plan-item-habit-morning');
      expect(
        gateway.scheduledReminders.any(
          (r) => r.itemId == 'plan-item-habit-morning',
        ),
        isFalse,
      );

      // Xóa mục vận động chiều -> bị loại khỏi OS alarms
      await controller.deletePlanItem('plan-item-exercise-afternoon');
      expect(
        gateway.scheduledReminders.any(
          (r) => r.itemId == 'plan-item-exercise-afternoon',
        ),
        isFalse,
      );
      expect(gateway.scheduledReminders, hasLength(1));
    });

    test('chặn trùng Local ↔ FCM trên controller và phát hiện xung đột version cấu hình', () async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );
      final controller = NotificationController(
        repository: repo,
        gateway: gateway,
        currentUserId: 'user-dedupe',
        nowProvider: () => fixedNow,
      );
      addTearDown(controller.dispose);

      await controller.loadAll();
      final approvedItem = controller.approvedItems.first;

      // Local phát lần đầu -> thành công
      final firstSent = await controller.dispatchEventWithDeduplication(
        item: approvedItem,
        source: NotificationChannelSource.local,
      );
      expect(firstSent, isTrue);
      expect(gateway.shownReminders, hasLength(1));

      // FCM gửi cùng mục lịch -> bị chặn không phát trùng
      final duplicateFcm = await controller.dispatchEventWithDeduplication(
        item: approvedItem,
        source: NotificationChannelSource.fcm,
      );
      expect(duplicateFcm, isFalse);
      expect(controller.suppressedDuplicateCount, 1);
      expect(gateway.shownReminders, hasLength(1));

      // Mô phỏng thiết bị khác sửa reminder_preferences trước (tăng version lên 2)
      final remoteCurrent = await repo.getPreferences('user-dedupe');
      await repo.savePreferences(
        remoteCurrent.copyWith(timezone: 'UTC'),
        expectedVersion: remoteCurrent.version,
      );

      // Controller đang cầm version cũ -> báo NotificationConflictException, không ghi đè
      final conflictSave = await controller.updatePreferences(
        controller.preferences.copyWith(timezone: 'Asia/Tokyo'),
      );
      expect(conflictSave, isFalse);
      expect(controller.actionError, contains('thiết bị khác'));
      expect(controller.preferences.timezone, 'UTC');

      // Kiểm tra bản ghi nháp không bao giờ được phát
      final draftItem = controller.excludedItems.firstWhere(
        (i) => i.planStatus == PlanApprovalStatus.draft,
      );
      expect(
        await controller.dispatchEventWithDeduplication(
          item: draftItem,
          source: NotificationChannelSource.fcm,
        ),
        isFalse,
      );
    });

    test('InMemoryNotificationRepository ném NotificationConflictException khi expectedVersion cũ', () async {
      final repo = InMemoryNotificationRepository(seedWithSamples: false);
      final initial = await repo.getPreferences('user-ver');
      final v1 = await repo.savePreferences(initial);
      final v2 = await repo.savePreferences(
        v1.copyWith(timezone: 'Asia/Tokyo'),
        expectedVersion: v1.version,
      );
      expect(v2.version, v1.version + 1);

      await expectLater(
        () => repo.savePreferences(
          v1.copyWith(timezone: 'UTC'),
          expectedVersion: v1.version,
        ),
        throwsA(isA<NotificationConflictException>()),
      );
    });
  });
}
