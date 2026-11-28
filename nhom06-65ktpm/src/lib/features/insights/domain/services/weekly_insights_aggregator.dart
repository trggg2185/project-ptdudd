import 'dart:math';

import '../../../../core/utils/date_helper.dart';
import '../../../activity/domain/entities/activity_session.dart';
import '../../../habits/domain/entities/habit.dart';
import '../../../habits/domain/entities/habit_log.dart';
import '../../../habits/domain/logic/streak_calculator.dart';
import '../../../nutrition/domain/entities/meal_log.dart';
import '../../../sleep/domain/entities/sleep_log.dart';
import '../../../sleep/domain/entities/sleep_window.dart';
import '../../../sleep/domain/logic/sleep_schedule_analyzer.dart';
import '../entities/insight_data_source.dart';
import '../entities/weekly_insights_summary.dart';

/// Dịch vụ thuần Dart tổng hợp số liệu theo tuần (Thứ Hai – Chủ Nhật) từ dữ liệu
/// của các module `#4` (thói quen/streak), `#5` (giấc ngủ tự ghi), `#8` (vận động/GPS)
/// và `#11` (nhật ký bữa ăn).
///
/// Nguyên tắc cốt lõi:
/// 1. Cô lập chặt theo `ownerUid`: bỏ qua mọi bản ghi thuộc tài khoản khác.
/// 2. Khử trùng lặp theo ID / ngày địa phương để không tính đúp khi đồng bộ lại.
/// 3. Phân biệt rạch ròi "chưa ghi nhận" với "không hoàn thành" (không tính ngày thiếu dữ liệu
///    là 0 giờ ngủ và không biến ngày chưa tới hạn thành thất bại).
/// 4. Tái sử dụng [StreakCalculator] (#4) và [SleepScheduleAnalyzer] (#5) để giữ nhất quán toàn app.
class WeeklyInsightsAggregator {
  const WeeklyInsightsAggregator();

  /// Xác định Thứ Hai đầu tuần chứa [date] theo ngày lịch địa phương.
  static DateTime startOfWeek(DateTime date) {
    final norm = DateHelper.normalize(date);
    return DateHelper.shiftDays(norm, 1 - norm.weekday);
  }

  /// Xác định Chủ Nhật cuối tuần chứa [date] theo ngày lịch địa phương.
  static DateTime endOfWeek(DateTime date) {
    return DateHelper.shiftDays(startOfWeek(date), 6);
  }

  /// Tổng hợp đầy đủ tỷ lệ hoàn thành, streak, thời lượng tập, giấc ngủ tự ghi và bữa ăn theo tuần.
  WeeklyInsightsSummary aggregate({
    required String ownerUid,
    required List<Habit> habits,
    required List<HabitLog> habitLogs,
    required List<ActivitySession> activitySessions,
    required List<SleepLog> sleepLogs,
    SleepWindow? sleepWindow,
    List<MealLog> mealLogs = const [],
    DateTime? weekAnchorDate,
    DateTime? referenceDate,
  }) {
    final trimmedOwner = ownerUid.trim();
    if (trimmedOwner.isEmpty) {
      throw ArgumentError.value(
        ownerUid,
        'ownerUid',
        'Thiếu định danh chủ tài khoản để tổng hợp tuần.',
      );
    }

    final ref = DateHelper.normalize(referenceDate ?? DateTime.now());
    final weekStart = startOfWeek(weekAnchorDate ?? ref);
    final weekEnd = DateHelper.shiftDays(weekStart, 6);
    final elapsedDays = _countElapsedDaysInWeek(weekStart, weekEnd, ref);

    final habitInsights = _aggregateHabits(
      ownerUid: trimmedOwner,
      habits: habits,
      habitLogs: habitLogs,
      weekStart: weekStart,
      ref: ref,
    );

    final activityInsights = _aggregateActivity(
      ownerUid: trimmedOwner,
      sessions: activitySessions,
      weekStart: weekStart,
      weekEnd: weekEnd,
      ref: ref,
      elapsedDays: elapsedDays,
    );

    final sleepInsights = _aggregateSleep(
      ownerUid: trimmedOwner,
      sleepLogs: sleepLogs,
      sleepWindow: sleepWindow,
      weekStart: weekStart,
      weekEnd: weekEnd,
      ref: ref,
      elapsedDays: elapsedDays,
    );

    final mealInsights = _aggregateMeals(
      ownerUid: trimmedOwner,
      mealLogs: mealLogs,
      weekStart: weekStart,
      weekEnd: weekEnd,
      ref: ref,
      elapsedDays: elapsedDays,
    );

    return WeeklyInsightsSummary(
      ownerUid: trimmedOwner,
      weekStart: weekStart,
      weekEnd: weekEnd,
      referenceDate: ref,
      elapsedDaysInWeek: elapsedDays,
      habits: habitInsights,
      activity: activityInsights,
      sleep: sleepInsights,
      meals: mealInsights,
    );
  }

