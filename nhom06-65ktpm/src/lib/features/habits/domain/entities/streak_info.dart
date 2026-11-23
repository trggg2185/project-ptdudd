/// Thông tin chuỗi kỷ luật (Streak) và thống kê của một thói quen.
class StreakInfo {
  /// Chuỗi ngày hoàn thành liên tục hiện tại.
  final int currentStreak;

  /// Kỷ lục chuỗi hoàn thành liên tục dài nhất trong lịch sử.
  final int longestStreak;

  /// Tổng số lần bấm hoàn thành.
  final int totalCompletions;

  /// Tổng số lần bỏ qua có lý do.
  final int totalSkipped;

  /// Tổng số ngày đến hạn đã trôi qua tính từ ngày bắt đầu.
  final int totalDueDays;

  /// Ngày hoàn thành gần nhất (chuẩn hóa đầu ngày).
  final DateTime? lastCompletedDate;

  const StreakInfo({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalCompletions = 0,
    this.totalSkipped = 0,
    this.totalDueDays = 0,
    this.lastCompletedDate,
  });

  /// Tỷ lệ hoàn thành theo phần trăm (0.0 đến 100.0).
  double get completionPercentage {
    if (totalDueDays == 0) return 0.0;
    final rate = (totalCompletions / totalDueDays) * 100.0;
    return rate > 100.0 ? 100.0 : double.parse(rate.toStringAsFixed(1));
  }

  StreakInfo copyWith({
    int? currentStreak,
    int? longestStreak,
    int? totalCompletions,
    int? totalSkipped,
    int? totalDueDays,
    DateTime? lastCompletedDate,
  }) {
    return StreakInfo(
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      totalCompletions: totalCompletions ?? this.totalCompletions,
      totalSkipped: totalSkipped ?? this.totalSkipped,
      totalDueDays: totalDueDays ?? this.totalDueDays,
      lastCompletedDate: lastCompletedDate ?? this.lastCompletedDate,
    );
  }
}
