import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/auth/domain/auth_repository.dart';
import 'package:healthylife/features/auth/presentation/auth_gate.dart';
import 'package:healthylife/features/sleep/data/repositories/in_memory_sleep_repository.dart';
import 'package:healthylife/features/sleep/domain/entities/routine_block.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_log.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_window.dart';
import 'package:healthylife/features/sleep/domain/repositories/sleep_repository.dart';
import 'package:healthylife/features/sleep/presentation/controllers/sleep_controller.dart';
import 'package:healthylife/features/sleep/presentation/pages/sleep_page.dart';
import 'package:healthylife/main.dart';

void main() {
  final fixedNow = DateTime(2026, 11, 24, 18, 0);
  const userId = 'firebase-user-sleep-ui';

  group('SleepPage UI, Responsive, Accessibility & Keyboard Tests', () {
    testWidgets('hiển thị trạng thái đang tải, trạng thái trống và thông báo minh bạch', (
      tester,
    ) async {
      final repo = InMemorySleepRepository(
        seedWithSamples: false,
        simulatedDelay: const Duration(milliseconds: 50),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SleepPage(
            repository: repo,
            currentUserId: userId,
            nowProvider: () => fixedNow,
          ),
        ),
      );

      // 1. Trạng thái đang tải (Loading)
      expect(
        find.text('Đang tải nhật ký giấc ngủ và lịch sinh hoạt...'),
        findsOneWidget,
      );

      await tester.pumpAndSettle();

      // 2. Trạng thái trống (Empty) + thông báo không suy ra từ tắt màn hình / không ép 22:00
      expect(find.text('Chưa có nhật ký giấc ngủ nào'), findsOneWidget);
      expect(
        find.textContaining('không suy ra giấc ngủ thật từ việc không dùng điện thoại'),
        findsOneWidget,
      );
      expect(find.textContaining('không ép mốc 22:00'), findsOneWidget);
    });

    testWidgets('hiển thị trạng thái lỗi khi tải thất bại và phục hồi khi bấm Thử lại', (
      tester,
    ) async {
      final repo = InMemorySleepRepository(
        seedWithSamples: true,
        referenceDate: fixedNow,
        nextError: const SleepSyncException('Mất kết nối Supabase khi tải nhật ký ngủ.'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SleepPage(
            repository: repo,
            currentUserId: userId,
            nowProvider: () => fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Không thể tải dữ liệu'), findsOneWidget);
      expect(
        find.text('Mất kết nối Supabase khi tải nhật ký ngủ.'),
        findsOneWidget,
      );

      // Bấm nút Thử lại -> tải thành công dữ liệu mẫu
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.text('Không thể tải dữ liệu'), findsNothing);
      expect(find.textContaining('Nhật ký giấc ngủ (5)'), findsOneWidget);
    });

    testWidgets('nhập giờ ngủ qua nửa đêm (23:30 → 07:00) bằng bàn phím và lưu thành công', (
      tester,
    ) async {
      final repo = InMemorySleepRepository(seedWithSamples: false);

      await tester.pumpWidget(
        MaterialApp(
          home: SleepPage(
            repository: repo,
            currentUserId: userId,
            nowProvider: () => fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mở form bằng phím tắt Alt + N (kiểm thử thao tác bàn phím)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(find.text('Ghi nhật ký giấc ngủ'), findsOneWidget);

      // Nhập giờ đi ngủ 23:30 và giờ thức dậy 07:00 qua bàn phím
      await tester.enterText(find.byKey(const Key('sleep_bed_hour')), '23');
      await tester.enterText(find.byKey(const Key('sleep_bed_minute')), '30');
      await tester.enterText(find.byKey(const Key('sleep_wake_hour')), '07');
      await tester.enterText(find.byKey(const Key('sleep_wake_minute')), '00');
      await tester.pumpAndSettle();

      // Xác nhận xem trước tự động tính qua nửa đêm (+1 ngày) và thời lượng 7 giờ 30 phút
      expect(find.textContaining('7 giờ 30 phút'), findsOneWidget);
      expect(find.textContaining('Qua nửa đêm (+1 ngày)'), findsOneWidget);

      // Chọn mức tỉnh táo 5 • Rất sảng khoái
      await tester.ensureVisible(find.text('5 • Rất sảng khoái'));
      await tester.tap(find.text('5 • Rất sảng khoái'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('sleep_note_field')),
        'Ngủ sâu qua nửa đêm',
      );
      await tester.ensureVisible(find.byKey(const Key('sleep_save_button')));
      await tester.tap(find.byKey(const Key('sleep_save_button')));
      await tester.pumpAndSettle();

      // Quay về màn chính và hiển thị bản ghi vừa lưu với nhãn Qua nửa đêm
      expect(find.textContaining('Nhật ký giấc ngủ (1)'), findsOneWidget);
      expect(find.text('Qua nửa đêm'), findsOneWidget);
      expect(find.textContaining('5/5 • Rất sảng khoái'), findsOneWidget);
      expect(find.text('Ngủ sâu qua nửa đêm'), findsOneWidget);
    });

    testWidgets('hỗ trợ thiết lập khoảng ngủ ca đêm (07:30–15:00) không bị ép 22:00', (
      tester,
    ) async {
      final repo = InMemorySleepRepository(seedWithSamples: false);
      repo.setRoutineBlocks(userId, [
        RoutineBlock(
          id: 'night-shift',
          title: 'Ca trực đêm (22:00 – 06:00)',
          kind: RoutineBlockKind.workShift,
          startsAt: DateTime(2026, 11, 23, 22, 0),
          endsAt: DateTime(2026, 11, 24, 6, 0),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: SleepPage(
            repository: repo,
            currentUserId: userId,
            nowProvider: () => fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mở hộp thoại đặt khoảng ngủ mong muốn
      await tester.tap(find.text('Thiết lập'));
      await tester.pumpAndSettle();

      expect(find.text('Khoảng ngủ mong muốn'), findsWidgets);

      // Chọn mẫu ca đêm — ngủ ban ngày (07:30 – 15:00)
      await tester.tap(find.text('Ca đêm — ngủ ban ngày'));
      await tester.pumpAndSettle();

      expect(find.textContaining('07:30 – 15:00'), findsOneWidget);
      await tester.tap(find.text('Lưu khung ngủ'));
      await tester.pumpAndSettle();

      // Hiển thị trên cả thẻ tổng quan lẫn lịch sinh hoạt 24 giờ
      expect(find.textContaining('07:30 – 15:00'), findsAtLeastNWidgets(1));
      final savedWindow = await repo.getSleepWindow(userId);
      expect(savedWindow, equals(const SleepWindow(
        startMinute: 7 * 60 + 30,
        endMinute: 15 * 60,
        label: 'Ca đêm — ngủ ban ngày',
      )));
    });

    testWidgets('giao diện responsive: 1 cột trên Android (390px) và 2 cột trên Web (1280px)', (
      tester,
    ) async {
      final repo = InMemorySleepRepository(
        seedWithSamples: true,
        nightShiftSample: true,
        referenceDate: fixedNow,
      );

      // 1. Màn hình Android hẹp (390x844) -> compact layout 1 cột có SegmentedButton
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: SleepPage(
            repository: repo,
            currentUserId: userId,
            nowProvider: () => fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sleep_compact_layout')), findsOneWidget);
      expect(find.byKey(const Key('sleep_wide_layout')), findsNothing);

      // Chuyển sang tab Lịch sinh hoạt 24h trên Android
      await tester.tap(find.text('Lịch sinh hoạt 24h'));
      await tester.pumpAndSettle();
      expect(find.text('Lịch sinh hoạt 24 giờ'), findsOneWidget);

      // 2. Màn hình Web rộng (1280x800) -> wide layout 2 cột song song không cần chuyển tab
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sleep_wide_layout')), findsOneWidget);
      expect(find.byKey(const Key('sleep_compact_layout')), findsNothing);
      expect(find.text('Lịch sinh hoạt 24 giờ'), findsOneWidget);
      expect(find.textContaining('Nhật ký giấc ngủ (5)'), findsOneWidget);
    });

    testWidgets('nhãn truy cập Semantics có mặt đầy đủ trên màn hình chính', (
      tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        final repo = InMemorySleepRepository(seedWithSamples: false);
        await repo.saveSleepLog(
          SleepLog(
            id: 'sem-1',
            ownerUid: userId,
            sleptAt: DateTime(2026, 11, 23, 23, 30),
            wokeAt: DateTime(2026, 11, 24, 7, 0),
            alertness: AlertnessLevel.refreshed,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SleepPage(
              repository: repo,
              currentUserId: userId,
              nowProvider: () => fixedNow,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel('Thêm nhật ký giấc ngủ mới'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Thiết lập khoảng ngủ mong muốn'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Tải lại dữ liệu giấc ngủ'), findsOneWidget);
      } finally {
        semanticsHandle.dispose();
      }
    });

    testWidgets('HealthyLifeApp hỗ trợ mở trực tiếp SleepPage và AuthGate kiểm soát quyền claim', (
      tester,
    ) async {
      final repo = InMemorySleepRepository(seedWithSamples: false);
      await tester.pumpWidget(HealthyLifeApp(sleepRepository: repo));
      await tester.pumpAndSettle();
      expect(find.text('Giấc ngủ & Lịch sinh hoạt'), findsOneWidget);

      // Kiểm tra resolveSleepRepository fallback offline
      expect(resolveSleepRepository(), isA<InMemorySleepRepository>());

      // Kiểm tra tích hợp AuthGate: nút "Mở nhật ký ngủ" theo claim & đổi tài khoản
      final auth = _StubAuthRepository();
      addTearDown(auth.changes.close);

      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            auth: auth,
            sleepPageBuilder: (session) =>
                Scaffold(body: Text('sleep:${session.uid}')),
          ),
        ),
      );
      auth.changes.add(const AuthSession(uid: 'user-sleep-a'));
      await tester.pumpAndSettle();

      final openSleepButton = find.widgetWithText(FilledButton, 'Mở nhật ký ngủ');
      expect(tester.widget<FilledButton>(openSleepButton).onPressed, isNull);

      auth.allowed = true;
      await tester.tap(find.text('Kiểm tra lại quyền'));
      await tester.pumpAndSettle();
      await tester.tap(openSleepButton);
      await tester.pumpAndSettle();
      expect(find.text('sleep:user-sleep-a'), findsOneWidget);

      // Đổi sang tài khoản B -> xóa màn hình tài khoản A
      auth.allowed = false;
      auth.changes.add(const AuthSession(uid: 'user-sleep-b'));
      await tester.pumpAndSettle();
      expect(find.text('sleep:user-sleep-a'), findsNothing);
      expect(tester.widget<FilledButton>(openSleepButton).onPressed, isNull);
    });

    testWidgets(
      'lưu thành công nhưng tải lại thất bại vẫn giữ bản ghi và hiển thị cảnh báo đồng bộ',
      (tester) async {
        final repo = InMemorySleepRepository(seedWithSamples: false);

        await tester.pumpWidget(
          MaterialApp(
            home: SleepPage(
              repository: repo,
              currentUserId: userId,
              nowProvider: () => fixedNow,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Mở form thêm nhật ký
        await tester.tap(find.byKey(const Key('sleep_add_fab')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('sleep_bed_hour')), '23');
        await tester.enterText(find.byKey(const Key('sleep_bed_minute')), '30');
        await tester.enterText(find.byKey(const Key('sleep_wake_hour')), '07');
        await tester.enterText(find.byKey(const Key('sleep_wake_minute')), '00');
        await tester.enterText(
          find.byKey(const Key('sleep_note_field')),
          'Đã lưu thành công dù reload lỗi',
        );

        // Mô phỏng lỗi mạng chỉ ở bước reload getSleepLogs sau khi save đã thành công
        repo.nextReadLogsError = const SleepSyncException(
          'Mất mạng khi tải lại danh sách.',
        );

        await tester.ensureVisible(find.byKey(const Key('sleep_save_button')));
        await tester.tap(find.byKey(const Key('sleep_save_button')));
        await tester.pumpAndSettle();

        // Form phải đóng lại, bản ghi vừa lưu hiển thị ngay, KHÔNG báo lỗi lưu
        expect(find.text('Ghi nhật ký giấc ngủ'), findsNothing);
        expect(find.textContaining('Nhật ký giấc ngủ (1)'), findsOneWidget);
        expect(find.text('Đã lưu thành công dù reload lỗi'), findsOneWidget);
        expect(find.textContaining('Không thể lưu nhật ký'), findsNothing);

        // Hiển thị cảnh báo nhẹ về bước tải lại và xóa sạch sau khi bấm Tải lại
        expect(
          find.textContaining('Đã lưu nhật ký giấc ngủ thành công, nhưng không thể tải lại'),
          findsOneWidget,
        );
        await tester.tap(find.text('Tải lại'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Đã lưu nhật ký giấc ngủ thành công, nhưng không thể tải lại'),
          findsNothing,
        );
        expect(find.textContaining('Nhật ký giấc ngủ (1)'), findsOneWidget);
      },
    );

    test('SleepController chặn ghi đè và báo xung đột khi chỉnh sửa hoặc xóa bản ghi cũ', () async {
      final repo = InMemorySleepRepository(seedWithSamples: false);
      final controller = SleepController(
        repository: repo,
        currentUserId: userId,
        nowProvider: () => fixedNow,
      );
      addTearDown(controller.dispose);

      // Tạo bản ghi ban đầu (version 1)
      final created = await controller.saveSleepLog(
        sleptAt: DateTime(2026, 11, 23, 23, 0),
        wokeAt: DateTime(2026, 11, 24, 7, 0),
        alertness: AlertnessLevel.refreshed,
        note: 'Bản gốc v1',
      );
      expect(created, isTrue);
      final localV1 = controller.sleepLogs.single;
      expect(localV1.version, equals(1));

      // Thiết bị khác cập nhật bản ghi lên version 2
      final remoteV2 = await repo.saveSleepLog(
        localV1.copyWith(note: 'Bản cập nhật từ thiết bị B'),
        baseVersion: 1,
      );
      expect(remoteV2.version, equals(2));

      // Thiết bị hiện tại (vẫn cầm v1) chỉnh sửa -> phải báo xung đột, không ghi đè v2
      final saveResult = await controller.saveSleepLog(
        existingId: localV1.id,
        sleptAt: DateTime(2026, 11, 23, 23, 15),
        wokeAt: DateTime(2026, 11, 24, 7, 15),
        alertness: AlertnessLevel.energized,
        note: 'Bản cũ từ thiết bị A',
      );
      expect(saveResult, isFalse);
      expect(controller.actionError, contains('thiết bị khác'));
      expect(controller.sleepLogs.single.version, equals(2));
      expect(controller.sleepLogs.single.note, equals('Bản cập nhật từ thiết bị B'));

      // Thiết bị khác tiếp tục nâng lên v3 -> thao tác xóa cầm v2 cũng bị chặn xung đột
      await repo.saveSleepLog(
        remoteV2.copyWith(note: 'Bản v3 từ thiết bị B'),
        baseVersion: 2,
      );
      final deleteResult = await controller.deleteSleepLog(localV1.id);
      expect(deleteResult, isFalse);
      expect(controller.actionError, contains('thiết bị khác'));
      expect(controller.sleepLogs.single.version, equals(3));
      expect(await repo.getSleepLogs(ownerUid: userId), hasLength(1));
    });

    test(
      'SleepController loại bản ghi khỏi danh sách local khi conflict báo bản ghi đã bị xóa trên máy chủ',
      () async {
        final repo = InMemorySleepRepository(seedWithSamples: false);
        final controller = SleepController(
          repository: repo,
          currentUserId: userId,
          nowProvider: () => fixedNow,
        );
        addTearDown(controller.dispose);

        // 1. Trường hợp sửa bản ghi đã bị xóa ở thiết bị khác (serverRecord == null)
        await controller.saveSleepLog(
          sleptAt: DateTime(2026, 11, 22, 23, 0),
          wokeAt: DateTime(2026, 11, 23, 7, 0),
          alertness: AlertnessLevel.refreshed,
          note: 'Bản sẽ bị xóa trước khi sửa',
        );
        final firstLog = controller.sleepLogs.single;
        await repo.deleteSleepLog(ownerUid: userId, logId: firstLog.id);

        final editDeleted = await controller.saveSleepLog(
          existingId: firstLog.id,
          sleptAt: DateTime(2026, 11, 22, 23, 15),
          wokeAt: DateTime(2026, 11, 23, 7, 15),
          alertness: AlertnessLevel.energized,
          note: 'Cố sửa sau khi thiết bị khác đã xóa',
        );
        expect(editDeleted, isFalse);
        expect(controller.actionError, contains('đã bị xóa'));
        expect(controller.sleepLogs, isEmpty);

        // 2. Trường hợp xóa bản ghi đã bị xóa ở thiết bị khác (serverRecord == null)
        await controller.saveSleepLog(
          sleptAt: DateTime(2026, 11, 23, 23, 0),
          wokeAt: DateTime(2026, 11, 24, 7, 0),
          alertness: AlertnessLevel.neutral,
          note: 'Bản sẽ bị xóa trước khi xóa lại',
        );
        final secondLog = controller.sleepLogs.single;
        await repo.deleteSleepLog(ownerUid: userId, logId: secondLog.id);

        final deleteDeleted = await controller.deleteSleepLog(secondLog.id);
        expect(deleteDeleted, isFalse);
        expect(controller.actionError, contains('đã bị xóa'));
        expect(controller.sleepLogs, isEmpty);
      },
    );
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

  @override
  Future<void> deleteAccount() async => changes.add(null);
}
