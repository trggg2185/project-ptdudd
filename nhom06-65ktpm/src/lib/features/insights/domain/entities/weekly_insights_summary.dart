import '../../../sleep/domain/logic/sleep_schedule_analyzer.dart';
import 'insight_data_source.dart';

/// Trạng thái chi tiết của một thói quen trong từng ngày thuộc tuần tổng kết.
///
/// Phân biệt tường minh giữa "chưa ghi nhận" (`unlogged`, `pendingToday`),
/// "không hoàn thành" (`failed`), "bỏ qua có lý do" (`skipped`),
/// "ngày nghỉ / tạm dừng" (`restOrPaused`) và ngày chưa áp dụng (`notApplicable`, `upcoming`).
enum HabitDayResolution {
  completed('Hoàn thành'),
  skipped('Bỏ qua có lý do'),
  failed('Không hoàn thành'),
  unlogged('Chưa ghi nhận'),
  pendingToday('Chưa ghi nhận (hôm nay)'),
  upcoming('Chưa tới hạn'),
  restOrPaused('Ngày nghỉ / Tạm dừng'),
  notApplicable('Trước ngày tạo thói quen');

  const HabitDayResolution(this.label);

  final String label;
}

/// Dữ liệu trạng thái một ngày của một thói quen trong tuần.
class HabitWeeklyDayCell {
  final DateTime date;
  final HabitDayResolution resolution;

  const HabitWeeklyDayCell({required this.date, required this.resolution});
}

/// Chi tiết tổng hợp tuần cho từng thói quen riêng lẻ.
class HabitWeeklyBreakdown {
  final String habitId;
  final String habitName;
  final bool isActive;
  final int currentStreak;
  final int longestStreak;
  final int dueSlotsElapsed;
  final int completedOnDueCount;
  final int bonusRestDayCompletedCount;
  final int skippedCount;
  final int explicitFailedCount;
  final int unloggedPastDueCount;
  final int pendingTodayCount;
  final int upcomingDueCount;
  final int restDaysCount;

  /// Tỷ lệ hoàn thành trên các ngày đến hạn đã qua/đã ghi nhận (0.0–100.0).
  /// Trả `null` khi tuần chưa phát sinh ngày đến hạn nào (`dueSlotsElapsed == 0`).
  final double? completionRatePercent;

  /// 7 ô trạng thái từ Thứ Hai đến Chủ Nhật.
  final List<HabitWeeklyDayCell> days;

  const HabitWeeklyBreakdown({
    required this.habitId,
    required this.habitName,
    required this.isActive,
    required this.currentStreak,
    required this.longestStreak,
    required this.dueSlotsElapsed,
    required this.completedOnDueCount,
    required this.bonusRestDayCompletedCount,
    required this.skippedCount,
    required this.explicitFailedCount,
    required this.unloggedPastDueCount,
    required this.pendingTodayCount,
    required this.upcomingDueCount,
    required this.restDaysCount,
    required this.completionRatePercent,
    required this.days,
  });

  int get totalCompletedCount =>
      completedOnDueCount + bonusRestDayCompletedCount;

  int get totalUnloggedCount => unloggedPastDueCount + pendingTodayCount;
}

/// Tổng hợp tỷ lệ hoàn thành và chuỗi streak thói quen theo tuần.
class WeeklyHabitInsights {
  final int totalHabitsCount;
  final int activeHabitsCount;
  final int dueSlotsElapsed;
  final int completedOnDueCount;
  final int bonusRestDayCompletedCount;
  final int skippedCount;
  final int explicitFailedCount;
  final int unloggedPastDueCount;
  final int pendingTodayCount;
  final int upcomingDueCount;
  final int restDaysCount;

  /// Tỷ lệ hoàn thành tổng hợp của tuần (0.0–100.0), `null` nếu chưa có lượt đến hạn nào.
  final double? completionRatePercent;

  /// Tỷ lệ hoàn thành tính riêng trên các lượt đã có ghi nhận (hoàn thành / bỏ qua / không hoàn thành),
  /// giúp tách biệt rõ với số ngày chưa ghi nhận.
  final double? recordedCompletionRatePercent;

  /// Chuỗi streak hiện tại cao nhất trong các thói quen của tài khoản.
  final int bestCurrentStreak;

  /// Kỷ lục streak dài nhất trong lịch sử các thói quen của tài khoản.
  final int bestLongestStreak;

