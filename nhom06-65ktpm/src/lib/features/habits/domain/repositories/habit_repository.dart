import '../entities/habit.dart';
import '../entities/habit_log.dart';
import '../entities/streak_info.dart';

/// Hợp đồng Repository quản lý thói quen và nhật ký check-in.
abstract class HabitRepository {
  /// Lấy danh sách thói quen của người dùng.
  ///
  /// Nếu [activeOnly] = true, chỉ trả về các thói quen đang kích hoạt.
  Future<List<Habit>> getHabits({String? ownerUid, bool? activeOnly});

  /// Tìm thói quen theo [id].
  Future<Habit?> getHabitById(String id);

  /// Thêm mới hoặc cập nhật thông tin thói quen.
  Future<void> saveHabit(Habit habit);

  /// Xóa thói quen theo [id].
  Future<void> deleteHabit(String id);

  /// Bật/tắt trạng thái kích hoạt (tạm dừng hoặc tiếp tục theo dõi).
  Future<void> toggleHabitActive(String id, bool isActive);

  /// Lấy danh sách nhật ký check-in của một thói quen.
  Future<List<HabitLog>> getHabitLogs(
    String habitId, {
    DateTime? fromDate,
    DateTime? toDate,
  });

  /// Lấy toàn bộ nhật ký check-in của người dùng trong một ngày cụ thể [date].
  Future<List<HabitLog>> getAllLogsForDate(String ownerUid, DateTime date);

  /// Lấy nhật ký check-in của thói quen trong ngày [date] (nếu có).
  Future<HabitLog?> getLogForHabitAndDate(String habitId, DateTime date);

  /// Ghi nhận check-in (hoàn thành hoặc bỏ qua có lý do).
  ///
  /// Đảm bảo mỗi thói quen chỉ có một kết quả duy nhất cho mỗi ngày địa phương.
  Future<void> recordCheckIn(HabitLog log);

  /// Xóa bản ghi check-in (hủy check-in trong ngày).
  Future<void> deleteHabitLog(String logId);

  /// Tính toán thông tin chuỗi kỷ luật (Streak) của thói quen.
  Future<StreakInfo> getStreakInfo(Habit habit, {DateTime? referenceDate});
}
