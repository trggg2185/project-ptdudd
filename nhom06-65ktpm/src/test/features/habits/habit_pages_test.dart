import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/habits/data/repositories/in_memory_habit_repository.dart';
import 'package:healthylife/features/habits/domain/entities/habit.dart';
import 'package:healthylife/features/habits/domain/entities/habit_frequency.dart';
import 'package:healthylife/features/habits/presentation/pages/habit_detail_page.dart';
import 'package:healthylife/features/habits/presentation/pages/habit_form_page.dart';
import 'package:healthylife/features/habits/presentation/pages/habits_page.dart';

void main() {
  group('Habit UI Widget Tests', () {
    late InMemoryHabitRepository repository;
    const userId = 'user-test-duc';

    setUp(() {
      repository = InMemoryHabitRepository(seedWithSamples: false);
    });

    testWidgets('HabitsPage renders empty state when no habits exist', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HabitsPage(repository: repository, currentUserId: userId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thói quen & Kỷ luật'), findsOneWidget);
      expect(find.text('Chưa có thói quen nào trong danh mục này'), findsOneWidget);
      expect(find.text('Thêm thói quen'), findsOneWidget);
    });

    testWidgets('HabitsPage displays habits and allows quick check-in', (tester) async {
      final habit = Habit(
        id: 'h-ui-1',
        ownerUid: userId,
        name: 'Uống 2 lít nước',
        description: 'Duy trì bù nước',
        frequency: const HabitFrequency.daily(),
      );
      await repository.saveHabit(habit);

      await tester.pumpWidget(
        MaterialApp(
          home: HabitsPage(repository: repository, currentUserId: userId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Uống 2 lít nước'), findsOneWidget);
      expect(find.text('Check-in'), findsOneWidget);

      // Bấm nút check-in
      await tester.tap(find.text('Check-in'));
      await tester.pumpAndSettle();

      // Nút đổi thành 'Đã xong'
      expect(find.text('Đã xong'), findsOneWidget);
    });

    testWidgets('HabitFormPage validates required habit name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HabitFormPage(ownerUid: userId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thêm thói quen mới'), findsOneWidget);

      // Bấm Lưu khi chưa nhập tên
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(find.text('Vui lòng nhập tên thói quen'), findsOneWidget);
    });

    testWidgets('HabitDetailPage renders streak card and week calendar', (tester) async {
      final habit = Habit(
        id: 'h-detail-1',
        ownerUid: userId,
        name: 'Chạy bộ 30 phút',
        description: 'Tập thể lực mỗi ngày',
        frequency: const HabitFrequency.daily(),
      );
      await repository.saveHabit(habit);

      await tester.pumpWidget(
        MaterialApp(
          home: HabitDetailPage(
            habit: habit,
            repository: repository,
            currentUserId: userId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chạy bộ 30 phút'), findsWidgets);
      expect(find.text('Chuỗi kỷ luật (Streak)'), findsOneWidget);
      expect(find.text('Lịch sử tuần này'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Nhật ký check-in gần đây'), 100);
      expect(find.text('Nhật ký check-in gần đây'), findsOneWidget);
    });
  });
}
