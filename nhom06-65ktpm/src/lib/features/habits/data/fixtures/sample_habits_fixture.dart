import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_frequency.dart';
import '../../domain/entities/habit_log.dart';

/// Dữ liệu mẫu phục vụ kiểm thử độc lập và trình diễn giao diện theo yêu cầu đề cương.
class SampleHabitsFixture {
  static const String demoOwnerUid = 'demo-user-duc-2351170585';

  /// Danh sách thói quen mẫu với các chu kỳ khác nhau.
  static List<Habit> getSampleHabits({DateTime? baseDate}) {
    final now = DateHelper.normalize(baseDate ?? DateTime.now());

    return [
      Habit(
        id: 'habit-water-001',
        ownerUid: demoOwnerUid,
        name: 'Uống đủ 2 lít nước',
        description: 'Duy trì bù nước đều đặn trong ngày để tăng cường trao đổi chất.',
        frequency: const HabitFrequency.daily(),
        reminderTime: '08:00',
        isActive: true,
        createdAt: now.subtract(const Duration(days: 14)),
      ),
      Habit(
        id: 'habit-run-002',
        ownerUid: demoOwnerUid,
        name: 'Chạy bộ 30 phút buổi sáng',
        description: 'Chạy nhẹ nhàng tại công viên hoặc máy chạy bộ.',
        frequency: const HabitFrequency.weekdays(),
        reminderTime: '06:15',
        isActive: true,
        createdAt: now.subtract(const Duration(days: 10)),
      ),
      Habit(
        id: 'habit-read-003',
        ownerUid: demoOwnerUid,
        name: 'Đọc sách 20 phút',
        description: 'Đọc sách chuyên ngành hoặc kỹ năng sống trước khi ngủ.',
        frequency: HabitFrequency.custom(const {1, 3, 5, 7}), // T2, T4, T6, CN
        reminderTime: '21:30',
        isActive: true,
        createdAt: now.subtract(const Duration(days: 21)),
      ),
      Habit(
        id: 'habit-sleep-004',
        ownerUid: demoOwnerUid,
        name: 'Ngủ trước 23:00',
        description: 'Tạm dừng theo dõi trong tuần thi cuối kỳ.',
        frequency: const HabitFrequency.daily(),
        reminderTime: '22:45',
        isActive: false,
        createdAt: now.subtract(const Duration(days: 30)),
      ),
    ];
  }

  /// Danh sách lịch sử check-in mẫu minh họa các kịch bản streak, ngày nghỉ và bỏ qua.
  static List<HabitLog> getSampleLogs({DateTime? baseDate}) {
    final today = DateHelper.normalize(baseDate ?? DateTime.now());
    final logs = <HabitLog>[];

    // 1. Thói quen uống nước (habit-water-001): hoàn thành liên tiếp 7 ngày
    for (int i = 7; i >= 1; i--) {
      final logDate = today.subtract(Duration(days: i));
      logs.add(
        HabitLog(
          id: 'log-water-$i',
          habitId: 'habit-water-001',
          userId: demoOwnerUid,
          date: logDate,
          status: CheckInStatus.completed,
          loggedAt: logDate.add(const Duration(hours: 19)),
        ),
      );
    }

    // 2. Thói quen đọc sách (habit-read-003): có ngày hoàn thành và 1 ngày bỏ qua có lý do
    final threeDaysAgo = today.subtract(const Duration(days: 3));
    final fiveDaysAgo = today.subtract(const Duration(days: 5));
    final sevenDaysAgo = today.subtract(const Duration(days: 7));

    logs.add(
      HabitLog(
        id: 'log-read-1',
        habitId: 'habit-read-003',
        userId: demoOwnerUid,
        date: sevenDaysAgo,
        status: CheckInStatus.completed,
      ),
    );
    logs.add(
      HabitLog(
        id: 'log-read-2',
        habitId: 'habit-read-003',
        userId: demoOwnerUid,
        date: fiveDaysAgo,
        status: CheckInStatus.skipped,
        reason: 'Bận ôn tập thi cuối kỳ',
      ),
    );
    logs.add(
      HabitLog(
        id: 'log-read-3',
        habitId: 'habit-read-003',
        userId: demoOwnerUid,
        date: threeDaysAgo,
        status: CheckInStatus.completed,
      ),
    );

    return logs;
  }
}
