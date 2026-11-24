import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/profile/domain/health_profile.dart';
import 'package:healthylife/features/profile/domain/profile_repository.dart';
import 'package:healthylife/features/profile/domain/schedule_block.dart';
import 'package:healthylife/features/profile/presentation/profile_page.dart';

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
