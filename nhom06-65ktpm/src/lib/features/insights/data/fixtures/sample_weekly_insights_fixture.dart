import '../../../activity/domain/entities/activity_session.dart';
import '../../../habits/domain/entities/habit.dart';
import '../../../habits/domain/entities/habit_frequency.dart';
import '../../../habits/domain/entities/habit_log.dart';
import '../../../nutrition/domain/entities/meal_log.dart';
import '../../../nutrition/domain/entities/meal_photo_attachment.dart';
import '../../../sleep/domain/entities/sleep_log.dart';
import '../../../sleep/domain/entities/sleep_window.dart';
import '../../domain/repositories/weekly_insights_source.dart';

/// Bộ dữ liệu mẫu (mock/fixture) chuẩn hóa phục vụ phát triển và kiểm thử độc lập
/// cho Dashboard & tổng kết tuần (Issue #12).
class SampleWeeklyInsightsFixture {
  /// Tuần mẫu hoàn chỉnh của tài khoản `uid-demo` (Thứ Hai 23/11/2026 – Chủ Nhật 29/11/2026,
  /// ngày mốc Thứ Sáu 27/11/2026): có chuỗi streak xuyên từ tuần trước, ngày bỏ qua có lý do,
  /// buổi tập kết hợp nhập tay & GPS, giấc ngủ qua nửa đêm và nhật ký bữa ăn.
  static WeeklyInsightsRawData balancedWeek({String ownerUid = 'uid-demo'}) {
    final monday = DateTime(2026, 11, 23);
    final waterHabit = Habit(
      id: 'habit-water',
      ownerUid: ownerUid,
      name: 'Uống 2 lít nước',
      frequency: const HabitFrequency.daily(),
      createdAt: DateTime(2026, 11, 18),
    );
    final workoutHabit = Habit(
      id: 'habit-workout',
      ownerUid: ownerUid,
      name: 'Vận động 30 phút',
      frequency: HabitFrequency.custom(const {1, 3, 5}), // T2, T4, T6
      createdAt: DateTime(2026, 11, 18),
    );

    final habitLogs = <HabitLog>[
      // Streak xuyên tuần trước (T6 20/11, T7 21/11, CN 22/11)
      HabitLog(
        id: 'hl-prev-1',
        habitId: waterHabit.id,
        userId: ownerUid,
        date: DateTime(2026, 11, 20),
        status: CheckInStatus.completed,
      ),
      HabitLog(
        id: 'hl-prev-2',
        habitId: waterHabit.id,
        userId: ownerUid,
        date: DateTime(2026, 11, 21),
        status: CheckInStatus.completed,
      ),
      HabitLog(
        id: 'hl-prev-3',
        habitId: waterHabit.id,
        userId: ownerUid,
        date: DateTime(2026, 11, 22),
        status: CheckInStatus.completed,
      ),
      // Trong tuần hiện tại (T2–T5 đã ghi nhận, T6 chưa bấm -> pendingToday)
      HabitLog(
        id: 'hl-mon',
        habitId: waterHabit.id,
        userId: ownerUid,
        date: monday,
        status: CheckInStatus.completed,
      ),
      HabitLog(
        id: 'hl-tue',
        habitId: waterHabit.id,
        userId: ownerUid,
        date: DateTime(2026, 11, 24),
        status: CheckInStatus.completed,
      ),
      HabitLog(
        id: 'hl-wed',
        habitId: waterHabit.id,
        userId: ownerUid,
        date: DateTime(2026, 11, 25),
        status: CheckInStatus.skipped,
        reason: 'Đi công tác đột xuất',
      ),
      HabitLog(
        id: 'hl-thu',
        habitId: waterHabit.id,
        userId: ownerUid,
        date: DateTime(2026, 11, 26),
        status: CheckInStatus.completed,
      ),
      // Thói quen vận động T2, T4, T6: T2 hoàn thành, T4 không hoàn thành (explicit failed)
      HabitLog(
        id: 'hl-w-mon',
        habitId: workoutHabit.id,
        userId: ownerUid,
        date: monday,
        status: CheckInStatus.completed,
      ),
      HabitLog(
        id: 'hl-w-wed',
        habitId: workoutHabit.id,
        userId: ownerUid,
        date: DateTime(2026, 11, 25),
        status: CheckInStatus.failed,
      ),
    ];

    final activitySessions = <ActivitySession>[
      // Buổi chạy GPS
      ActivitySession(
        id: 'act-gps-1',
        ownerUid: ownerUid,
        activityName: 'Chạy bộ công viên',
        durationSeconds: 1800, // 30 phút
        estimatedDistanceMeters: 3800,
        feeling: 'Thoải mái',
        routeSaved: true,
        startedAt: DateTime(2026, 11, 23, 6, 30),
        endedAt: DateTime(2026, 11, 23, 7, 0),
        route: [
          GpsPoint(
            latitude: 21.0285,
            longitude: 105.8542,
            accuracyMeters: 8,
            recordedAt: DateTime(2026, 11, 23, 6, 30),
          ),
        ],
        inputSource: ActivityInputSource.gps,
      ),
      // Buổi tập nhập tay (không GPS)
      ActivitySession(
        id: 'act-manual-1',
        ownerUid: ownerUid,
        activityName: 'Giãn cơ tại nhà',
        durationSeconds: 1200, // 20 phút
        estimatedDistanceMeters: 0,
        feeling: 'Nhẹ nhàng',
        routeSaved: false,
        startedAt: DateTime(2026, 11, 26, 19, 0),
        endedAt: DateTime(2026, 11, 26, 19, 20),
        route: const [],
        inputSource: ActivityInputSource.manual,
      ),
    ];

    final sleepLogs = <SleepLog>[
      // Ngủ từ 23:00 CN 22/11 -> 06:30 T2 23/11 (7h30, wakeDate = T2 23/11)
      SleepLog(
        id: 'sleep-mon',
        ownerUid: ownerUid,
        sleptAt: DateTime(2026, 11, 22, 23, 0),
        wokeAt: DateTime(2026, 11, 23, 6, 30),
        alertness: AlertnessLevel.refreshed,
      ),
      // Ngủ từ 23:30 T2 23/11 -> 06:30 T3 24/11 (7h00, wakeDate = T3 24/11)
      SleepLog(
        id: 'sleep-tue',
        ownerUid: ownerUid,
        sleptAt: DateTime(2026, 11, 23, 23, 30),
        wokeAt: DateTime(2026, 11, 24, 6, 30),
        alertness: AlertnessLevel.neutral,
      ),
      // T4 chưa ghi nhận (không được tính là 0 giờ ngủ)
      // Ngủ từ 23:15 T4 25/11 -> 07:15 T5 26/11 (8h00, wakeDate = T5 26/11)
      SleepLog(
        id: 'sleep-thu',
        ownerUid: ownerUid,
        sleptAt: DateTime(2026, 11, 25, 23, 15),
        wokeAt: DateTime(2026, 11, 26, 7, 15),
        alertness: AlertnessLevel.energized,
      ),
    ];

    final mealLogs = <MealLog>[
      MealLog(
        id: 'meal-1',
        ownerUid: ownerUid,
        mealName: 'Ức gà áp chảo khoai lang',
        consumedAt: DateTime(2026, 11, 23, 12, 15),
        imagePath: '$ownerUid/meal-1.jpg',
        photoSource: MealPhotoSource.camera,
        photoUploadStatus: MealPhotoUploadStatus.uploaded,
        createdAt: DateTime(2026, 11, 23, 12, 15),
        updatedAt: DateTime(2026, 11, 23, 12, 15),
      ),
      MealLog(
        id: 'meal-2',
        ownerUid: ownerUid,
        mealName: 'Phở gà nạc nhập tay',
        consumedAt: DateTime(2026, 11, 25, 7, 30),
        createdAt: DateTime(2026, 11, 25, 7, 30),
        updatedAt: DateTime(2026, 11, 25, 7, 30),
      ),
    ];

    return WeeklyInsightsRawData(
      habits: [waterHabit, workoutHabit],
      habitLogs: habitLogs,
      activitySessions: activitySessions,
      sleepLogs: sleepLogs,
      sleepWindow: const SleepWindow(startMinute: 23 * 60, endMinute: 6 * 60 + 30),
      mealLogs: mealLogs,
    );
  }
}

/// Nguồn dữ liệu giả (fixture) phục vụ phát triển và kiểm thử độc lập không cần cloud.
class FixtureWeeklyInsightsSource implements WeeklyInsightsSource {
  final WeeklyInsightsRawData Function(String ownerUid) builder;

  FixtureWeeklyInsightsSource({
    WeeklyInsightsRawData Function(String ownerUid)? builder,
  }) : builder = builder ?? ((uid) => SampleWeeklyInsightsFixture.balancedWeek(ownerUid: uid));

  @override
  Future<WeeklyInsightsRawData> loadWeeklyData({
    required String ownerUid,
    required DateTime weekStart,
    required DateTime weekEnd,
    required DateTime referenceDate,
  }) async {
    return builder(ownerUid);
  }
}
