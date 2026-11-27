import '../../../../core/utils/date_helper.dart';
import '../entities/weekly_insights_summary.dart';
import '../repositories/weekly_insights_source.dart';
import '../services/weekly_insights_aggregator.dart';

/// Use case tải và tổng hợp Dashboard tuần (tỷ lệ hoàn thành, streak, thời lượng tập,
/// giấc ngủ tự ghi và bữa ăn) cho đúng tài khoản `ownerUid`.
class GetWeeklyInsightsUseCase {
  final WeeklyInsightsSource source;
  final WeeklyInsightsAggregator aggregator;

  const GetWeeklyInsightsUseCase({
    required this.source,
    this.aggregator = const WeeklyInsightsAggregator(),
  });

  Future<WeeklyInsightsSummary> call({
    required String ownerUid,
    DateTime? weekAnchorDate,
    DateTime? referenceDate,
  }) async {
    final trimmedOwner = ownerUid.trim();
    if (trimmedOwner.isEmpty) {
      throw ArgumentError.value(
        ownerUid,
        'ownerUid',
        'Thiếu định danh chủ tài khoản.',
      );
    }

    final ref = DateHelper.normalize(referenceDate ?? DateTime.now());
    final weekStart = WeeklyInsightsAggregator.startOfWeek(
      weekAnchorDate ?? ref,
    );
    final weekEnd = DateHelper.shiftDays(weekStart, 6);

    final raw = await source.loadWeeklyData(
      ownerUid: trimmedOwner,
      weekStart: weekStart,
      weekEnd: weekEnd,
      referenceDate: ref,
    );

    return aggregator.aggregate(
      ownerUid: trimmedOwner,
      habits: raw.habits,
      habitLogs: raw.habitLogs,
      activitySessions: raw.activitySessions,
      sleepLogs: raw.sleepLogs,
      sleepWindow: raw.sleepWindow,
      mealLogs: raw.mealLogs,
      weekAnchorDate: weekStart,
      referenceDate: ref,
    );
  }
}