  static int _countElapsedDaysInWeek(
    DateTime weekStart,
    DateTime weekEnd,
    DateTime ref,
  ) {
    if (ref.isBefore(weekStart)) return 0;
    if (!ref.isBefore(weekEnd)) return 7;
    return ref.difference(weekStart).inDays + 1;
  }

  WeeklyHabitInsights _aggregateHabits({
    required String ownerUid,
    required List<Habit> habits,
    required List<HabitLog> habitLogs,
    required DateTime weekStart,
    required DateTime ref,
  }) {
    final ownedHabits = <String, Habit>{};
    for (final habit in habits) {
      if (habit.ownerUid == ownerUid) {
        ownedHabits[habit.id] = habit;
      }
    }

    final logsByHabit = <String, List<HabitLog>>{};
    for (final log in habitLogs) {
      if (log.userId != ownerUid) continue;
      if (!ownedHabits.containsKey(log.habitId)) continue;
      logsByHabit.putIfAbsent(log.habitId, () => []).add(log);
    }

    var totalDueElapsed = 0;
    var totalCompletedOnDue = 0;
    var totalBonusRestDay = 0;
    var totalSkipped = 0;
    var totalExplicitFailed = 0;
    var totalUnloggedPastDue = 0;
    var totalPendingToday = 0;
    var totalUpcomingDue = 0;
    var totalRestDays = 0;
    var bestCurrentStreak = 0;
    var bestLongestStreak = 0;
    var activeStreakHabitCount = 0;
    var activeHabitsCount = 0;

    final breakdowns = <HabitWeeklyBreakdown>[];

    for (final habit in ownedHabits.values) {
      if (habit.isActive) {
        activeHabitsCount++;
      }

      final habitSpecificLogs = logsByHabit[habit.id] ?? const <HabitLog>[];

      // Khử trùng lặp log theo ngày địa phương và loại bỏ log tương lai (khớp StreakCalculator).
      final uniqueLogsByDay = <String, HabitLog>{};
      DateTime effectiveStart = DateHelper.normalize(habit.createdAt);
      for (final log in habitSpecificLogs) {
        if (DateHelper.isFutureDay(log.date, ref)) continue;
        final key = DateHelper.formatIsoDate(log.date);
        final existing = uniqueLogsByDay[key];
        if (existing == null || log.loggedAt.isAfter(existing.loggedAt)) {
          uniqueLogsByDay[key] = log;
        }
        if (log.date.isBefore(effectiveStart)) {
          effectiveStart = log.date;
        }
      }

      final streakInfo = StreakCalculator.calculate(
        habit,
        habitSpecificLogs,
        referenceDate: ref,
      );
      bestCurrentStreak = max(bestCurrentStreak, streakInfo.currentStreak);
      bestLongestStreak = max(bestLongestStreak, streakInfo.longestStreak);
      if (streakInfo.currentStreak > 0) {
        activeStreakHabitCount++;
      }

      var dueElapsed = 0;
      var completedOnDue = 0;
      var bonusRestCompleted = 0;
      var skipped = 0;
      var explicitFailed = 0;
      var unloggedPastDue = 0;
      var pendingToday = 0;
      var upcomingDue = 0;
      var restDays = 0;
      final dayCells = <HabitWeeklyDayCell>[];

      for (var i = 0; i < 7; i++) {
        final day = DateHelper.shiftDays(weekStart, i);
        final key = DateHelper.formatIsoDate(day);
        final log = uniqueLogsByDay[key];

        if (day.isBefore(effectiveStart)) {
          dayCells.add(
            HabitWeeklyDayCell(
              date: day,
              resolution: HabitDayResolution.notApplicable,
            ),
          );
          continue;
        }

        if (DateHelper.isFutureDay(day, ref)) {
          if (habit.isPausedOn(day) || !habit.getFrequencyOn(day).isDueOn(day)) {
            restDays++;
            dayCells.add(
              HabitWeeklyDayCell(
                date: day,
                resolution: HabitDayResolution.restOrPaused,
              ),
            );
          } else {
            upcomingDue++;
            dayCells.add(
              HabitWeeklyDayCell(
                date: day,
                resolution: HabitDayResolution.upcoming,
              ),
            );
          }
          continue;
        }

        if (habit.isPausedOn(day)) {
          restDays++;
          dayCells.add(
            HabitWeeklyDayCell(
              date: day,
              resolution: HabitDayResolution.restOrPaused,
            ),
          );
          continue;
        }

        final isDue = habit.getFrequencyOn(day).isDueOn(day);
        final isToday = DateHelper.isSameDay(day, ref);

        if (!isDue) {
          if (log != null && log.status == CheckInStatus.completed) {
            bonusRestCompleted++;
            dayCells.add(
              HabitWeeklyDayCell(
                date: day,
                resolution: HabitDayResolution.completed,
              ),
            );
          } else {
            restDays++;
            dayCells.add(
              HabitWeeklyDayCell(
                date: day,
                resolution: HabitDayResolution.restOrPaused,
              ),
            );
          }
          continue;
        }

        // Ngày đến hạn (đã qua hoặc hôm nay)
        if (log != null) {
          dueElapsed++;
          switch (log.status) {
            case CheckInStatus.completed:
              completedOnDue++;
              dayCells.add(
                HabitWeeklyDayCell(
                  date: day,
                  resolution: HabitDayResolution.completed,
                ),
              );
            case CheckInStatus.skipped:
              skipped++;
              dayCells.add(
                HabitWeeklyDayCell(
                  date: day,
                  resolution: HabitDayResolution.skipped,
                ),
              );
            case CheckInStatus.failed:
              explicitFailed++;
              dayCells.add(
                HabitWeeklyDayCell(
                  date: day,
                  resolution: HabitDayResolution.failed,
                ),
              );
          }
        } else if (isToday) {
          // Hôm nay chưa bấm check-in: ghi nhận là "Chưa ghi nhận (hôm nay)", không phạt.
          pendingToday++;
          dayCells.add(
            HabitWeeklyDayCell(
              date: day,
              resolution: HabitDayResolution.pendingToday,
            ),
          );
        } else {
          // Ngày quá khứ đến hạn nhưng không có log: phân biệt rõ là "Chưa ghi nhận",
          // không gộp nhầm vào explicitFailed.
          dueElapsed++;
          unloggedPastDue++;
          dayCells.add(
            HabitWeeklyDayCell(
              date: day,
              resolution: HabitDayResolution.unlogged,
            ),
          );
        }
      }

      final habitRate = _percent(completedOnDue, dueElapsed);

      breakdowns.add(
        HabitWeeklyBreakdown(
          habitId: habit.id,
          habitName: habit.name,
          isActive: habit.isActive,
          currentStreak: streakInfo.currentStreak,
          longestStreak: streakInfo.longestStreak,
          dueSlotsElapsed: dueElapsed,
          completedOnDueCount: completedOnDue,
          bonusRestDayCompletedCount: bonusRestCompleted,
          skippedCount: skipped,
          explicitFailedCount: explicitFailed,
          unloggedPastDueCount: unloggedPastDue,
          pendingTodayCount: pendingToday,
          upcomingDueCount: upcomingDue,
          restDaysCount: restDays,
          completionRatePercent: habitRate,
          days: List<HabitWeeklyDayCell>.unmodifiable(dayCells),
        ),
      );

      totalDueElapsed += dueElapsed;
      totalCompletedOnDue += completedOnDue;
      totalBonusRestDay += bonusRestCompleted;
      totalSkipped += skipped;
      totalExplicitFailed += explicitFailed;
      totalUnloggedPastDue += unloggedPastDue;
      totalPendingToday += pendingToday;
      totalUpcomingDue += upcomingDue;
      totalRestDays += restDays;
    }

    final totalRecordedDue =
        totalCompletedOnDue + totalSkipped + totalExplicitFailed;

    return WeeklyHabitInsights(
      totalHabitsCount: ownedHabits.length,
      activeHabitsCount: activeHabitsCount,
      dueSlotsElapsed: totalDueElapsed,
      completedOnDueCount: totalCompletedOnDue,
      bonusRestDayCompletedCount: totalBonusRestDay,
      skippedCount: totalSkipped,
      explicitFailedCount: totalExplicitFailed,
      unloggedPastDueCount: totalUnloggedPastDue,
      pendingTodayCount: totalPendingToday,
      upcomingDueCount: totalUpcomingDue,
      restDaysCount: totalRestDays,
      completionRatePercent: _percent(totalCompletedOnDue, totalDueElapsed),
      recordedCompletionRatePercent: _percent(
        totalCompletedOnDue,
        totalRecordedDue,
      ),
      bestCurrentStreak: bestCurrentStreak,
      bestLongestStreak: bestLongestStreak,
      activeStreakHabitCount: activeStreakHabitCount,
      perHabit: List<HabitWeeklyBreakdown>.unmodifiable(breakdowns),
    );
  }

