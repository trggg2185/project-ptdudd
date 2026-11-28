import '../../../activity/domain/entities/activity_session.dart';
import '../../../habits/domain/entities/habit.dart';
import '../../../habits/domain/entities/habit_log.dart';
import '../../../nutrition/domain/entities/meal_log.dart';
import '../../../sleep/domain/entities/sleep_log.dart';
import '../../../sleep/domain/entities/sleep_window.dart';

/// Tập dữ liệu thô theo tài khoản phục vụ tính toán tổng kết tuần.
class WeeklyInsightsRawData {
  final List<Habit> habits;
  final List<HabitLog> habitLogs;
  final List<ActivitySession> activitySessions;
  final List<SleepLog> sleepLogs;
  final SleepWindow? sleepWindow;
  final List<MealLog> mealLogs;

  const WeeklyInsightsRawData({
    this.habits = const [],
    this.habitLogs = const [],
    this.activitySessions = const [],
    this.sleepLogs = const [],
    this.sleepWindow,
    this.mealLogs = const [],
  });
}

/// Interface nguồn dữ liệu tổng hợp tuần (cho phép hoán đổi giữa fixture/mock và repository thật).
abstract interface class WeeklyInsightsSource {
  Future<WeeklyInsightsRawData> loadWeeklyData({
    required String ownerUid,
    required DateTime weekStart,
    required DateTime weekEnd,
    required DateTime referenceDate,
  });
}
