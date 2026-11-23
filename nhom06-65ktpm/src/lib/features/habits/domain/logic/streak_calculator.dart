import 'dart:math';

import '../../../../core/utils/date_helper.dart';
import '../entities/habit.dart';
import '../entities/habit_log.dart';
import '../entities/streak_info.dart';

/// Bộ tính toán chuỗi kỷ luật (Streak) và trạng thái thói quen theo múi giờ địa phương.
///
/// Các quy tắc cốt lõi:
/// 1. Chỉ tính ngày đến hạn theo múi giờ địa phương (`HabitFrequency.isDueOn`).
/// 2. Ngày nghỉ (`restDay`) KHÔNG phá vỡ streak hiện tại.
/// 3. Bỏ qua có lý do hợp lệ (`skipped`) KHÔNG phá vỡ streak hiện tại.
/// 4. Ngày đến hạn trong quá khứ không có log hoặc bị đánh dấu `failed` sẽ phá vỡ streak hiện tại về 0.
/// 5. Ngày hôm nay (`referenceDate`) chưa check-in không phá vỡ streak hôm qua (vẫn đang trong ngày).
/// 6. Ngày trong tương lai KHÔNG được ghi nhận check-in hoặc tính vào streak.
/// 7. Mỗi ngày địa phương chỉ tính một kết quả duy nhất (loại bỏ trùng lặp).
/// 8. Sửa chu kỳ trong tương lai không làm thay đổi lịch sử các ngày đã ghi nhận
///    (sử dụng `habit.getFrequencyOn(date)` theo từng mốc áp dụng).
/// 9. Tạm dừng thói quen (`!habit.isActive` / `habit.pausedAt`) sẽ đóng băng chuỗi (freeze streak),
///    không phát sinh ngày đến hạn trong khoảng thời gian tạm dừng và không tính là vi phạm.
class StreakCalculator {
  /// Tính toán thông tin `StreakInfo` cho thói quen [habit] dựa trên danh sách nhật ký [logs].
  ///
  /// [referenceDate] là ngày mốc so sánh (mặc định là hôm nay, chuẩn hóa 00:00:00).
  static StreakInfo calculate(
    Habit habit,
    List<HabitLog> logs, {
    DateTime? referenceDate,
  }) {
    final ref = DateHelper.normalize(referenceDate ?? DateTime.now());

    // 1. Lọc và khử trùng lặp logs theo ngày địa phương (ưu tiên log mới nhất).
    final Map<String, HabitLog> uniqueLogsMap = {};
    for (final log in logs) {
      if (log.habitId != habit.id) continue;
      // Bỏ qua các log nếu có ai cố tình ghi vào ngày tương lai
      if (DateHelper.isFutureDay(log.date, ref)) continue;

      final key = DateHelper.formatIsoDate(log.date);
      final existing = uniqueLogsMap[key];
      if (existing == null || log.loggedAt.isAfter(existing.loggedAt)) {
        uniqueLogsMap[key] = log;
      }
    }

    // 2. Xác định ngày bắt đầu tính toán:
    DateTime startDate = DateHelper.normalize(habit.createdAt);
    for (final log in uniqueLogsMap.values) {
      if (log.date.isBefore(startDate)) {
        startDate = log.date;
      }
    }

    // Nếu ngày tạo ở tương lai so với ngày mốc, streak = 0.
    if (startDate.isAfter(ref)) {
      return const StreakInfo();
    }

    int currentStreak = 0;
    int longestStreak = 0;
    int totalCompletions = 0;
    int totalSkipped = 0;
    int totalDueDays = 0;
    DateTime? lastCompletedDate;

    // 3. Duyệt tuần tự từng ngày từ `startDate` đến `ref`.
    var cursor = startDate;
    while (!cursor.isAfter(ref)) {
      // Kiểm tra khoảng thời gian tạm dừng (dựa vào pauseHistory hoặc pausedAt):
      final isPaused = habit.isPausedOn(cursor);

      if (isPaused) {
        // Ngày trong khoảng tạm dừng: không sinh ngày đến hạn, đóng băng chuỗi (freeze streak)
        cursor = cursor.add(const Duration(days: 1));
        continue;
      }

      // Lấy chu kỳ có hiệu lực tại thời điểm cursor (đảm bảo không sửa lịch sử)
      final effectiveFreq = habit.getFrequencyOn(cursor);
      final isDue = effectiveFreq.isDueOn(cursor);
      final dateKey = DateHelper.formatIsoDate(cursor);
      final log = uniqueLogsMap[dateKey];
      final isToday = DateHelper.isSameDay(cursor, ref);

      if (isDue) {
        if (!isToday) {
          // Ngày trong quá khứ đã đến hạn
          totalDueDays++;

          if (log != null && log.status == CheckInStatus.completed) {
            totalCompletions++;
            currentStreak++;
            longestStreak = max(longestStreak, currentStreak);
            lastCompletedDate = cursor;
          } else if (log != null && log.status == CheckInStatus.skipped) {
            totalSkipped++;
            // Bỏ qua có lý do hợp lệ không phá vỡ streak hiện tại
          } else {
            // Không check-in hoặc thất bại: đứt chuỗi
            currentStreak = 0;
          }
        } else {
          // Ngày hôm nay (đang diễn ra)
          if (log != null && log.status == CheckInStatus.completed) {
            totalDueDays++;
            totalCompletions++;
            currentStreak++;
            longestStreak = max(longestStreak, currentStreak);
            lastCompletedDate = cursor;
          } else if (log != null && log.status == CheckInStatus.skipped) {
            totalDueDays++;
            totalSkipped++;
            // Bỏ qua hôm nay giữ nguyên chuỗi
          } else {
            // Hôm nay chưa bấm ghi nhận (pending):
            // Giữ nguyên chuỗi từ hôm qua, không tính ngày hôm nay vào phạt thiếu dữ liệu.
          }
        }
      } else {
        // Ngày nghỉ (restDay):
        // Nếu có log completed ngoài lịch (người dùng tự giác làm thêm), vẫn ghi nhận
        if (log != null && log.status == CheckInStatus.completed) {
          totalCompletions++;
          currentStreak++;
          longestStreak = max(longestStreak, currentStreak);
          lastCompletedDate = cursor;
        }
        // Không phá vỡ chuỗi hiện tại
      }

      cursor = cursor.add(const Duration(days: 1));
    }

    return StreakInfo(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalCompletions: totalCompletions,
      totalSkipped: totalSkipped,
      totalDueDays: totalDueDays,
      lastCompletedDate: lastCompletedDate,
    );
  }