  WeeklyActivityInsights _aggregateActivity({
    required String ownerUid,
    required List<ActivitySession> sessions,
    required DateTime weekStart,
    required DateTime weekEnd,
    required DateTime ref,
    required int elapsedDays,
  }) {
    final uniqueSessions = <String, ActivitySession>{};
    for (final session in sessions) {
      if (session.ownerUid != ownerUid) continue;
      final sessionDay = DateHelper.normalize(session.startedAt.toLocal());
      if (sessionDay.isBefore(weekStart) ||
          sessionDay.isAfter(weekEnd) ||
          DateHelper.isFutureDay(sessionDay, ref)) {
        continue;
      }
      uniqueSessions[session.id] = session;
    }

    final byDay = <String, List<ActivitySession>>{};
    var totalSeconds = 0;
    var totalDistance = 0.0;
    var manualCount = 0;
    var gpsCount = 0;
    final allSources = <InsightDataSource>{};

    for (final session in uniqueSessions.values) {
      final sessionDay = DateHelper.normalize(session.startedAt.toLocal());
      final key = DateHelper.formatIsoDate(sessionDay);
      byDay.putIfAbsent(key, () => []).add(session);

      final durationSec = max(0, session.durationSeconds);
      final distance = max(0.0, session.estimatedDistanceMeters);
      totalSeconds += durationSec;
      totalDistance += distance;

      final source = _resolveActivitySource(session);
      allSources.add(source);
      if (source == InsightDataSource.deviceGps) {
        gpsCount++;
      } else {
        manualCount++;
      }
    }

    var activeDays = 0;
    final dailySummaries = List<DailyActivitySummary>.generate(7, (index) {
      final day = DateHelper.shiftDays(weekStart, index);
      final key = DateHelper.formatIsoDate(day);
      final daySessions = byDay[key] ?? const <ActivitySession>[];
      final isFuture = DateHelper.isFutureDay(day, ref);
      if (daySessions.isNotEmpty) {
        activeDays++;
      }
      final daySeconds = daySessions.fold<int>(
        0,
        (sum, s) => sum + max(0, s.durationSeconds),
      );
      final dayDistance = daySessions.fold<double>(
        0.0,
        (sum, s) => sum + max(0.0, s.estimatedDistanceMeters),
      );
      final daySources = daySessions.map(_resolveActivitySource).toSet();
      return DailyActivitySummary(
        date: day,
        sessionCount: daySessions.length,
        totalDurationSeconds: daySeconds,
        totalEstimatedDistanceMeters: dayDistance,
        isFuture: isFuture,
        dataSources: Set<InsightDataSource>.unmodifiable(daySources),
      );
    });

    final unloggedDays = max(0, elapsedDays - activeDays);

    return WeeklyActivityInsights(
      sessionCount: uniqueSessions.length,
      totalDurationSeconds: totalSeconds,
      totalEstimatedDistanceMeters: totalDistance,
      activeDaysCount: activeDays,
      unloggedDaysCount: unloggedDays,
      manualSessionCount: manualCount,
      gpsSessionCount: gpsCount,
      dailySummaries: List<DailyActivitySummary>.unmodifiable(dailySummaries),
      dataSources: Set<InsightDataSource>.unmodifiable(allSources),
    );
  }

