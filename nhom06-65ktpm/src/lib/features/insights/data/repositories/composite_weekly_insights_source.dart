import '../../../../core/utils/date_helper.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import '../../../habits/domain/entities/habit_log.dart';
import '../../../habits/domain/repositories/habit_repository.dart';
import '../../../nutrition/domain/entities/meal_log.dart';
import '../../../nutrition/domain/repositories/meal_log_repository.dart';
import '../../../sleep/domain/repositories/sleep_repository.dart';
import '../../domain/repositories/weekly_insights_source.dart';

/// Adapter kết nối trực tiếp các repository thật của các module đã tích hợp:
/// - `#4`: [HabitRepository]
/// - `#5`: [SleepRepository]
/// - `#8`: [ActivityRepository]
/// - `#11`: [MealLogRepository] (tùy chọn)
class CompositeWeeklyInsightsSource implements WeeklyInsightsSource {
  final HabitRepository habitRepository;
  final SleepRepository sleepRepository;
  final ActivityRepository activityRepository;
  final MealLogRepository? mealLogRepository;

  const CompositeWeeklyInsightsSource({
    required this.habitRepository,
    required this.sleepRepository,
    required this.activityRepository,
    this.mealLogRepository,
  });

  @override
  Future<WeeklyInsightsRawData> loadWeeklyData({
    required String ownerUid,
    required DateTime weekStart,
    required DateTime weekEnd,
    required DateTime referenceDate,
  }) async {
    final habits = await habitRepository.getHabits(ownerUid: ownerUid);
    final habitLogs = <HabitLog>[];
    for (final habit in habits) {
      // Không cắt `fromDate` về đầu tuần để StreakCalculator tính đúng chuỗi streak xuyên nhiều tuần.
      final logs = await habitRepository.getHabitLogs(
        habit.id,
        toDate: referenceDate,
      );
      habitLogs.addAll(logs);
    }

    // Lấy dư 1 ngày ở hai đầu tuần để không bỏ sót giấc ngủ vắt qua nửa đêm (wakeDate rơi vào Thứ Hai).
    final sleepLogs = await sleepRepository.getSleepLogs(
      ownerUid: ownerUid,
      fromDate: DateHelper.shiftDays(weekStart, -1),
      toDate: DateHelper.shiftDays(weekEnd, 1),
    );
    final sleepWindow = await sleepRepository.getSleepWindow(ownerUid);
    final activitySessions = await activityRepository.getSessions(
      ownerUid: ownerUid,
    );
    final mealLogs = mealLogRepository == null
        ? const <MealLog>[]
        : await mealLogRepository!.getMealLogs(ownerUid: ownerUid);

    return WeeklyInsightsRawData(
      habits: habits,
      habitLogs: habitLogs,
      activitySessions: activitySessions,
      sleepLogs: sleepLogs,
      sleepWindow: sleepWindow,
      mealLogs: mealLogs,
    );
  }
}
