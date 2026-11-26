import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/profile/domain/health_profile.dart';
import 'package:healthylife/features/profile/domain/profile_repository.dart';
import 'package:healthylife/features/profile/domain/schedule_block.dart';
import 'package:healthylife/features/profile/presentation/profile_page.dart';
import 'package:healthylife/features/profile/presentation/schedule_editor.dart';

void main() {
  testWidgets(
    'an incomplete profile can add and reopen a manual schedule entry',
    (tester) async {
      final repository = _TestProfileRepository();
      await tester.pumpWidget(
        MaterialApp(home: ProfilePage(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Cần xác nhận'), findsOneWidget);

      await tester.tap(find.text('Mở lịch thủ công'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm lịch thủ công'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên khoảng lịch'),
        'Đi bộ sau giờ làm',
      );
      await tester.tap(find.text('Lưu khoảng lịch'));
      await tester.pumpAndSettle();

      expect(repository.blocks.single.kind, ScheduleKind.manual);
      expect(find.text('Đi bộ sau giờ làm'), findsOneWidget);
      await tester.tap(find.text('Đi bộ sau giờ làm'));
      await tester.pumpAndSettle();
      expect(find.text('Sửa khoảng lịch'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Xóa Đi bộ sau giờ làm'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
      await tester.pumpAndSettle();
      expect(repository.blocks, isEmpty);
    },
  );

  testWidgets(
    'invalid numbers block saving even when their field is off screen',
    (tester) async {
      final repository = _TestProfileRepository();
      await tester.pumpWidget(
        MaterialApp(home: ProfilePage(repository: repository)),
      );
      await tester.pumpAndSettle();

      final minutes = find.widgetWithText(
        TextFormField,
        'Số phút có thể tập mỗi buổi',
      );
      await tester.ensureVisible(minutes);
      await tester.enterText(minutes, '241');
      final save = find.widgetWithText(FilledButton, 'Lưu hồ sơ');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.saveCalls, 0);

      await tester.ensureVisible(minutes);
      await tester.enterText(minutes, '20');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.saveCalls, 1);
      expect(repository.profile.sessionMinutes, 20);
    },
  );
  testWidgets('changing the first day flags invalid exceptions before saving', (
    tester,
  ) async {
    final block = ScheduleBlock.fromLocal(
      id: 'weekly',
      kind: ScheduleKind.work,
      title: 'Ca sáng',
      timeZone: 'Asia/Ho_Chi_Minh',
      date: DateTime.utc(2026, 12, 1),
      startMinute: 480,
      endMinute: 540,
      repeatsWeekly: true,
      exceptionDates: [DateTime.utc(2026, 12, 8), DateTime.utc(2026, 12, 22)],
    );
    ScheduleBlock? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ScheduleEditor(
                  timeZone: block.timeZone,
                  isManual: false,
                  initialBlock: block,
                  save: (value) async => saved = value,
                ),
              ),
              child: const Text('Sửa lịch'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sửa lịch'));
    await tester.pumpAndSettle();

    Future<void> changeStartDate(String previousDate, String day) async {
      final picker = find.text('Ngày bắt đầu $previousDate');
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text(day),
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
    }

    final warning = find.textContaining('hoặc đổi ngày bắt đầu.');
    final bothDatesWarning = find.text(
      'Bỏ ngày ngoại lệ 2026-12-08, 2026-12-22 hoặc đổi ngày bắt đầu.',
    );
    final save = find.widgetWithText(FilledButton, 'Lưu khoảng lịch');
    final earlyChip = find.widgetWithText(InputChip, '2026-12-08');
    final laterChip = find.widgetWithText(InputChip, '2026-12-22');
    await changeStartDate('2026-12-01', '2');
    expect(bothDatesWarning, findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.widget<InputChip>(earlyChip).labelStyle, isNotNull);
    expect(tester.widget<InputChip>(laterChip).labelStyle, isNotNull);

    await changeStartDate('2026-12-02', '1');
    expect(warning, findsNothing);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await changeStartDate('2026-12-01', '15');
    expect(
      find.text('Bỏ ngày ngoại lệ 2026-12-08 hoặc đổi ngày bắt đầu.'),
      findsOneWidget,
    );
    expect(tester.widget<InputChip>(earlyChip).labelStyle, isNotNull);
    expect(tester.widget<InputChip>(laterChip).labelStyle, isNull);

    final delete = find.descendant(
      of: earlyChip,
      matching: find.byTooltip('Delete'),
    );
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(warning, findsNothing);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved?.exceptionDates, {DateTime.utc(2026, 12, 22)});
  });
}

class _TestProfileRepository implements ProfileRepository {
  final blocks = <ScheduleBlock>[];
  HealthProfile profile = HealthProfile();
  int saveCalls = 0;

  @override
  Future<ProfileData> load() async =>
      (profile: profile, blocks: blocks.toList());

  @override
  Future<void> saveProfile(HealthProfile profile) async {
    this.profile = profile;
    saveCalls++;
  }

  @override
  Future<void> saveBlock(ScheduleBlock block) async {
    blocks.removeWhere((item) => item.id == block.id);
    blocks.add(block);
  }

  @override
  Future<void> deleteBlock(String id) async =>
      blocks.removeWhere((item) => item.id == id);
}
