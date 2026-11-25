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

  /// Ngày trong tương lai (chưa tới hạn thực hiện).
  future,

  /// Đã hoàn thành.
  completed,

  /// Đã chọn bỏ qua có lý do.
  skipped,

  /// Đã quá hạn mà không thực hiện (ngày trong quá khứ không có log).
  missed,

  /// Ngày nghỉ theo lịch (không phải ngày đến hạn) hoặc đang trong giai đoạn tạm dừng.
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'habitId': habitId,
      'userId': userId,
      'date': DateHelper.formatIsoDate(date),
      'status': status.name,
      'reason': reason,
      'loggedAt': loggedAt.toIso8601String(),
    };
  }

  factory HabitLog.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'completed';
    final status = CheckInStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => CheckInStatus.completed,
    );
    return HabitLog(
      id: json['id'] as String,
      habitId: json['habitId'] as String,
      userId: json['userId'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      status: status,
      reason: json['reason'] as String?,
      loggedAt: json['loggedAt'] != null ? DateTime.parse(json['loggedAt'] as String) : null,
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'owner_uid': userId,
      'habit_id': habitId,
      'local_date': DateHelper.formatIsoDate(date),
      'result': status == CheckInStatus.completed ? 'completed' : 'skipped',
      'skipped_reason': reason,
      'logged_at': loggedAt.toUtc().toIso8601String(),
    };
  }

  factory HabitLog.fromSupabaseMap(Map<String, dynamic> map) {
    final resultStr = map['result'] as String? ?? 'completed';
    return HabitLog(
      id: map['id'] as String,
      habitId: map['habit_id'] as String,
      userId: map['owner_uid'] as String? ?? '',
      date: DateTime.parse(map['local_date'] as String),
      status: resultStr == 'skipped' ? CheckInStatus.skipped : CheckInStatus.completed,
      reason: map['skipped_reason'] as String?,
      loggedAt: map['logged_at'] != null ? DateTime.parse(map['logged_at'] as String) : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HabitLog &&
        other.id == id &&
        other.habitId == habitId &&
        other.userId == userId &&
        DateHelper.isSameDay(other.date, date) &&
        other.status == status &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(id, habitId, userId, date.year, date.month, date.day, status, reason);
}
