import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/activity/data/repositories/in_memory_activity_repository.dart';
import 'package:healthylife/features/activity/data/repositories/supabase_activity_repository.dart';
import 'package:healthylife/features/activity/domain/entities/activity_session.dart';
import 'package:healthylife/features/activity/presentation/controllers/activity_controller.dart';
import 'package:healthylife/features/habits/data/repositories/in_memory_habit_repository.dart';
import 'package:healthylife/features/habits/domain/entities/habit.dart';
import 'package:healthylife/features/habits/domain/entities/habit_frequency.dart';
import 'package:healthylife/features/habits/domain/entities/habit_log.dart';
import 'package:healthylife/features/insights/data/fixtures/sample_weekly_insights_fixture.dart';
import 'package:healthylife/features/insights/data/repositories/composite_weekly_insights_source.dart';
import 'package:healthylife/features/insights/domain/entities/insight_data_source.dart';
import 'package:healthylife/features/insights/domain/entities/weekly_insights_summary.dart';
import 'package:healthylife/features/insights/domain/services/insights_display_formatter.dart';
import 'package:healthylife/features/insights/domain/services/weekly_insights_aggregator.dart';
import 'package:healthylife/features/insights/domain/usecases/get_weekly_insights_usecase.dart';
import 'package:healthylife/features/nutrition/data/repositories/in_memory_meal_log_repository.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_log.dart';
import 'package:healthylife/features/sleep/data/repositories/in_memory_sleep_repository.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_log.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_window.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const aggregator = WeeklyInsightsAggregator();

  group('Tổng hợp tỷ lệ hoàn thành, streak, thời lượng tập và giấc ngủ tự ghi theo tuần (Issue #12 - Tiêu chí 1)', () {
    test('tổng hợp chính xác tuần mẫu cân bằng gồm thói quen, streak xuyên tuần, vận động, giấc ngủ và bữa ăn', () async {
      final useCase = GetWeeklyInsightsUseCase(
        source: FixtureWeeklyInsightsSource(),
      );

      final summary = await useCase(
        ownerUid: 'uid-demo',
        referenceDate: DateTime(2026, 11, 27), // Thứ Sáu
      );

      expect(summary.ownerUid, 'uid-demo');
      expect(summary.weekStart, DateTime(2026, 11, 23)); // Thứ Hai
      expect(summary.weekEnd, DateTime(2026, 11, 29)); // Chủ Nhật
      expect(summary.elapsedDaysInWeek, 5);
      expect(summary.hasAnyData, isTrue);

      // 1. Thói quen & Streak
      final habits = summary.habits;
      expect(habits.totalHabitsCount, 2);
      expect(habits.activeHabitsCount, 2);
      // water: T2,T3,T5 completed (3) + T4 skipped (1) -> 4 due elapsed, T6 pendingToday, T7/CN upcoming
      // workout (T2,T4,T6): T2 completed (1) + T4 failed (1) -> 2 due elapsed, T6 pendingToday
      expect(habits.dueSlotsElapsed, 6);
      expect(habits.completedOnDueCount, 4);
      expect(habits.skippedCount, 1);
      expect(habits.explicitFailedCount, 1);
      expect(habits.unloggedPastDueCount, 0);
      expect(habits.pendingTodayCount, 2);
      expect(habits.upcomingDueCount, 2);
      expect(habits.completionRatePercent, 66.7);
      expect(habits.bestCurrentStreak, 6); // 3 ngày tuần trước + T2, T3 + T4 skipped + T5
      expect(habits.bestLongestStreak, 6);
      expect(habits.activeStreakHabitCount, 1);

      final water = habits.perHabit.firstWhere(
        (h) => h.habitId == 'habit-water',
      );
      expect(water.currentStreak, 6);
      expect(water.completionRatePercent, 75.0);
      expect(water.days, hasLength(7));
      expect(water.days[0].resolution, HabitDayResolution.completed);
      expect(water.days[2].resolution, HabitDayResolution.skipped);
      expect(water.days[4].resolution, HabitDayResolution.pendingToday);
      expect(water.days[5].resolution, HabitDayResolution.upcoming);

      // 2. Thời lượng tập luyện
      final activity = summary.activity;
      expect(activity.hasData, isTrue);
      expect(activity.sessionCount, 2);
      expect(activity.totalDurationSeconds, 3000);
      expect(activity.totalDurationMinutes, 50);
      expect(activity.formattedTotalDuration, '50 phút');
      expect(activity.totalEstimatedDistanceMeters, 3800);
      expect(activity.activeDaysCount, 2);
      expect(activity.unloggedDaysCount, 3);
      expect(activity.gpsSessionCount, 1);
      expect(activity.manualSessionCount, 1);
      expect(
        activity.dataSources,
        equals({InsightDataSource.deviceGps, InsightDataSource.manualInput}),
      );
      expect(activity.dailySummaries, hasLength(7));
      expect(activity.dailySummaries[0].totalDurationSeconds, 1800);
      expect(activity.dailySummaries[3].totalDurationSeconds, 1200);
      expect(activity.dailySummaries[5].isFuture, isTrue);

      // 3. Giấc ngủ tự ghi (trung bình chỉ chia theo 3 ngày có ghi nhận, không tính T4 thiếu dữ liệu là 0 giờ)
      final sleep = summary.sleep;
      expect(sleep.hasData, isTrue);
      expect(sleep.totalLogsCount, 3);
      expect(sleep.loggedDaysCount, 3);
      expect(sleep.unloggedDaysCount, 2);
      expect(sleep.totalDurationMinutes, 450 + 420 + 480);
      expect(sleep.averageDuration, const Duration(minutes: 450));
      expect(sleep.formattedAverageDuration, '7 giờ 30 phút');
      expect(sleep.averageAlertnessScore, 4.0);
      expect(sleep.averageBedtimeDeviationMinutes, 15);
      expect(sleep.regularityIndex, 95);
      expect(sleep.crossesMidnightCount, 3);
      expect(sleep.daytimeSleepCount, 0);
      expect(sleep.dataSource, InsightDataSource.selfReported);
      expect(sleep.days, hasLength(7));

      // 4. Bữa ăn trong tuần
      final meals = summary.meals;
      expect(meals.totalLogsCount, 2);
      expect(meals.loggedDaysCount, 2);
      expect(meals.unloggedDaysCount, 3);
      expect(meals.withPhotoCount, 1);
      expect(meals.manualOnlyCount, 1);
    });

    test('phân biệt rõ chưa ghi nhận với không hoàn thành, ngày trước khi tạo thói quen, tạm dừng và bỏ qua log tương lai', () {
      final midWeekHabit = Habit(
        id: 'h-mid',
        ownerUid: 'uid-a',
        name: 'Đọc sách 15 phút',
        frequency: const HabitFrequency.daily(),
        createdAt: DateTime(2026, 11, 25), // Tạo vào Thứ Tư
        pauseHistory: [
          PauseInterval(
            pausedAt: DateTime(2026, 11, 26), // Tạm dừng Thứ Năm
            resumedAt: DateTime(2026, 11, 27), // Tiếp tục Thứ Sáu
          ),
        ],
      );

      final summary = aggregator.aggregate(
        ownerUid: 'uid-a',
        habits: [midWeekHabit],
        habitLogs: [
          // T4 (25/11) không có log -> unlogged (KHÔNG phải explicitFailed)
          // T7 (28/11) là ngày tương lai so với mốc T6 (27/11) -> phải bị bỏ qua
          HabitLog(
            id: 'hl-future',
            habitId: midWeekHabit.id,
            userId: 'uid-a',
            date: DateTime(2026, 11, 28),
            status: CheckInStatus.completed,
          ),
        ],
        activitySessions: [
          ActivitySession(
            id: 'act-future',
            ownerUid: 'uid-a',
            activityName: 'Chạy tương lai',
            durationSeconds: 900,
            estimatedDistanceMeters: 1000,
            feeling: '',
            routeSaved: false,
            startedAt: DateTime(2026, 11, 28, 8, 0),
            endedAt: DateTime(2026, 11, 28, 8, 15),
            route: const [],
          ),
        ],
        sleepLogs: [
          SleepLog(
            id: 'sleep-future',
            ownerUid: 'uid-a',
            sleptAt: DateTime(2026, 11, 27, 23, 0),
            wokeAt: DateTime(2026, 11, 28, 7, 0),
          ),
        ],
        referenceDate: DateTime(2026, 11, 27), // Thứ Sáu
      );

      final item = summary.habits.perHabit.single;
      // T2 & T3 trước ngày tạo -> notApplicable
      expect(item.days[0].resolution, HabitDayResolution.notApplicable);
      expect(item.days[1].resolution, HabitDayResolution.notApplicable);
      // T4 đến hạn quá khứ nhưng chưa ghi -> unlogged (explicitFailed == 0)
      expect(item.days[2].resolution, HabitDayResolution.unlogged);
      // T5 tạm dừng -> restOrPaused
      expect(item.days[3].resolution, HabitDayResolution.restOrPaused);
      // T6 hôm nay chưa ghi -> pendingToday
      expect(item.days[4].resolution, HabitDayResolution.pendingToday);
      // T7 & CN tương lai -> upcoming (log tương lai không được tính!)
      expect(item.days[5].resolution, HabitDayResolution.upcoming);
      expect(item.days[6].resolution, HabitDayResolution.upcoming);

      expect(item.dueSlotsElapsed, 1);
      expect(item.unloggedPastDueCount, 1);
      expect(item.explicitFailedCount, 0);
      expect(item.pendingTodayCount, 1);
      expect(item.totalCompletedCount, 0);
      expect(summary.activity.sessionCount, 0);
      expect(summary.sleep.totalLogsCount, 0);
    });

    test('tuần trống trả trạng thái chưa ghi nhận thay vì ép 0% hay 0 giờ ngủ', () {
      final summary = aggregator.aggregate(
        ownerUid: 'uid-empty',
        habits: const [],
        habitLogs: const [],
        activitySessions: const [],
        sleepLogs: const [],
        referenceDate: DateTime(2026, 11, 25), // Thứ Tư (3 ngày đã qua)
      );

      expect(summary.hasAnyData, isFalse);
      expect(summary.elapsedDaysInWeek, 3);
      expect(summary.habits.completionRatePercent, isNull);
      expect(summary.habits.recordedCompletionRatePercent, isNull);
      expect(summary.habits.bestCurrentStreak, 0);
      expect(summary.activity.hasData, isFalse);
      expect(summary.activity.formattedTotalDuration, 'Chưa ghi nhận');
      expect(summary.activity.unloggedDaysCount, 3);
      expect(summary.sleep.hasData, isFalse);
      expect(summary.sleep.averageDuration, isNull);
      expect(summary.sleep.formattedAverageDuration, 'Chưa ghi nhận');
      expect(summary.sleep.unloggedDaysCount, 3);
    });

    test('hỗ trợ giấc ngủ ban ngày cho ca đêm, khử trùng lặp bản ghi và cô lập chặt theo ownerUid', () {
      final habitA = Habit(
        id: 'h-a',
        ownerUid: 'uid-a',
        name: 'Uống nước',
        createdAt: DateTime(2026, 11, 23),
      );
      final habitB = Habit(
        id: 'h-b',
        ownerUid: 'uid-b',
        name: 'Thói quen người khác',
        createdAt: DateTime(2026, 11, 23),
      );

      final summary = aggregator.aggregate(
        ownerUid: 'uid-a',
        habits: [habitA, habitB],
        habitLogs: [
          HabitLog(
            id: 'l-1',
            habitId: 'h-a',
            userId: 'uid-a',
            date: DateTime(2026, 11, 23),
            status: CheckInStatus.completed,
            loggedAt: DateTime(2026, 11, 23, 8, 0),
          ),
          // Bản ghi trùng cùng ngày địa phương -> chỉ đếm 1 lần
          HabitLog(
            id: 'l-1-dup',
            habitId: 'h-a',
            userId: 'uid-a',
            date: DateTime(2026, 11, 23),
            status: CheckInStatus.completed,
            loggedAt: DateTime(2026, 11, 23, 9, 0),
          ),
          // Log của tài khoản khác -> phải bị loại
          HabitLog(
            id: 'l-b',
            habitId: 'h-b',
            userId: 'uid-b',
            date: DateTime(2026, 11, 23),
            status: CheckInStatus.completed,
          ),
        ],
        activitySessions: [
          ActivitySession(
            id: 's-dup',
            ownerUid: 'uid-a',
            activityName: 'Đi bộ',
            durationSeconds: 1500,
            estimatedDistanceMeters: 0,
            feeling: 'Ổn',
            routeSaved: false,
            startedAt: DateTime(2026, 11, 23, 18, 0),
            endedAt: DateTime(2026, 11, 23, 18, 25),
            route: const [],
          ),
          // Trùng ID -> không cộng đúp thời lượng
          ActivitySession(
            id: 's-dup',
            ownerUid: 'uid-a',
            activityName: 'Đi bộ',
            durationSeconds: 1500,
            estimatedDistanceMeters: 0,
            feeling: 'Ổn',
            routeSaved: false,
            startedAt: DateTime(2026, 11, 23, 18, 0),
            endedAt: DateTime(2026, 11, 23, 18, 25),
            route: const [],
          ),
          // Phiên tập của uid-b -> không lọt vào uid-a
          ActivitySession(
            id: 's-other',
            ownerUid: 'uid-b',
            activityName: 'Đạp xe người khác',
            durationSeconds: 3600,
            estimatedDistanceMeters: 15000,
            feeling: '',
            routeSaved: true,
            startedAt: DateTime(2026, 11, 23, 7, 0),
            endedAt: DateTime(2026, 11, 23, 8, 0),
            route: const [],
          ),
        ],
        sleepLogs: [
          // Giấc ngủ ban ngày sau ca đêm: 07:30 -> 14:30 (7 giờ)
          SleepLog(
            id: 'sleep-shift',
            ownerUid: 'uid-a',
            sleptAt: DateTime(2026, 11, 23, 7, 30),
            wokeAt: DateTime(2026, 11, 23, 14, 30),
            alertness: AlertnessLevel.refreshed,
          ),
          // Trùng ID -> không cộng đúp
          SleepLog(
            id: 'sleep-shift',
            ownerUid: 'uid-a',
            sleptAt: DateTime(2026, 11, 23, 7, 30),
            wokeAt: DateTime(2026, 11, 23, 14, 30),
            alertness: AlertnessLevel.refreshed,
          ),
          // Giấc ngủ của uid-b -> không lọt vào uid-a
          SleepLog(
            id: 'sleep-b',
            ownerUid: 'uid-b',
            sleptAt: DateTime(2026, 11, 23, 22, 0),
            wokeAt: DateTime(2026, 11, 24, 6, 0),
          ),
        ],
        referenceDate: DateTime(2026, 11, 23),
      );

      expect(summary.habits.totalHabitsCount, 1);
      expect(summary.habits.completedOnDueCount, 1);
      expect(summary.habits.completionRatePercent, 100.0);
      expect(summary.activity.sessionCount, 1);
      expect(summary.activity.totalDurationSeconds, 1500);
      expect(summary.sleep.totalLogsCount, 1);
      expect(summary.sleep.daytimeSleepCount, 1);
      expect(summary.sleep.averageDuration, const Duration(hours: 7));

      expect(
        () => aggregator.aggregate(
          ownerUid: '   ',
          habits: const [],
          habitLogs: const [],
          activitySessions: const [],
          sleepLogs: const [],
        ),
        throwsArgumentError,
      );
    });

    test('CompositeWeeklyInsightsSource kết nối trực tiếp các repository #4, #5, #8, #11 và bảo toàn streak xuyên tuần', () async {
      const ownerUid = 'uid-integrated';
      final habitRepo = InMemoryHabitRepository();
      final sleepRepo = InMemorySleepRepository();
      final activityRepo = InMemoryActivityRepository();
      final mealRepo = InMemoryMealLogRepository();

      final habit = Habit(
        id: 'h-int-1',
        ownerUid: ownerUid,
        name: 'Thiền 10 phút',
        frequency: const HabitFrequency.daily(),
        createdAt: DateTime(2026, 11, 21),
      );
      await habitRepo.saveHabit(habit);
      for (final day in [
        DateTime(2026, 11, 21), // T7 tuần trước
        DateTime(2026, 11, 22), // CN tuần trước
        DateTime(2026, 11, 23), // T2 tuần này
        DateTime(2026, 11, 24), // T3 tuần này
      ]) {
        await habitRepo.recordCheckIn(
          HabitLog(
            id: 'log-${day.day}',
            habitId: habit.id,
            userId: ownerUid,
            date: day,
            status: CheckInStatus.completed,
          ),
        );
      }

      // Giấc ngủ bắt đầu tối Chủ Nhật 22/11 và thức sáng Thứ Hai 23/11 (nằm trong tuần mới)
      await sleepRepo.saveSleepLog(
        SleepLog(
          id: 'sl-sun-mon',
          ownerUid: ownerUid,
          sleptAt: DateTime(2026, 11, 22, 23, 0),
          wokeAt: DateTime(2026, 11, 23, 6, 45),
          alertness: AlertnessLevel.refreshed,
        ),
      );
      await sleepRepo.saveSleepWindow(
        ownerUid: ownerUid,
        window: const SleepWindow(startMinute: 23 * 60, endMinute: 6 * 60 + 30),
      );

      await activityRepo.saveSession(
        ActivitySession(
          id: 'act-int-1',
          ownerUid: ownerUid,
          activityName: 'Đạp xe sáng',
          durationSeconds: 2700, // 45 phút
          estimatedDistanceMeters: 9500,
          feeling: 'Khỏe',
          routeSaved: true,
          startedAt: DateTime(2026, 11, 24, 6, 0),
          endedAt: DateTime(2026, 11, 24, 6, 45),
          route: const [],
        ),
      );

      await mealRepo.saveMealLog(
        MealLog(
          id: 'meal-int-1',
          ownerUid: ownerUid,
          mealName: 'Cơm gạo lứt ức gà',
          consumedAt: DateTime(2026, 11, 24, 12, 0),
          createdAt: DateTime(2026, 11, 24, 12, 0),
          updatedAt: DateTime(2026, 11, 24, 12, 0),
        ),
      );

      final useCase = GetWeeklyInsightsUseCase(
        source: CompositeWeeklyInsightsSource(
          habitRepository: habitRepo,
          sleepRepository: sleepRepo,
          activityRepository: activityRepo,
          mealLogRepository: mealRepo,
        ),
      );

      final summary = await useCase(
        ownerUid: ownerUid,
        referenceDate: DateTime(2026, 11, 24), // Thứ Ba
      );

      // Streak bảo toàn xuyên từ 21/11 -> 24/11 = 4 ngày
      expect(summary.habits.bestCurrentStreak, 4);
      expect(summary.habits.completedOnDueCount, 2); // T2, T3 trong tuần này
      expect(summary.habits.completionRatePercent, 100.0);
      // Giấc ngủ tối CN -> sáng T2 được lấy đúng qua buffer -1 ngày
      expect(summary.sleep.totalLogsCount, 1);
      expect(summary.sleep.formattedAverageDuration, '7 giờ 45 phút');
      expect(summary.sleep.averageBedtimeDeviationMinutes, 0);
      expect(summary.sleep.regularityIndex, 100);
      // Thời lượng tập & bữa ăn
      expect(summary.activity.totalDurationSeconds, 2700);
      expect(summary.activity.formattedTotalDuration, '45 phút');
      expect(summary.meals.totalLogsCount, 1);
    });

    test('phiên GPS 0 m không lưu tuyến vẫn được tính là nguồn thiết bị GPS, không gộp vào nhập tay', () async {
      const ownerUid = 'uid-gps-zero';
      final activityRepo = InMemoryActivityRepository();
      final controller = ActivityController(
        repository: activityRepo,
        ownerUid: ownerUid,
      );
      addTearDown(controller.dispose);

      // 1. Lưu phiên GPS 0 m, không bật lưu tuyến đường (routeSaved == false, route == [])
      final gpsStart = DateTime(2026, 11, 24, 7, 0);
      final gpsEnd = gpsStart.add(const Duration(minutes: 15));
      controller.startGps(gpsStart);
      controller.stopGps(gpsEnd);
      await controller.saveGpsSession(gpsEnd);

      final gpsOnlySummary = aggregator.aggregate(
        ownerUid: ownerUid,
        habits: const [],
        habitLogs: const [],
        activitySessions: await activityRepo.getSessions(ownerUid: ownerUid),
        sleepLogs: const [],
        referenceDate: DateTime(2026, 11, 24),
      );

      expect(gpsOnlySummary.activity.sessionCount, 1);
      expect(gpsOnlySummary.activity.gpsSessionCount, 1);
      expect(gpsOnlySummary.activity.manualSessionCount, 0);
      expect(gpsOnlySummary.activity.totalEstimatedDistanceMeters, 0);
      expect(
        gpsOnlySummary.activity.dataSources,
        equals({InsightDataSource.deviceGps}),
      );
      expect(
        InsightsDisplayFormatter.formatEstimatedDistance(
          gpsOnlySummary.activity.totalEstimatedDistanceMeters,
          hasGpsSession: gpsOnlySummary.activity.gpsSessionCount > 0,
        ),
        '0 m (ước tính GPS)',
      );

      // 2. Lưu thêm 1 phiên nhập tay -> tách rõ 1 GPS + 1 nhập tay
      await controller.saveManualSession(
        durationMinutes: 20,
        date: DateTime(2026, 11, 24, 18, 0),
      );

      final combinedSummary = aggregator.aggregate(
        ownerUid: ownerUid,
        habits: const [],
        habitLogs: const [],
        activitySessions: await activityRepo.getSessions(ownerUid: ownerUid),
        sleepLogs: const [],
        referenceDate: DateTime(2026, 11, 24),
      );

      expect(combinedSummary.activity.sessionCount, 2);
      expect(combinedSummary.activity.gpsSessionCount, 1);
      expect(combinedSummary.activity.manualSessionCount, 1);
      expect(
        combinedSummary.activity.dataSources,
        equals({InsightDataSource.deviceGps, InsightDataSource.manualInput}),
      );
      expect(
        InsightsDisplayFormatter.formatEstimatedDistance(
          0,
          hasGpsSession: false,
        ),
        'Không có quãng đường GPS',
      );
    });

    test('SupabaseActivityRepository phân biệt bản ghi nhập tay cũ (chưa rõ nguồn) song song với phiên GPS 0 m và nhập tay mới qua HTTP', () async {
      const ownerUid = 'uid-supabase-gps-zero';
      final legacyManualRow = <String, dynamic>{
        'id': 'legacy-manual-001',
        'owner_uid': ownerUid,
        'activity_name': 'Đi bộ nhập tay phiên bản cũ',
        'started_at': DateTime.utc(2026, 11, 25, 1, 0).toIso8601String(),
        'ended_at': DateTime.utc(2026, 11, 25, 1, 20).toIso8601String(),
        'duration_seconds': 1200,
        'estimated_distance_meters': 0,
        'feeling': 'Ổn',
        'route_saved': false,
        // Không có khóa `input_source` như bản ghi cũ trước migration.
      };
      final storedRows = <Map<String, dynamic>>[legacyManualRow];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        final path = request.uri.path;
        if (request.method == 'POST' &&
            path.endsWith('/rest/v1/activity_sessions')) {
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            storedRows.removeWhere((row) => row['id'] == decoded['id']);
            storedRows.add(decoded);
          }
          request.response
            ..statusCode = HttpStatus.created
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(decoded));
          await request.response.close();
          return;
        }
        if (request.method == 'GET' &&
            path.endsWith('/rest/v1/activity_sessions')) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(storedRows));
          await request.response.close();
          return;
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('[]');
        await request.response.close();
      });

      final client = SupabaseClient(
        'http://${server.address.address}:${server.port}',
        'test-anon-key',
      );
      addTearDown(() => client.dispose());

      final repo = SupabaseActivityRepository(client: client);

      // 1. Đọc riêng bản ghi nhập tay cũ (estimated_distance_meters: 0, route_saved: false, không có input_source):
      //    tuyệt đối KHÔNG được đếm thành GPS (gpsSessionCount == 0), xếp vào nguồn chưa xác định.
      final legacyOnly = await repo.getSessions(ownerUid: ownerUid);
      expect(legacyOnly, hasLength(1));
      expect(legacyOnly.single.resolvedSource, ActivityInputSource.unknown);

      final legacySummary = aggregator.aggregate(
        ownerUid: ownerUid,
        habits: const [],
        habitLogs: const [],
        activitySessions: legacyOnly,
        sleepLogs: const [],
        referenceDate: DateTime(2026, 11, 25),
      );
      expect(legacySummary.activity.sessionCount, 1);
      expect(legacySummary.activity.gpsSessionCount, 0);
      expect(legacySummary.activity.manualSessionCount, 0);
      expect(legacySummary.activity.unknownSourceSessionCount, 1);
      expect(
        legacySummary.activity.dataSources,
        equals({InsightDataSource.unknownSource}),
      );
      expect(
        InsightsDisplayFormatter.formatActivitySources(legacySummary.activity),
        'Nguồn: Nguồn chưa xác định (bản ghi cũ): 1 buổi',
      );
      expect(
        InsightsDisplayFormatter.formatEstimatedDistance(
          legacySummary.activity.totalEstimatedDistanceMeters,
          hasGpsSession: legacySummary.activity.gpsSessionCount > 0,
        ),
        'Không có quãng đường GPS',
      );

      // 2. Ghi thêm 1 phiên GPS 0 m mới và 1 phiên nhập tay mới (có input_source tường minh)
      final controller = ActivityController(
        repository: repo,
        ownerUid: ownerUid,
      );
      addTearDown(controller.dispose);

      final gpsStart = DateTime(2026, 11, 25, 6, 30);
      final gpsEnd = gpsStart.add(const Duration(minutes: 10));
      controller.startGps(gpsStart);
      controller.stopGps(gpsEnd);
      await controller.saveGpsSession(gpsEnd);
      await controller.saveManualSession(
        durationMinutes: 15,
        date: DateTime(2026, 11, 25, 19, 0),
      );

      // Xác nhận payload mới gửi input_source tường minh ('gps' vs 'manual')
      expect(storedRows, hasLength(3));
      expect(storedRows[1]['input_source'], 'gps');
      expect(storedRows[1]['estimated_distance_meters'], 0);
      expect(storedRows[2]['input_source'], 'manual');
      expect(storedRows[2]['estimated_distance_meters'], 0);

      // 3. Đọc đồng thời cả 3 bản ghi (cũ + GPS 0 m mới + nhập tay mới) và tổng hợp tuần
      final reloaded = await repo.getSessions(ownerUid: ownerUid);
      final summary = aggregator.aggregate(
        ownerUid: ownerUid,
        habits: const [],
        habitLogs: const [],
        activitySessions: reloaded,
        sleepLogs: const [],
        referenceDate: DateTime(2026, 11, 25),
      );

      expect(summary.activity.sessionCount, 3);
      expect(summary.activity.gpsSessionCount, 1);
      expect(summary.activity.manualSessionCount, 1);
      expect(summary.activity.unknownSourceSessionCount, 1);
      expect(
        summary.activity.dataSources,
        equals({
          InsightDataSource.deviceGps,
          InsightDataSource.manualInput,
          InsightDataSource.unknownSource,
        }),
      );
    });

    test('SupabaseActivityRepository fallback an toàn khi cloud chưa áp dụng migration input_source (PGRST204)', () async {
      final receivedPayloads = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        final path = request.uri.path;
        if (request.method == 'POST' &&
            path.endsWith('/rest/v1/activity_sessions')) {
          final body = await utf8.decoder.bind(request).join();
          final decoded = Map<String, dynamic>.from(jsonDecode(body) as Map);
          receivedPayloads.add(decoded);
          if (decoded.containsKey('input_source')) {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'code': 'PGRST204',
                  'message':
                      "Could not find the 'input_source' column of 'activity_sessions' in the schema cache",
                }),
              );
            await request.response.close();
            return;
          }
          request.response
            ..statusCode = HttpStatus.created
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(decoded));
          await request.response.close();
          return;
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('[]');
        await request.response.close();
      });

      final client = SupabaseClient(
        'http://${server.address.address}:${server.port}',
        'test-anon-key',
      );
      addTearDown(() => client.dispose());

      final repo = SupabaseActivityRepository(client: client);
      final session = ActivitySession(
        id: 'fallback-gps-0m',
        ownerUid: 'uid-pre-migration',
        activityName: 'Đi bộ',
        durationSeconds: 600,
        estimatedDistanceMeters: 0,
        feeling: '',
        routeSaved: false,
        startedAt: DateTime.utc(2026, 11, 25, 6, 0),
        endedAt: DateTime.utc(2026, 11, 25, 6, 10),
        route: const [],
        inputSource: ActivityInputSource.gps,
      );

      await repo.saveSession(session);
      expect(receivedPayloads, hasLength(2));
      expect(receivedPayloads[0]['input_source'], 'gps');
      expect(receivedPayloads[1].containsKey('input_source'), isFalse);
    });
  });
}