  /// Xác định trạng thái của thói quen trong một ngày cụ thể [targetDate].
  static HabitDayStatus getDayStatus(
    Habit habit,
    List<HabitLog> logs,
    DateTime targetDate, {
    DateTime? referenceDate,
  }) {
    final normTarget = DateHelper.normalize(targetDate);
    final ref = DateHelper.normalize(referenceDate ?? DateTime.now());

    // 1. Kiểm tra ngày trong tương lai TRƯỚC HẾT (Fix [P2] Finding):
    // Tuyệt đối không để log tương lai (do dữ liệu bất thường hoặc lệch múi giờ) hiển thị là "completed".
    if (DateHelper.isFutureDay(normTarget, ref)) {
      if (habit.isPausedOn(normTarget)) {
        return HabitDayStatus.restDay;
      }
      final effectiveFreq = habit.getFrequencyOn(normTarget);
      final isDue = effectiveFreq.isDueOn(normTarget);
      if (!isDue) {
        return HabitDayStatus.restDay;
      }
      return HabitDayStatus.future;
    }

    // 2. Nếu thói quen đang trong giai đoạn tạm dừng tại thời điểm targetDate:
    if (habit.isPausedOn(normTarget)) {
      return HabitDayStatus.restDay;
    }

    // 3. Tìm log hợp lệ trong ngày đó (quá khứ hoặc hôm nay):
    HabitLog? dayLog;
    for (final log in logs) {
      if (log.habitId == habit.id && DateHelper.isSameDay(log.date, normTarget)) {
        if (dayLog == null || log.loggedAt.isAfter(dayLog.loggedAt)) {
          dayLog = log;
        }
      }
    }

    if (dayLog != null) {
      switch (dayLog.status) {
        case CheckInStatus.completed:
          return HabitDayStatus.completed;
        case CheckInStatus.skipped:
          return HabitDayStatus.skipped;
        case CheckInStatus.failed:
          return HabitDayStatus.missed;
      }
    }

    // 4. Kiểm tra chu kỳ có hiệu lực tại thời điểm targetDate (ngày nghỉ thì là restDay):
    final effectiveFreq = habit.getFrequencyOn(normTarget);
    final isDue = effectiveFreq.isDueOn(normTarget);
    if (!isDue) {
      return HabitDayStatus.restDay;
    }

    // 5. Ngày trong quá khứ đã đến hạn nhưng không có log check-in:
    if (normTarget.isBefore(ref)) {
      return HabitDayStatus.missed;
    }

    // 6. Hôm nay chưa check-in:
    return HabitDayStatus.pending;
  }

  /// Lấy trạng thái của toàn bộ 7 ngày trong tuần chứa [date].
  /// Trả về danh sách 7 phần tử từ Thứ Hai đến Chủ Nhật.
  static List<DayStatusItem> getWeekStatus(
    Habit habit,
    List<HabitLog> logs,
    DateTime date, {
    DateTime? referenceDate,
  }) {
    final norm = DateHelper.normalize(date);
    // Tính ngày Thứ Hai đầu tuần
    final monday = norm.subtract(Duration(days: norm.weekday - 1));

    return List.generate(7, (index) {
      final currentDay = monday.add(Duration(days: index));
      final status = getDayStatus(habit, logs, currentDay, referenceDate: referenceDate);
      return DayStatusItem(date: currentDay, status: status);
    });
  }
}

/// Dữ liệu biểu diễn một ngày trên thanh lịch tuần.
class DayStatusItem {
  final DateTime date;
  final HabitDayStatus status;

  const DayStatusItem({required this.date, required this.status});
}