  /// Số thói quen đang duy trì chuỗi `currentStreak > 0`.
  final int activeStreakHabitCount;

  final List<HabitWeeklyBreakdown> perHabit;
  final InsightDataSource dataSource;

  const WeeklyHabitInsights({
    required this.totalHabitsCount,
    required this.activeHabitsCount,
    required this.dueSlotsElapsed,
    required this.completedOnDueCount,
    required this.bonusRestDayCompletedCount,
    required this.skippedCount,
    required this.explicitFailedCount,
    required this.unloggedPastDueCount,
    required this.pendingTodayCount,
    required this.upcomingDueCount,
    required this.restDaysCount,
    required this.completionRatePercent,
    required this.recordedCompletionRatePercent,
    required this.bestCurrentStreak,
    required this.bestLongestStreak,
    required this.activeStreakHabitCount,
    required this.perHabit,
    this.dataSource = InsightDataSource.manualInput,
  });

  int get totalCompletedCount =>
      completedOnDueCount + bonusRestDayCompletedCount;

  int get totalUnloggedCount => unloggedPastDueCount + pendingTodayCount;

  int get recordedDueCount =>
      completedOnDueCount + skippedCount + explicitFailedCount;

  bool get hasAnyRecordedActivity =>
      totalCompletedCount > 0 || skippedCount > 0 || explicitFailedCount > 0;
}

/// Tổng hợp thời lượng tập luyện của một ngày trong tuần.
class DailyActivitySummary {
  final DateTime date;
  final int sessionCount;
  final int totalDurationSeconds;
  final double totalEstimatedDistanceMeters;
  final bool isFuture;
  final Set<InsightDataSource> dataSources;

  const DailyActivitySummary({
    required this.date,
    required this.sessionCount,
    required this.totalDurationSeconds,
    required this.totalEstimatedDistanceMeters,
    required this.isFuture,
    required this.dataSources,
  });

  bool get hasData => sessionCount > 0;

  Duration get totalDuration => Duration(seconds: totalDurationSeconds);
}

/// Tổng hợp thời lượng vận động/tập luyện theo tuần.
class WeeklyActivityInsights {
  final int sessionCount;
  final int totalDurationSeconds;
  final double totalEstimatedDistanceMeters;
  final int activeDaysCount;

  /// Số ngày đã qua trong tuần chưa ghi nhận buổi tập nào ("Chưa ghi nhận", không tính là thất bại).
  final int unloggedDaysCount;

  final int manualSessionCount;
  final int gpsSessionCount;
  final int unknownSourceSessionCount;
  final List<DailyActivitySummary> dailySummaries;
  final Set<InsightDataSource> dataSources;

  const WeeklyActivityInsights({
    required this.sessionCount,
    required this.totalDurationSeconds,
    required this.totalEstimatedDistanceMeters,
    required this.activeDaysCount,
    required this.unloggedDaysCount,
    required this.manualSessionCount,
    required this.gpsSessionCount,
    this.unknownSourceSessionCount = 0,
    required this.dailySummaries,
    required this.dataSources,
  });

  bool get hasData => sessionCount > 0;

  Duration get totalDuration => Duration(seconds: totalDurationSeconds);

  int get totalDurationMinutes => totalDurationSeconds ~/ 60;

  /// Chuỗi hiển thị thời lượng tập dễ đọc (trả "Chưa ghi nhận" nếu tuần chưa có buổi tập).
  String get formattedTotalDuration {
    if (sessionCount == 0 || totalDurationSeconds <= 0) {
      return 'Chưa ghi nhận';
    }
    final totalMinutes = (totalDurationSeconds / 60).round();
    if (totalMinutes <= 0) {
      return '$totalDurationSeconds giây';
    }
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours == 0) return '$mins phút';
    if (mins == 0) return '$hours giờ';
    return '$hours giờ $mins phút';
  }
}

/// Tổng hợp giấc ngủ tự ghi nhận theo tuần (7 ngày Thứ Hai – Chủ Nhật).
class WeeklySleepInsights {
  final int totalLogsCount;
  final int loggedDaysCount;

  /// Số ngày đã qua trong tuần chưa có bản ghi giấc ngủ ("Chưa ghi nhận", không tính là 0 giờ ngủ).
  final int unloggedDaysCount;

