import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/core/utils/date_helper.dart';
import 'package:healthylife/features/habits/data/repositories/in_memory_habit_repository.dart';
import 'package:healthylife/features/habits/data/repositories/supabase_habit_repository.dart';
import 'package:healthylife/features/habits/domain/entities/habit.dart';
import 'package:healthylife/features/habits/domain/entities/habit_frequency.dart';
import 'package:healthylife/features/habits/domain/entities/habit_log.dart';

void main() {
  group('InMemoryHabitRepository CRUD and CheckIn Tests', () {
    late InMemoryHabitRepository repository;
    const userId = 'user-test-duc';

    setUp(() {
      repository = InMemoryHabitRepository(seedWithSamples: false);
    });

    test('Save and get habit by ID', () async {
      final habit = Habit(
        id: 'h-1',
        ownerUid: userId,
        name: 'Uống nước',
        description: 'Mỗi ngày 2 lít',
        frequency: const HabitFrequency.daily(),
        reminderTime: '07:30',
      );

      await repository.saveHabit(habit);
      final fetched = await repository.getHabitById('h-1');

      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Uống nước'));
      expect(fetched.description, equals('Mỗi ngày 2 lít'));
      expect(fetched.reminderTime, equals('07:30'));
      expect(fetched.isActive, isTrue);
    });

    test('Filter habits by ownerUid and activeOnly', () async {
      final h1 = Habit(id: 'h1', ownerUid: userId, name: 'H1', isActive: true);
      final h2 = Habit(id: 'h2', ownerUid: userId, name: 'H2', isActive: false);
      final h3 = Habit(id: 'h3', ownerUid: 'other-user', name: 'H3', isActive: true);

      await repository.saveHabit(h1);
      await repository.saveHabit(h2);
      await repository.saveHabit(h3);

      final userHabits = await repository.getHabits(ownerUid: userId);
      expect(userHabits.length, equals(2));

      final activeOnly = await repository.getHabits(ownerUid: userId, activeOnly: true);
      expect(activeOnly.length, equals(1));
      expect(activeOnly.first.id, equals('h1'));
    });

    test('Toggle habit active status', () async {
      final habit = Habit(id: 'h-toggle', ownerUid: userId, name: 'Chạy bộ', isActive: true);
      await repository.saveHabit(habit);

      await repository.toggleHabitActive('h-toggle', false);
      final updated = await repository.getHabitById('h-toggle');
      expect(updated!.isActive, isFalse);

      await repository.toggleHabitActive('h-toggle', true);
      final activeAgain = await repository.getHabitById('h-toggle');
      expect(activeAgain!.isActive, isTrue);
    });

    test('Delete habit cascades and removes its logs', () async {
      final habit = Habit(id: 'h-del', ownerUid: userId, name: 'Đọc sách');
      await repository.saveHabit(habit);

      final log = HabitLog(
        id: 'l-del',
        habitId: 'h-del',
        userId: userId,
        date: DateTime.now(),
        status: CheckInStatus.completed,
      );
      await repository.recordCheckIn(log);

      // Verify log exists
      final logsBefore = await repository.getHabitLogs('h-del');
      expect(logsBefore.length, equals(1));

      // Delete habit
      await repository.deleteHabit('h-del');
      final fetched = await repository.getHabitById('h-del');
      final logsAfter = await repository.getHabitLogs('h-del');

      expect(fetched, isNull);
      expect(logsAfter, isEmpty);
    });

    test('Record check-in is idempotent: overwrites existing log for the same date', () async {
      final today = DateHelper.normalize(DateTime.now());
      final habit = Habit(id: 'h-checkin', ownerUid: userId, name: 'Hít đất');
      await repository.saveHabit(habit);

      // 1. Ghi nhận bỏ qua buổi sáng
      final morningLog = HabitLog(
        id: 'log-morning',
        habitId: 'h-checkin',
        userId: userId,
        date: today,
        status: CheckInStatus.skipped,
        reason: 'Bận họp',
      );
      await repository.recordCheckIn(morningLog);

      var dayLog = await repository.getLogForHabitAndDate('h-checkin', today);
      expect(dayLog?.status, equals(CheckInStatus.skipped));
      expect(dayLog?.reason, equals('Bận họp'));

      // 2. Chiều rảnh, người dùng hoàn thành thói quen -> ghi đè log
      final eveningLog = HabitLog(
        id: 'log-evening',
        habitId: 'h-checkin',
        userId: userId,
        date: today,
        status: CheckInStatus.completed,
      );
      await repository.recordCheckIn(eveningLog);

      dayLog = await repository.getLogForHabitAndDate('h-checkin', today);
      expect(dayLog?.status, equals(CheckInStatus.completed));
      expect(dayLog?.reason, isNull);

      // Tổng số log vẫn chỉ là 1 cho ngày hôm nay
      final allLogs = await repository.getHabitLogs('h-checkin');
      expect(allLogs.length, equals(1));
    });

    test('Delete habit log allows undoing a check-in', () async {
      final today = DateTime.now();
      final log = HabitLog(
        id: 'log-undo',
        habitId: 'h-undo',
        userId: userId,
        date: today,
        status: CheckInStatus.completed,
      );
      await repository.recordCheckIn(log);

      expect(await repository.getLogForHabitAndDate('h-undo', today), isNotNull);

      await repository.deleteHabitLog('log-undo');
      expect(await repository.getLogForHabitAndDate('h-undo', today), isNull);
    });

    test('Repository integration with streak calculation', () async {
      final baseDate = DateTime(2026, 11, 20);
      final habit = Habit(
        id: 'h-streak',
        ownerUid: userId,
        name: 'Uống nước đều',
        frequency: const HabitFrequency.daily(),
        createdAt: baseDate,
      );
      await repository.saveHabit(habit);

      // Ghi nhận 3 ngày liên tiếp
      for (int i = 0; i < 3; i++) {
        final d = baseDate.add(Duration(days: i));
        await repository.recordCheckIn(
          HabitLog(id: 'l-$i', habitId: 'h-streak', userId: userId, date: d, status: CheckInStatus.completed),
        );
      }

      final day3 = baseDate.add(const Duration(days: 2));
      final streak = await repository.getStreakInfo(habit, referenceDate: day3);

      expect(streak.currentStreak, equals(3));
      expect(streak.longestStreak, equals(3));
      expect(streak.completionPercentage, equals(100.0));
    });

    test('HabitSyncException formats error message clearly without swallowing (P1 Finding)', () {
      final ex = HabitSyncException('Lỗi mạng kết nối Supabase', cause: 'SocketException: Failed host lookup');
      expect(ex.message, contains('Lỗi mạng kết nối Supabase'));
      expect(ex.toString(), contains('SocketException: Failed host lookup'));
    });
  });
}
