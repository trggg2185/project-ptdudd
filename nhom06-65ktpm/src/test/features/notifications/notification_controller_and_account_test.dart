import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/notifications/data/gateways/in_memory_fcm_messaging_gateway.dart';
import 'package:healthylife/features/notifications/data/gateways/in_memory_local_notification_gateway.dart';
import 'package:healthylife/features/notifications/data/repositories/in_memory_notification_repository.dart';
import 'package:healthylife/features/notifications/domain/entities/approved_plan_reminder_item.dart';
import 'package:healthylife/features/notifications/domain/entities/scheduled_reminder.dart';
import 'package:healthylife/features/notifications/domain/logic/notification_privacy_formatter.dart';
import 'package:healthylife/features/notifications/domain/repositories/fcm_messaging_gateway.dart';
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

    test('chuyển tài khoản trực tiếp (A → B) và đăng xuất Firebase bên ngoài (A → null) đều hủy nhắc cục bộ và vô hiệu hóa device_tokens tài khoản cũ', () async {
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

      // 1. Chuyển trực tiếp tài khoản A → B không qua nút đăng xuất
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
      expect(gateway.scheduledReminders, hasLength(3));

      await coordinator.handleAccountChanged(
        previousUid: 'user-a',
        nextUid: 'user-b',
      );
      expect(gateway.scheduledReminders, isEmpty);
      expect((await repo.getDeviceTokens('user-a')).single.isActive, isFalse);
      expect((await repo.getDeviceTokens('user-b')).single.isActive, isTrue);

      // 2. Đăng nhập tài khoản B rồi bị đăng xuất Firebase từ bên ngoài (B → null)
      final controllerB = NotificationController(
        repository: repo,
        gateway: gateway,
        currentUserId: 'user-b',
        accountCoordinator: coordinator,
        nowProvider: () => fixedNow,
      );
      addTearDown(controllerB.dispose);
      await controllerB.loadAll();
      expect(gateway.scheduledReminders, hasLength(3));

      await coordinator.handleAccountChanged(
        previousUid: 'user-b',
        nextUid: null,
      );
      expect(gateway.scheduledReminders, isEmpty);
      expect((await repo.getDeviceTokens('user-b')).single.isActive, isFalse);

      // 3. Tài khoản A đăng nhập lại, kích hoạt lại token rồi lại đăng xuất bên ngoài -> vẫn vô hiệu hóa lại đúng
      await coordinator.handleAccountChanged(
        previousUid: null,
        nextUid: 'user-a',
      );
      await repo.registerDeviceToken(
        ownerUid: 'user-a',
        token: 'fcm-token-a',
        platform: 'android',
      );
      expect((await repo.getDeviceTokens('user-a')).single.isActive, isTrue);

      await coordinator.handleAccountChanged(
        previousUid: 'user-a',
        nextUid: null,
      );
      expect((await repo.getDeviceTokens('user-a')).single.isActive, isFalse);
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

    test('tích hợp FCM: tự đăng ký token, xử lý onTokenRefresh kèm retry thu hồi token cũ và chống trùng onForegroundMessage', () async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );
      final fcmGateway = InMemoryFcmMessagingGateway(
        currentToken: 'fcm-token-v1',
      );
      final coordinator = NotificationAccountCoordinator(
        gateway: gateway,
        fcmGateway: fcmGateway,
        repositoryResolver: () => repo,
        nowProvider: () => fixedNow,
      );
      addTearDown(() async {
        coordinator.dispose();
        await fcmGateway.dispose();
      });

      // 1. Khi phiên được cấp quyền -> tự động đăng ký token FCM v1
      await coordinator.activateAuthorizedSession('user-fcm');
      var tokens = await repo.getDeviceTokens('user-fcm');
      expect(tokens, hasLength(1));
      expect(tokens.single.token, 'fcm-token-v1');
      expect(tokens.single.isActive, isTrue);

      // 2. Xoay vòng token (onTokenRefresh) lúc mạng chập chờn không tắt được token cũ -> xếp hàng đợi retry
      repo.nextDeactivateTokenError = const NotificationSyncException('Offline');
      fcmGateway.emitTokenRefresh('fcm-token-v2');
      await Future<void>.delayed(Duration.zero);

      tokens = await repo.getDeviceTokens('user-fcm');
      expect(
        tokens.firstWhere((t) => t.token == 'fcm-token-v2').isActive,
        isTrue,
      );
      expect(
        tokens.firstWhere((t) => t.token == 'fcm-token-v1').isActive,
        isTrue,
      );
      expect(coordinator.pendingDeactivationCount, 1);

      // Mạng phục hồi -> handleAppResumed() tự retry thu hồi token cũ, giữ token mới hoạt động
      await coordinator.handleAppResumed();
      tokens = await repo.getDeviceTokens('user-fcm');
      expect(
        tokens.firstWhere((t) => t.token == 'fcm-token-v1').isActive,
        isFalse,
      );
      expect(
        tokens.firstWhere((t) => t.token == 'fcm-token-v2').isActive,
        isTrue,
      );
      expect(coordinator.pendingDeactivationCount, 0);

      // 3. Cầu nối FCM foreground qua NotificationDeduplicator chung với Local Notifications
      final controller = NotificationController(
        repository: repo,
        gateway: gateway,
        currentUserId: 'user-fcm',
        accountCoordinator: coordinator,
        nowProvider: () => fixedNow,
      );
      addTearDown(controller.dispose);
      await controller.loadAll();

      final approvedItem = controller.approvedItems.first;
      final localSent = await controller.dispatchEventWithDeduplication(
        item: approvedItem,
        source: NotificationChannelSource.local,
      );
      expect(localSent, isTrue);
      expect(gateway.shownReminders, hasLength(1));

      // FCM bắn cùng mục lịch (trùng dedupeKey) -> bị chặn, không phát đúp
      fcmGateway.emitForegroundMessage(
        IncomingFcmMessage(
          messageId: 'msg-dup-1',
          ownerUid: 'user-fcm',
          planId: approvedItem.planId,
          itemId: approvedItem.itemId,
          itemType: approvedItem.itemType,
          scheduledAtUtc: approvedItem.startsAtUtc,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.suppressedFcmDuplicateCount, 1);
      expect(gateway.shownReminders, hasLength(1));

      // FCM thuộc tài khoản khác -> bị bỏ qua hoàn toàn
      fcmGateway.emitForegroundMessage(
        IncomingFcmMessage(
          messageId: 'msg-foreign-1',
          ownerUid: 'other-account',
          itemId: 'foreign-item',
          scheduledAtUtc: fixedNow,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(gateway.shownReminders, hasLength(1));

      // FCM sự kiện mới hợp lệ -> được phát với nội dung màn hình khóa trung tính an toàn
      fcmGateway.emitForegroundMessage(
        IncomingFcmMessage(
          messageId: 'msg-new-1',
          ownerUid: 'user-fcm',
          planId: 'plan-server-1',
          itemId: 'server-nudge-1',
          itemType: ReminderItemType.habit,
          scheduledAtUtc: fixedNow.add(const Duration(minutes: 5)),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(gateway.shownReminders, hasLength(2));
      expect(
        gateway.shownReminders.last.lockScreenBody,
        NotificationPrivacyFormatter.neutralLockScreenBody,
      );
      expect(gateway.shownReminders.last.hideDetailsOnLockScreen, isTrue);

      // 4. Khi rơi vào giờ yên lặng (23:00 Asia/Ho_Chi_Minh) -> chặn phát FCM foreground
      final quietNow = tz.TZDateTime(
        profileLocation('Asia/Ho_Chi_Minh')!,
        2026,
        11,
        27,
        23,
        0,
      ).toUtc();
      final quietCoordinator = NotificationAccountCoordinator(
        gateway: gateway,
        fcmGateway: fcmGateway,
        repositoryResolver: () => repo,
        nowProvider: () => quietNow,
      );
      addTearDown(quietCoordinator.dispose);
      await quietCoordinator.activateAuthorizedSession('user-fcm');
      final shownInQuiet = await quietCoordinator.handleIncomingFcmMessage(
        IncomingFcmMessage(
          messageId: 'msg-quiet-1',
          ownerUid: 'user-fcm',
          itemId: 'quiet-item',
          scheduledAtUtc: quietNow,
        ),
      );
      expect(shownInQuiet, isFalse);
      expect(gateway.shownReminders, hasLength(2));
    });

    test('hàng đợi retry thu hồi device_tokens khi offline phân vùng chặt theo tài khoản (an toàn RLS)', () async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );
      final fcmGateway = InMemoryFcmMessagingGateway(
        currentToken: 'tok-a-1',
      );
      final coordinator = NotificationAccountCoordinator(
        gateway: gateway,
        fcmGateway: fcmGateway,
        repositoryResolver: () => repo,
        nowProvider: () => fixedNow,
      );
      addTearDown(() async {
        coordinator.dispose();
        await fcmGateway.dispose();
      });

      await coordinator.activateAuthorizedSession('user-a');
      expect((await repo.getDeviceTokens('user-a')).single.isActive, isTrue);

      // Đăng xuất tài khoản A lúc mất mạng -> xóa token FCM cục bộ, xếp tác vụ thu hồi Supabase vào hàng đợi retry
      repo.nextDeactivateTokenError = const NotificationSyncException(
        'Mất kết nối mạng',
      );
      await coordinator.handleBeforeSignOut('user-a');

      expect(gateway.scheduledReminders, isEmpty);
      expect(fcmGateway.deleteTokenCallCount, 1);
      expect(coordinator.pendingDeactivationCount, 1);
      expect((await repo.getDeviceTokens('user-a')).single.isActive, isTrue);

      // Tài khoản B đăng nhập lúc có mạng -> đăng ký token B nhưng KHÔNG được gửi/xóa nhầm hàng đợi của tài khoản A
      await coordinator.activateAuthorizedSession('user-b');
      expect((await repo.getDeviceTokens('user-b')).single.isActive, isTrue);
      expect(coordinator.pendingDeactivationCount, 1);
      expect(
        coordinator.pendingDeactivations.single.ownerUid,
        'user-a',
      );

      // Tài khoản B đăng xuất bình thường -> token B bị vô hiệu hóa, hàng đợi của A vẫn còn nguyên
      await coordinator.handleBeforeSignOut('user-b');
      expect((await repo.getDeviceTokens('user-b')).single.isActive, isFalse);
      expect(coordinator.pendingDeactivationCount, 1);

      // Tài khoản A đăng nhập lại lúc có mạng -> tự động retry thu hồi token cũ 'tok-a-1' trước, rồi đăng ký token mới
      await coordinator.activateAuthorizedSession('user-a');
      final tokensA = await repo.getDeviceTokens('user-a');
      expect(
        tokensA.firstWhere((t) => t.token == 'tok-a-1').isActive,
        isFalse,
      );
      expect(
        tokensA.where((t) => t.isActive),
        hasLength(1),
      );
      expect(
        tokensA.firstWhere((t) => t.isActive).token,
        isNot('tok-a-1'),
      );
      expect(coordinator.pendingDeactivationCount, 0);
    });

    test('khôi phục nhắc lịch sau khởi động lại máy ở cấp toàn app mà không cần mở NotificationsPage', () async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );
      final fcmGateway = InMemoryFcmMessagingGateway(
        currentToken: 'tok-reboot-appwide',
      );
      final coordinator = NotificationAccountCoordinator(
        gateway: gateway,
        fcmGateway: fcmGateway,
        repositoryResolver: () => repo,
        nowProvider: () => fixedNow,
      );
      addTearDown(() async {
        coordinator.dispose();
        await fcmGateway.dispose();
      });

      // Không hề tạo NotificationController hay mở NotificationsPage
      await coordinator.activateAuthorizedSession('user-appwide');
      expect(gateway.scheduledReminders, hasLength(3));
      expect(
        (await repo.getDeviceTokens('user-appwide')).single.token,
        'tok-reboot-appwide',
      );

      // Máy khởi động lại -> toàn bộ alarm cục bộ bị xóa
      gateway.simulateDeviceReboot();
      expect(gateway.scheduledReminders, isEmpty);

      // Ứng dụng nhận AppLifecycleState.resumed ở cấp toàn app -> tự khôi phục đủ 3 nhắc đã duyệt
      await coordinator.handleAppResumed();
      expect(gateway.scheduledReminders, hasLength(3));
    });
  });
}
