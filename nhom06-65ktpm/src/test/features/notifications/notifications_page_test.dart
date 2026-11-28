import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/auth/domain/auth_repository.dart';
import 'package:healthylife/features/auth/presentation/auth_gate.dart';
import 'package:healthylife/features/notifications/data/gateways/in_memory_fcm_messaging_gateway.dart';
import 'package:healthylife/features/notifications/data/gateways/in_memory_local_notification_gateway.dart';
import 'package:healthylife/features/notifications/data/repositories/in_memory_notification_repository.dart';
import 'package:healthylife/features/notifications/domain/entities/scheduled_reminder.dart';
import 'package:healthylife/features/notifications/domain/repositories/notification_repository.dart';
import 'package:healthylife/features/notifications/domain/services/notification_account_coordinator.dart';
import 'package:healthylife/features/notifications/presentation/pages/notifications_page.dart';
import 'package:healthylife/features/profile/domain/profile_time.dart';
import 'package:healthylife/main.dart';
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
  const userId = 'firebase-user-notif-ui';

  group('NotificationsPage UI, Responsive & AuthGate Cleanup Tests', () {
    testWidgets('hiển thị trạng thái tải, lỗi, phục hồi Thử lại và tách rõ mục đã duyệt với lịch nháp', (
      tester,
    ) async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
        simulatedDelay: const Duration(milliseconds: 30),
        nextError: const NotificationSyncException(
          'Mất kết nối khi tải cấu hình nhắc lịch.',
        ),
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsPage(
            repository: repo,
            gateway: gateway,
            currentUserId: userId,
            nowProvider: () => fixedNow,
          ),
        ),
      );

      expect(
        find.text('Đang tải cấu hình nhắc lịch và kiểm tra quyền...'),
        findsOneWidget,
      );
      await tester.pumpAndSettle();

      // Trạng thái lỗi -> bấm Thử lại
      expect(find.text('Không thể tải cấu hình nhắc lịch'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      // Sau khi tải xong: 3 mục đã duyệt (có 1 mục dời qua giờ yên lặng) + 2 mục bị loại trừ (nháp/hoàn thành)
      expect(find.text('Nhắc lịch từ lịch đã duyệt (3)'), findsOneWidget);
      expect(
        find.text('Mục không đặt nhắc — nháp / đã xong (2)'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('quiet_deferred_badge_plan-item-sleep-quiet-window')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('lock_screen_preview_box')), findsOneWidget);
      // Không có công tắc cho phép chuyển thông báo màn hình khóa sang public
      expect(find.byKey(const Key('lock_screen_privacy_switch')), findsNothing);
      expect(
        find.byKey(const Key('lock_screen_privacy_policy_tile')),
        findsOneWidget,
      );
    });

    testWidgets('hiển thị cảnh báo khi quyền thông báo bị tắt và cho cấp lại quyền mượt mà', (
      tester,
    ) async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.denied,
        permissionStatusAfterRequest: NotificationPermissionStatus.granted,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsPage(
            repository: repo,
            gateway: gateway,
            currentUserId: userId,
            nowProvider: () => fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('permission_warning_banner')), findsOneWidget);
      expect(gateway.scheduledReminders, isEmpty);

      await tester.tap(find.byKey(const Key('request_permission_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('permission_granted_banner')), findsOneWidget);
      expect(gateway.scheduledReminders, hasLength(3));
    });

    testWidgets('cấu hình giờ yên lặng ca đêm (08:00–15:00) qua dialog và tạm hoãn / bỏ qua mục lịch', (
      tester,
    ) async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsPage(
            repository: repo,
            gateway: gateway,
            currentUserId: userId,
            nowProvider: () => fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mở hộp thoại giờ yên lặng và chọn mẫu ca đêm 08:00 – 15:00
      await tester.ensureVisible(find.byKey(const Key('edit_quiet_hours_button')));
      await tester.tap(find.byKey(const Key('edit_quiet_hours_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quiet_preset_shift')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quiet_save_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('08:00 – 15:00'), findsOneWidget);

      // Tạm hoãn mục buổi sáng
      final snoozeFinder = find.byKey(
        const Key('snooze_button_plan-item-habit-morning'),
      );
      await tester.ensureVisible(snoozeFinder);
      await tester.tap(snoozeFinder);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('snoozed_badge_plan-item-habit-morning')),
        findsOneWidget,
      );

      // Bỏ qua mục buổi sáng -> giảm từ 3 xuống 2 mục đang nhắc
      final skipFinder = find.byKey(
        const Key('skip_button_plan-item-habit-morning'),
      );
      await tester.ensureVisible(skipFinder);
      await tester.tap(skipFinder);
      await tester.pumpAndSettle();
      expect(find.text('Nhắc lịch từ lịch đã duyệt (2)'), findsOneWidget);
    });

    testWidgets('bố cục responsive: 1 cột trên Android (390px) và 2 cột trên Web (1280px)', (
      tester,
    ) async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway();

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsPage(
            repository: repo,
            gateway: gateway,
            currentUserId: userId,
            nowProvider: () => fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notifications_compact_layout')), findsOneWidget);
      expect(find.byKey(const Key('notifications_wide_layout')), findsNothing);

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notifications_wide_layout')), findsOneWidget);
      expect(find.byKey(const Key('notifications_compact_layout')), findsNothing);
    });

    testWidgets('AuthGate tự hủy nhắc cục bộ & device_tokens khi đăng xuất hoặc đổi tài khoản, và HealthyLifeApp hỗ trợ demo', (
      tester,
    ) async {
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
        ownerUid: 'user-notif-a',
        token: 'tok-a',
        platform: 'android',
      );

      final auth = _StubAuthRepository();
      addTearDown(auth.changes.close);

      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            auth: auth,
            notificationsPageBuilder: (session) => NotificationsPage(
              repository: repo,
              gateway: gateway,
              currentUserId: session.uid,
              accountCoordinator: coordinator,
              nowProvider: () => fixedNow,
            ),
            onBeforeSignOut: coordinator.handleBeforeSignOut,
            onAccountChanged: (prev, next) => coordinator.handleAccountChanged(
              previousUid: prev,
              nextUid: next,
            ),
          ),
        ),
      );

      auth.changes.add(const AuthSession(uid: 'user-notif-a'));
      await tester.pumpAndSettle();

      final openBtn = find.widgetWithText(
        FilledButton,
        'Mở nhắc lịch & giờ yên lặng',
      );
      expect(tester.widget<FilledButton>(openBtn).onPressed, isNull);

      auth.allowed = true;
      await tester.tap(find.text('Kiểm tra lại quyền'));
      await tester.pumpAndSettle();
      await tester.tap(openBtn);
      await tester.pumpAndSettle();

      // Mở trang thành công -> đặt lịch 3 nhắc cho user-notif-a
      expect(gateway.scheduledReminders, hasLength(3));

      // Quay về màn hình phiên và bấm Đăng xuất -> tự hủy toàn bộ nhắc và vô hiệu hóa token
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();

      expect(gateway.scheduledReminders, isEmpty);
      expect((await repo.getDeviceTokens('user-notif-a')).single.isActive, isFalse);

      // Chuyển trực tiếp tài khoản A → B qua luồng Auth (không bấm nút đăng xuất) -> hủy nhắc & vô hiệu hóa token của A
      await repo.registerDeviceToken(
        ownerUid: 'user-notif-a',
        token: 'tok-a',
        platform: 'android',
      );
      await repo.registerDeviceToken(
        ownerUid: 'user-notif-b',
        token: 'tok-b',
        platform: 'android',
      );
      auth.changes.add(const AuthSession(uid: 'user-notif-a'));
      await tester.pumpAndSettle();
      await tester.tap(openBtn);
      await tester.pumpAndSettle();
      expect(gateway.scheduledReminders, hasLength(3));

      auth.changes.add(const AuthSession(uid: 'user-notif-b'));
      await tester.pumpAndSettle();
      expect(gateway.scheduledReminders, isEmpty);
      expect((await repo.getDeviceTokens('user-notif-a')).single.isActive, isFalse);
      expect((await repo.getDeviceTokens('user-notif-b')).single.isActive, isTrue);

      // Đăng xuất Firebase từ bên ngoài (luồng phát null cho user-notif-b) -> vô hiệu hóa token của B
      await tester.tap(openBtn);
      await tester.pumpAndSettle();
      expect(gateway.scheduledReminders, hasLength(3));

      auth.changes.add(null);
      await tester.pumpAndSettle();
      expect(gateway.scheduledReminders, isEmpty);
      expect((await repo.getDeviceTokens('user-notif-b')).single.isActive, isFalse);

      // Kiểm tra khởi chạy độc lập qua HealthyLifeApp và fallback offline
      expect(resolveNotificationRepository(), isA<InMemoryNotificationRepository>());
      await tester.pumpWidget(
        HealthyLifeApp(
          notificationRepository: repo,
          notificationGateway: gateway,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nhắc lịch & Giờ yên lặng'), findsOneWidget);
    });

    testWidgets('AuthGate tự đăng ký FCM và khôi phục nhắc lịch toàn app khi có quyền mà không cần mở NotificationsPage', (
      tester,
    ) async {
      final repo = InMemoryNotificationRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
      );
      final gateway = InMemoryLocalNotificationGateway(
        permissionStatus: NotificationPermissionStatus.granted,
      );
      final fcmGateway = InMemoryFcmMessagingGateway(
        currentToken: 'tok-authgate-appwide',
      );
      final coordinator = NotificationAccountCoordinator(
        gateway: gateway,
        fcmGateway: fcmGateway,
        repositoryResolver: () => repo,
        nowProvider: () => fixedNow,
      );
      final auth = _StubAuthRepository();
      addTearDown(() async {
        coordinator.dispose();
        await fcmGateway.dispose();
        await auth.changes.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            auth: auth,
            notificationsPageBuilder: (session) => NotificationsPage(
              repository: repo,
              gateway: gateway,
              currentUserId: session.uid,
              accountCoordinator: coordinator,
              nowProvider: () => fixedNow,
            ),
            onSessionAuthorized: coordinator.activateAuthorizedSession,
            onBeforeSignOut: coordinator.handleBeforeSignOut,
            onAccountChanged: (prev, next) => coordinator.handleAccountChanged(
              previousUid: prev,
              nextUid: next,
            ),
          ),
        ),
      );

      // 1. Đăng nhập nhưng chưa có claim role: authenticated -> chưa đăng ký FCM và chưa đặt nhắc
      auth.changes.add(const AuthSession(uid: 'user-bg-1'));
      await tester.pumpAndSettle();
      expect(await repo.getDeviceTokens('user-bg-1'), isEmpty);
      expect(gateway.scheduledReminders, isEmpty);

      // 2. Cấp claim và bấm Kiểm tra lại quyền -> KHÔNG mở NotificationsPage nhưng vẫn đăng ký FCM và đặt đủ 3 nhắc
      auth.allowed = true;
      await tester.tap(find.text('Kiểm tra lại quyền'));
      await tester.pumpAndSettle();

      final tokens = await repo.getDeviceTokens('user-bg-1');
      expect(tokens, hasLength(1));
      expect(tokens.single.token, 'tok-authgate-appwide');
      expect(tokens.single.isActive, isTrue);
      expect(gateway.scheduledReminders, hasLength(3));

      // 3. Mô phỏng máy khởi động lại khi người dùng chưa mở NotificationsPage -> resume ở cấp app tự khôi phục
      gateway.simulateDeviceReboot();
      expect(gateway.scheduledReminders, isEmpty);
      await coordinator.handleAppResumed();
      expect(gateway.scheduledReminders, hasLength(3));

      // 4. Đăng xuất ngay trên màn hình phiên -> xóa token FCM cục bộ, hủy 3 nhắc và vô hiệu hóa device_tokens
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      expect(gateway.scheduledReminders, isEmpty);
      expect(fcmGateway.deleteTokenCallCount, 1);
      expect((await repo.getDeviceTokens('user-bg-1')).single.isActive, isFalse);
    });
  });
}

class _StubAuthRepository implements AuthRepository {
  final changes = StreamController<AuthSession?>.broadcast();
  bool allowed = false;

  @override
  Stream<AuthSession?> get sessions => changes.stream;

  @override
  Future<bool> hasDataAccess({bool refresh = false}) async => allowed;

  @override
  Future<void> registerWithEmail(String email, String password) async {}

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signInWithEmail(String email, String password) async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async => changes.add(null);
}