  static InsightDataSource _resolveActivitySource(ActivitySession session) {
    return session.resolvedSource == ActivityInputSource.gps
        ? InsightDataSource.deviceGps
        : InsightDataSource.manualInput;
  }

  WeeklySleepInsights _aggregateSleep({
    required String ownerUid,
    required List<SleepLog> sleepLogs,
    required SleepWindow? sleepWindow,
    required DateTime weekStart,
    required DateTime weekEnd,
    required DateTime ref,
    required int elapsedDays,
  }) {
    final uniqueLogs = <String, SleepLog>{};
    for (final log in sleepLogs) {
      if (log.ownerUid != ownerUid) continue;
      if (log.durationMinutes <= 0) continue;
      final wakeDay = log.wakeDate;
      if (wakeDay.isBefore(weekStart) ||
          wakeDay.isAfter(weekEnd) ||
          DateHelper.isFutureDay(wakeDay, ref)) {
        continue;
      }
      final existing = uniqueLogs[log.id];
      if (existing == null || log.updatedAt.isAfter(existing.updatedAt)) {
        uniqueLogs[log.id] = log;
      }
    }

    final validLogs = uniqueLogs.values.toList()
      ..sort((a, b) => a.sleptAt.compareTo(b.sleptAt));

    final byDay = <String, List<SleepLog>>{};
    var daytimeCount = 0;
    var crossesMidnightCount = 0;

    for (final log in validLogs) {
      final key = DateHelper.formatIsoDate(log.wakeDate);
      byDay.putIfAbsent(key, () => []).add(log);
      if (log.isDaytimeSleep) daytimeCount++;
      if (log.crossesMidnight) crossesMidnightCount++;
    }

    final days = List<DailySleepSummary>.generate(7, (index) {
      final day = DateHelper.shiftDays(weekStart, index);
      final key = DateHelper.formatIsoDate(day);
      final dayLogs = List<SleepLog>.from(byDay[key] ?? const <SleepLog>[])
        ..sort((a, b) => a.sleptAt.compareTo(b.sleptAt));
      return DailySleepSummary(date: day, logs: dayLogs);
    });

    final loggedDays = days.where((d) => d.hasData).toList();
    final unloggedDays = max(0, elapsedDays - loggedDays.length);

    if (validLogs.isEmpty) {
      return WeeklySleepInsights(
        totalLogsCount: 0,
        loggedDaysCount: 0,
        unloggedDaysCount: unloggedDays,
        totalDurationMinutes: 0,
        averageDuration: null,
        averageAlertnessScore: null,
        averageBedtimeDeviationMinutes: null,
        regularityIndex: null,
        daytimeSleepCount: 0,
        crossesMidnightCount: 0,
        days: List<DailySleepSummary>.unmodifiable(days),
      );
    }

    final totalMinutes = loggedDays.fold<int>(
      0,
      (sum, d) => sum + d.totalMinutes,
    );
    final avgMinutes = (totalMinutes / loggedDays.length).round();

    final totalAlertness = validLogs.fold<int>(
      0,
      (sum, log) => sum + log.alertness.score,
    );
    final avgAlertness = double.parse(
      (totalAlertness / validLogs.length).toStringAsFixed(2),
    );

    int? avgBedtimeDeviation;
    int? regularityIndex;

    if (sleepWindow != null) {
      var totalDev = 0;
      for (final log in validLogs) {
        final localStart = log.sleptAt.toLocal();
        final startMin = localStart.hour * 60 + localStart.minute;
        totalDev += SleepScheduleAnalyzer.circularClockDistanceMinutes(
          startMin,
          sleepWindow.startMinute,
        );
      }
      avgBedtimeDeviation = (totalDev / validLogs.length).round();
      regularityIndex = max(
        0,
        min(100, 100 - (avgBedtimeDeviation / 3).round()),
      );
    } else if (validLogs.length >= 2) {
      var pairwiseDiffSum = 0;
      for (var i = 1; i < validLogs.length; i++) {
        final prevStart = validLogs[i - 1].sleptAt.toLocal();
        final currStart = validLogs[i].sleptAt.toLocal();
        pairwiseDiffSum += SleepScheduleAnalyzer.circularClockDistanceMinutes(
          prevStart.hour * 60 + prevStart.minute,
          currStart.hour * 60 + currStart.minute,
        );
      }
      final avgSpread = (pairwiseDiffSum / (validLogs.length - 1)).round();
      regularityIndex = max(0, min(100, 100 - (avgSpread / 3).round()));
    }

    return WeeklySleepInsights(
      totalLogsCount: validLogs.length,
      loggedDaysCount: loggedDays.length,
      unloggedDaysCount: unloggedDays,
      totalDurationMinutes: totalMinutes,
      averageDuration: Duration(minutes: avgMinutes),
      averageAlertnessScore: avgAlertness,
      averageBedtimeDeviationMinutes: avgBedtimeDeviation,
      regularityIndex: regularityIndex,
      daytimeSleepCount: daytimeCount,
      crossesMidnightCount: crossesMidnightCount,
      days: List<DailySleepSummary>.unmodifiable(days),
    );
  }

