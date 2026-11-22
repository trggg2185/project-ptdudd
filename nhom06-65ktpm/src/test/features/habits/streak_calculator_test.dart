import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/habits/domain/entities/habit.dart';
import 'package:healthylife/features/habits/domain/entities/habit_frequency.dart';
import 'package:healthylife/features/habits/domain/entities/habit_log.dart';
import 'package:healthylife/features/habits/domain/logic/streak_calculator.dart';

void main() {
  group('StreakCalculator Tests', () {
    final baseMonday = DateTime(2026, 11, 16); // Tuần 1: Thứ Hai
    const userId = 'user-test-01';

    test('Consecutive completed days increment currentStreak and longestStreak', () {
      final habit = Habit(
        id: 'h1',
        ownerUid: userId,
        name: 'Chạy bộ',
        frequency: const HabitFrequency.daily(),
        createdAt: baseMonday,
      );

      // Hoàn thành liên tiếp 5 ngày: T2 -> T6
      final logs = List.generate(5, (i) {
        final d = baseMonday.add(Duration(days: i));
        return HabitLog(
          id: 'log-$i',
          habitId: 'h1',
          userId: userId,
          date: d,
          status: CheckInStatus.completed,
        );
      });

      final friday = baseMonday.add(const Duration(days: 4));
      final streak = StreakCalculator.calculate(habit, logs, referenceDate: friday);

      expect(streak.currentStreak, equals(5));
      expect(streak.longestStreak, equals(5));
      expect(streak.totalCompletions, equals(5));
      expect(streak.totalDueDays, equals(5));
      expect(streak.completionPercentage, equals(100.0));
    });

    test('Rest days do NOT break streak ("ngày nghỉ không phá streak")', () {
      // Thói quen chỉ thực hiện vào ngày làm việc (T2 - T6)
      final habit = Habit(
        id: 'h2',
        ownerUid: userId,
        name: 'Tập gym ngày làm việc',
        frequency: const HabitFrequency.weekdays(),
        createdAt: baseMonday,
      );

      // Hoàn thành Thứ Sáu (ngày thứ 5)
      final friday = baseMonday.add(const Duration(days: 4));
      final logs = [
        HabitLog(
          id: 'log-fri',
          habitId: 'h2',
          userId: userId,
          date: friday,
          status: CheckInStatus.completed,
        ),
      ];

      // Xem vào Chủ Nhật (ngày nghỉ)
      final sunday = baseMonday.add(const Duration(days: 6));
      final streakSunday = StreakCalculator.calculate(habit, logs, referenceDate: sunday);

      // Chuỗi từ thứ Sáu vẫn được bảo lưu (1 ngày), tổng số ngày đến hạn trong tuần là 5 ngày (T2 - T6)
      expect(streakSunday.currentStreak, equals(1));
      expect(streakSunday.longestStreak, equals(1));
      expect(streakSunday.totalDueDays, equals(5));
      expect(streakSunday.totalCompletions, equals(1));
    });

    test('Skipped day with valid reason does NOT break streak ("bỏ qua có lý do không phá streak")', () {
      final habit = Habit(
        id: 'h3',
        ownerUid: userId,
        name: 'Đọc sách',
        frequency: const HabitFrequency.daily(),
        createdAt: baseMonday,
      );

      final t2 = baseMonday;
      final t3 = baseMonday.add(const Duration(days: 1));
      final t4 = baseMonday.add(const Duration(days: 2));

      // T2: Hoàn thành, T3: Bỏ qua vì ốm, T4: Hoàn thành
      final logs = [
        HabitLog(id: 'l1', habitId: 'h3', userId: userId, date: t2, status: CheckInStatus.completed),
        HabitLog(id: 'l2', habitId: 'h3', userId: userId, date: t3, status: CheckInStatus.skipped, reason: 'Bị cảm sốt'),
        HabitLog(id: 'l3', habitId: 'h3', userId: userId, date: t4, status: CheckInStatus.completed),
      ];

      final streak = StreakCalculator.calculate(habit, logs, referenceDate: t4);

      // Chuỗi không bị reset về 0, tổng cộng đạt 2 completions + 1 skipped
      expect(streak.currentStreak, equals(2));
      expect(streak.longestStreak, equals(2));
      expect(streak.totalCompletions, equals(2));
      expect(streak.totalSkipped, equals(1));
      expect(streak.totalDueDays, equals(3));
    });

    test('Missed past due day breaks currentStreak to 0 but preserves longestStreak', () {
      final habit = Habit(
        id: 'h4',
        ownerUid: userId,
        name: 'Uống nước',
        frequency: const HabitFrequency.daily(),
        createdAt: baseMonday,
      );

      final t2 = baseMonday;
      final t3 = baseMonday.add(const Duration(days: 1));
      // T4 bị bỏ lỡ hoàn toàn (không có log)
      final t5 = baseMonday.add(const Duration(days: 3));

      final logs = [
        HabitLog(id: 'l1', habitId: 'h4', userId: userId, date: t2, status: CheckInStatus.completed),
        HabitLog(id: 'l2', habitId: 'h4', userId: userId, date: t3, status: CheckInStatus.completed),
        // t4 missed
      ];

      final streak = StreakCalculator.calculate(habit, logs, referenceDate: t5);

      // Current streak đứt về 0, nhưng kỷ lục dài nhất vẫn là 2 ngày
      expect(streak.currentStreak, equals(0));
      expect(streak.longestStreak, equals(2));
      expect(streak.totalCompletions, equals(2));
      expect(streak.totalDueDays, equals(3)); // T2, T3, T4 (T5 là referenceDate pending)
    });

    test('Today pending does NOT break yesterday streak', () {
      final habit = Habit(
        id: 'h5',
        ownerUid: userId,
        name: 'Thiền định',
        frequency: const HabitFrequency.daily(),
        createdAt: baseMonday,
      );

      final yesterday = baseMonday;
      final today = baseMonday.add(const Duration(days: 1));

      // Hôm qua hoàn thành, hôm nay chưa check-in
      final logs = [
        HabitLog(id: 'l1', habitId: 'h5', userId: userId, date: yesterday, status: CheckInStatus.completed),
      ];

      final streak = StreakCalculator.calculate(habit, logs, referenceDate: today);

      // Chuỗi hôm qua vẫn là 1, hôm nay chưa hết ngày nên không phạt
      expect(streak.currentStreak, equals(1));
      expect(streak.longestStreak, equals(1));
      expect(streak.totalCompletions, equals(1));
    });

    test('Future day is classified as future and not evaluated for check-in (P1 Finding)', () {
      final habit = Habit(
        id: 'h-future',
        ownerUid: userId,
        name: 'Tập thể dục tương lai',
        frequency: const HabitFrequency.daily(),
        createdAt: baseMonday,
      );

      final today = baseMonday;
      final tomorrow = baseMonday.add(const Duration(days: 1));
      final nextWeek = baseMonday.add(const Duration(days: 7));

      final statusTomorrow = StreakCalculator.getDayStatus(habit, [], tomorrow, referenceDate: today);
      final statusNextWeek = StreakCalculator.getDayStatus(habit, [], nextWeek, referenceDate: today);

      expect(statusTomorrow, equals(HabitDayStatus.future));
      expect(statusNextWeek, equals(HabitDayStatus.future));
    });

    test('Modifying future frequency preserves historical streak ("sửa lịch tương lai không sửa lịch sử") (P1 Finding)', () {
      final t2 = baseMonday;
      final t3 = baseMonday.add(const Duration(days: 1));
      final t4 = baseMonday.add(const Duration(days: 2)); // Thứ Tư
      final t5 = baseMonday.add(const Duration(days: 3)); // Thứ Năm: ngày đổi lịch

      // Ban đầu từ T2 là thói quen hằng ngày (daily)
      // Người dùng hoàn thành T2, T3, T4 (3 ngày liên tiếp)
      final logs = [
        HabitLog(id: 'l1', habitId: 'h-history', userId: userId, date: t2, status: CheckInStatus.completed),
        HabitLog(id: 'l2', habitId: 'h-history', userId: userId, date: t3, status: CheckInStatus.completed),
        HabitLog(id: 'l3', habitId: 'h-history', userId: userId, date: t4, status: CheckInStatus.completed),
      ];

      // Đến Thứ Năm, người dùng đổi lịch sang chỉ tập Cuối tuần (weekends: T7, CN)
      final habitWithHistory = Habit(
        id: 'h-history',
        ownerUid: userId,
        name: 'Luyện tập',
        frequency: const HabitFrequency.weekends(), // Chu kỳ mới
        createdAt: t2,
        frequencyHistory: [
          FrequencySchedule(frequency: const HabitFrequency.daily(), effectiveFrom: t2),
          FrequencySchedule(frequency: const HabitFrequency.weekends(), effectiveFrom: t5),
        ],
      );

      // Kiểm tra chu kỳ có hiệu lực:
      expect(habitWithHistory.getFrequencyOn(t2), equals(const HabitFrequency.daily()));
      expect(habitWithHistory.getFrequencyOn(t3), equals(const HabitFrequency.daily()));
      expect(habitWithHistory.getFrequencyOn(t4), equals(const HabitFrequency.daily()));
      expect(habitWithHistory.getFrequencyOn(t5), equals(const HabitFrequency.weekends()));

      // Tính streak tại thời điểm Thứ Năm:
      // Các ngày T2, T3, T4 trong quá khứ vẫn được đánh giá theo chu kỳ daily -> chuỗi 3 ngày hoàn thành vẫn nguyên vẹn!
      final streak = StreakCalculator.calculate(habitWithHistory, logs, referenceDate: t5);
      expect(streak.currentStreak, equals(3));
      expect(streak.longestStreak, equals(3));
      expect(streak.totalCompletions, equals(3));
    });

    test('Paused habit freezes streak and does NOT penalize missed days during pause (P2 Finding)', () {
      final t2 = baseMonday;
      final t3 = baseMonday.add(const Duration(days: 1));
      final t5 = baseMonday.add(const Duration(days: 3));

      // Hoàn thành T2 (chuỗi 1 ngày)
      final logs = [
        HabitLog(id: 'l1', habitId: 'h-pause', userId: userId, date: t2, status: CheckInStatus.completed),
      ];

      // Thói quen bị tạm dừng vào đầu ngày Thứ Ba (T3)
      final pausedHabit = Habit(
        id: 'h-pause',
        ownerUid: userId,
        name: 'Đọc sách tạm dừng',
        frequency: const HabitFrequency.daily(),
        createdAt: t2,
        isActive: false,
        pausedAt: t3,
      );

      // Xem vào ngày Thứ Sáu (T5):
      // Trong các ngày T3, T4, T5 thói quen đang tạm dừng nên không sinh ngày đến hạn,
      // chuỗi 1 ngày từ T2 được đóng băng (freeze), không bị phạt về 0!
      final streakAtT5 = StreakCalculator.calculate(pausedHabit, logs, referenceDate: t5);

      expect(streakAtT5.currentStreak, equals(1));
      expect(streakAtT5.longestStreak, equals(1));
      expect(streakAtT5.totalDueDays, equals(1)); // Chỉ có T2 là due day trước khi dừng
      expect(streakAtT5.totalCompletions, equals(1));

      // Trạng thái ngày T3, T4 trong giai đoạn tạm dừng là restDay
      final statusT3 = StreakCalculator.getDayStatus(pausedHabit, logs, t3, referenceDate: t5);
      expect(statusT3, equals(HabitDayStatus.restDay));
    });

    test('Pause and resume with pauseHistory preserves streak upon resumption (P1 Finding)', () {
      final t2 = baseMonday; // Mon: complete
      final t3 = baseMonday.add(const Duration(days: 1)); // Tue: pause starts
      final t5 = baseMonday.add(const Duration(days: 3)); // Thu: pause ends / resumed

      // Hoàn thành T2 (1 ngày) và T5 (ngày tiếp tục lại thói quen)
      final logs = [
        HabitLog(id: 'l1', habitId: 'h-resume', userId: userId, date: t2, status: CheckInStatus.completed),
        HabitLog(id: 'l2', habitId: 'h-resume', userId: userId, date: t5, status: CheckInStatus.completed),
      ];

      // Thói quen từng tạm dừng từ T3 đến T5 (sau đó resumedAt = T5)
      final resumedHabit = Habit(
        id: 'h-resume',
        ownerUid: userId,
        name: 'Đọc sách tạm dừng rồi tiếp tục',
        frequency: const HabitFrequency.daily(),
        createdAt: t2,
        isActive: true,
        pausedAt: null, // Đã tiếp tục nên pausedAt = null
        pauseHistory: [
          PauseInterval(pausedAt: t3, resumedAt: t5),
        ],
      );

      // Tính streak tại thời điểm T5:
      // Các ngày T3, T4 nằm trong khoảng tạm dừng nên được đóng băng,
      // không bị coi là thiếu dữ liệu làm đứt chuỗi.
      // Khi T5 hoàn thành, streak tăng tiếp từ 1 lên 2!
      final streakAtT5 = StreakCalculator.calculate(resumedHabit, logs, referenceDate: t5);
      expect(streakAtT5.currentStreak, equals(2));
      expect(streakAtT5.longestStreak, equals(2));
      expect(streakAtT5.totalCompletions, equals(2));
      expect(streakAtT5.totalDueDays, equals(2)); // T2 và T5 (T3, T4 được miễn)
    });

    test('Future date with anomalous log from backend still returns future status (P2 Finding)', () {
      final habit = Habit(
        id: 'h-future-anomaly',
        ownerUid: userId,
        name: 'Chạy bộ',
        frequency: const HabitFrequency.daily(),
        createdAt: baseMonday,
      );

      final today = baseMonday;
      final tomorrow = baseMonday.add(const Duration(days: 1));

      // Giả sử backend hoặc mạng đồng bộ một log completed cho ngày mai (tương lai)
      final anomalousLogs = [
        HabitLog(
          id: 'log-future-anomaly',
          habitId: 'h-future-anomaly',
          userId: userId,
          date: tomorrow,
          status: CheckInStatus.completed,
        ),
      ];

      // Kiểm tra trạng thái ngày mai (referenceDate = today):
      // Phải trả về future ("Chưa đến hạn"), KHÔNG được trả về completed ("Đã xong")!
      final statusTomorrow = StreakCalculator.getDayStatus(
        habit,
        anomalousLogs,
        tomorrow,
        referenceDate: today,
      );

      expect(statusTomorrow, equals(HabitDayStatus.future));
    });

    test('Deduplication: multiple logs on same date takes latest log without double counting', () {
      final habit = Habit(
        id: 'h6',
        ownerUid: userId,
        name: 'Tập thở',
        frequency: const HabitFrequency.daily(),
        createdAt: baseMonday,
      );

      // 2 logs trong cùng ngày baseMonday (do đồng bộ hoặc bấm lại)
      final logs = [
        HabitLog(
          id: 'l1',
          habitId: 'h6',
          userId: userId,
          date: baseMonday,
          status: CheckInStatus.skipped,
          loggedAt: DateTime(2026, 11, 16, 8, 0),
        ),
        HabitLog(
          id: 'l2',
          habitId: 'h6',
          userId: userId,
          date: baseMonday,
          status: CheckInStatus.completed,
          loggedAt: DateTime(2026, 11, 16, 20, 0), // Log sau
        ),
      ];

      final streak = StreakCalculator.calculate(habit, logs, referenceDate: baseMonday);

      // Chỉ tính 1 lần hoàn thành
      expect(streak.totalDueDays, equals(1));
      expect(streak.totalCompletions, equals(1));
      expect(streak.totalSkipped, equals(0));
      expect(streak.currentStreak, equals(1));
    });

    test('getDayStatus identifies completed, skipped, restDay, missed, pending, and future accurately', () {
      final habit = Habit(
        id: 'h7',
        ownerUid: userId,
        name: 'Chạy bộ',
        frequency: const HabitFrequency.weekdays(), // Mon-Fri
        createdAt: baseMonday,
      );

      final t2 = baseMonday; // Mon
      final t3 = baseMonday.add(const Duration(days: 1)); // Tue
      final t4 = baseMonday.add(const Duration(days: 2)); // Wed (missed)
      final t6 = baseMonday.add(const Duration(days: 4)); // Fri (today pending)
      final t7 = baseMonday.add(const Duration(days: 5)); // Sat (rest day)
      final nextMon = baseMonday.add(const Duration(days: 7)); // Next Mon (future)

      final logs = [
        HabitLog(id: 'l1', habitId: 'h7', userId: userId, date: t2, status: CheckInStatus.completed),
        HabitLog(id: 'l2', habitId: 'h7', userId: userId, date: t3, status: CheckInStatus.skipped),
      ];

      final statusT2 = StreakCalculator.getDayStatus(habit, logs, t2, referenceDate: t6);
      final statusT3 = StreakCalculator.getDayStatus(habit, logs, t3, referenceDate: t6);
      final statusT4 = StreakCalculator.getDayStatus(habit, logs, t4, referenceDate: t6);
      final statusT6 = StreakCalculator.getDayStatus(habit, logs, t6, referenceDate: t6);
      final statusT7 = StreakCalculator.getDayStatus(habit, logs, t7, referenceDate: t6);
      final statusFuture = StreakCalculator.getDayStatus(habit, logs, nextMon, referenceDate: t6);

      expect(statusT2, equals(HabitDayStatus.completed));
      expect(statusT3, equals(HabitDayStatus.skipped));
      expect(statusT4, equals(HabitDayStatus.missed));
      expect(statusT6, equals(HabitDayStatus.pending));
      expect(statusT7, equals(HabitDayStatus.restDay));
      expect(statusFuture, equals(HabitDayStatus.future));
    });

    test('getWeekStatus returns exactly 7 items from Monday to Sunday', () {
      final habit = Habit(
        id: 'h8',
        ownerUid: userId,
        name: 'Lối sống lành mạnh',
        frequency: const HabitFrequency.daily(),
        createdAt: baseMonday,
      );

      final weekStatus = StreakCalculator.getWeekStatus(habit, [], baseMonday);
      expect(weekStatus.length, equals(7));
      expect(weekStatus[0].date.weekday, equals(DateTime.monday));
      expect(weekStatus[6].date.weekday, equals(DateTime.sunday));
    });
  });
}