  final int totalDurationMinutes;

  /// Thời lượng ngủ trung bình trên các ngày ĐÃ ghi nhận (`null` nếu chưa ghi ngày nào).
  final Duration? averageDuration;

  /// Mức tỉnh táo tự đánh giá trung bình (1.0–5.0), `null` nếu chưa có bản ghi.
  final double? averageAlertnessScore;

  /// Độ lệch giờ đi ngủ trung bình (phút) theo đồng hồ vòng tròn so với `SleepWindow` người dùng đặt.
  final int? averageBedtimeDeviationMinutes;

  /// Chỉ số đều đặn giấc ngủ tương đối (0–100) — không phải điểm sức khỏe y khoa.
  final int? regularityIndex;

  /// Số giấc ngủ ban ngày (phổ biến với người làm ca đêm).
  final int daytimeSleepCount;

  /// Số giấc ngủ vắt qua mốc nửa đêm (00:00).
  final int crossesMidnightCount;

  /// 7 ngày từ Thứ Hai đến Chủ Nhật.
  final List<DailySleepSummary> days;

  final InsightDataSource dataSource;

  const WeeklySleepInsights({
    required this.totalLogsCount,
    required this.loggedDaysCount,
    required this.unloggedDaysCount,
    required this.totalDurationMinutes,
    required this.averageDuration,
    required this.averageAlertnessScore,
    required this.averageBedtimeDeviationMinutes,
    required this.regularityIndex,
    required this.daytimeSleepCount,
    required this.crossesMidnightCount,
    required this.days,
    this.dataSource = InsightDataSource.selfReported,
  });

  bool get hasData => totalLogsCount > 0;

  String get formattedAverageDuration {
    final avg = averageDuration;
    if (avg == null) return 'Chưa ghi nhận';
    final totalMins = avg.inMinutes;
    final hours = totalMins ~/ 60;
    final mins = totalMins % 60;
    if (hours == 0) return '$mins phút';
    if (mins == 0) return '$hours giờ';
    return '$hours giờ $mins phút';
  }
}

/// Tổng hợp bổ sung nhật ký bữa ăn trong tuần (phối hợp Issue #11).
class WeeklyMealInsights {
  final int totalLogsCount;
  final int loggedDaysCount;
  final int unloggedDaysCount;
  final int withPhotoCount;
  final int manualOnlyCount;
  final Set<InsightDataSource> dataSources;

  const WeeklyMealInsights({
    required this.totalLogsCount,
    required this.loggedDaysCount,
    required this.unloggedDaysCount,
    required this.withPhotoCount,
    required this.manualOnlyCount,
    required this.dataSources,
  });

  bool get hasData => totalLogsCount > 0;
}

/// Bản tổng hợp hoàn chỉnh của Dashboard & tổng kết tuần cho một tài khoản (`ownerUid`).
class WeeklyInsightsSummary {
  static const String nonMedicalDisclaimer =
      'Số liệu tổng hợp phản ánh mức độ ghi nhận kỷ luật cá nhân từ nhật ký tự khai báo và thiết bị trong phiên, không phải điểm sức khỏe hay đánh giá y khoa.';

  final String ownerUid;

  /// Thứ Hai đầu tuần (chuẩn hóa 00:00 địa phương).
  final DateTime weekStart;

  /// Chủ Nhật cuối tuần (chuẩn hóa 00:00 địa phương).
  final DateTime weekEnd;

  /// Ngày mốc đánh giá (mặc định là hôm nay, chuẩn hóa 00:00 địa phương).
  final DateTime referenceDate;

  /// Số ngày trong tuần `[weekStart..weekEnd]` đã trôi qua tính tới [referenceDate] (0..7).
  final int elapsedDaysInWeek;

  final WeeklyHabitInsights habits;
  final WeeklyActivityInsights activity;
  final WeeklySleepInsights sleep;
  final WeeklyMealInsights meals;

  const WeeklyInsightsSummary({
    required this.ownerUid,
    required this.weekStart,
    required this.weekEnd,
    required this.referenceDate,
    required this.elapsedDaysInWeek,
    required this.habits,
    required this.activity,
    required this.sleep,
    required this.meals,
  });

  bool get hasAnyData =>
      habits.hasAnyRecordedActivity ||
      activity.hasData ||
      sleep.hasData ||
      meals.hasData;
}
