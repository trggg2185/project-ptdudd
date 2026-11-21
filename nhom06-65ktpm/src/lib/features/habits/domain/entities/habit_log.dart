import '../../../../core/utils/date_helper.dart';

/// Trạng thái ghi nhận check-in thực tế của người dùng.
enum CheckInStatus {
  /// Đã hoàn thành thói quen.
  completed,

  /// Bỏ qua có lý do hợp lệ (ví dụ: ốm, bận đột xuất, thời tiết xấu).
  skipped,

  /// Không hoàn thành / thất bại.
  failed,
}

/// Trạng thái tổng hợp của một thói quen trong một ngày cụ thể (dành cho UI/UX).
enum HabitDayStatus {
  /// Ngày hôm nay/đến hạn nhưng người dùng chưa bấm ghi nhận.
  pending,

  /// Đã hoàn thành.
  completed,

  /// Đã chọn bỏ qua có lý do.
  skipped,

  /// Đã quá hạn mà không thực hiện (ngày trong quá khứ không có log).
  missed,

  /// Ngày nghỉ theo lịch (không phải ngày đến hạn).
  restDay,
}

/// Bản ghi nhật ký check-in của một thói quen cho một ngày địa phương duy nhất.
class HabitLog {
  /// Định danh duy nhất của bản ghi nhật ký.
  final String id;

  /// ID của thói quen tương ứng.
  final String habitId;

  /// UID người sở hữu (Firebase UID).
  final String userId;

  /// Ngày địa phương áp dụng (chuẩn hóa về 00:00:00).
  final DateTime date;

  /// Kết quả check-in.
  final CheckInStatus status;

  /// Lý do (nếu bỏ qua hoặc ghi chú bổ sung).
  final String? reason;

  /// Thời điểm thực tế người dùng bấm check-in.
  final DateTime loggedAt;

  HabitLog({
    required this.id,
    required this.habitId,
    required this.userId,
    required DateTime date,
    required this.status,
    this.reason,
    DateTime? loggedAt,
  })  : date = DateHelper.normalize(date),
        loggedAt = loggedAt ?? DateTime.now();

  HabitLog copyWith({
    String? id,
    String? habitId,
    String? userId,
    DateTime? date,
    CheckInStatus? status,
    String? reason,
    DateTime? loggedAt,
  }) {
    return HabitLog(
      id: id ?? this.id,
      habitId: habitId ?? this.habitId,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      loggedAt: loggedAt ?? this.loggedAt,
    );
  }
}