  WeeklyMealInsights _aggregateMeals({
    required String ownerUid,
    required List<MealLog> mealLogs,
    required DateTime weekStart,
    required DateTime weekEnd,
    required DateTime ref,
    required int elapsedDays,
  }) {
    final uniqueMeals = <String, MealLog>{};
    for (final meal in mealLogs) {
      if (meal.ownerUid != ownerUid) continue;
      final mealDay = DateHelper.normalize(meal.consumedAt.toLocal());
      if (mealDay.isBefore(weekStart) ||
          mealDay.isAfter(weekEnd) ||
          DateHelper.isFutureDay(mealDay, ref)) {
        continue;
      }
      uniqueMeals[meal.id] = meal;
    }

    final loggedDays = <String>{};
    var withPhoto = 0;
    var manualOnly = 0;
    final sources = <InsightDataSource>{};

    for (final meal in uniqueMeals.values) {
      loggedDays.add(DateHelper.formatIsoDate(meal.consumedAt.toLocal()));
      if (meal.hasPhoto || meal.photoSource != null) {
        withPhoto++;
        sources.add(InsightDataSource.cameraOrGallery);
      } else {
        manualOnly++;
        sources.add(InsightDataSource.manualInput);
      }
    }

    return WeeklyMealInsights(
      totalLogsCount: uniqueMeals.length,
      loggedDaysCount: loggedDays.length,
      unloggedDaysCount: max(0, elapsedDays - loggedDays.length),
      withPhotoCount: withPhoto,
      manualOnlyCount: manualOnly,
      dataSources: Set<InsightDataSource>.unmodifiable(sources),
    );
  }

  static double? _percent(int numerator, int denominator) {
    if (denominator <= 0) return null;
    final raw = (numerator / denominator) * 100.0;
    final clamped = raw < 0.0 ? 0.0 : (raw > 100.0 ? 100.0 : raw);
    return double.parse(clamped.toStringAsFixed(1));
  }
}
