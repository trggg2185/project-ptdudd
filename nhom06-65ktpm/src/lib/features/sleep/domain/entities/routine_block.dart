/// Loại khối hoạt động hiển thị trên giao diện lịch sinh hoạt 24 giờ responsive.
enum RoutineBlockKind {
  /// Ca làm việc (bao gồm cả ca đêm qua nửa đêm, ví dụ 22:00–06:00).
  workShift('Ca làm việc'),

  /// Khoảng bận cố định (lịch học, họp, di chuyển).
  busy('Khoảng bận'),

  /// Khoảng ngủ mong muốn theo mục tiêu người dùng đặt.
  sleepTarget('Khoảng ngủ mong muốn'),

  /// Giấc ngủ thực tế đã ghi nhận trong nhật ký.
  sleepLogged('Giấc ngủ đã ghi nhận');

  const RoutineBlockKind(this.label);

  final String label;
}

/// Khối lịch sinh hoạt (ca làm, khoảng bận...) dùng để hiển thị trên lịch ngày/tuần.
class RoutineBlock {
  final String id;
  final String title;
  final RoutineBlockKind kind;
  final DateTime startsAt;
  final DateTime endsAt;
  final int travelMinutes;

  const RoutineBlock({
    required this.id,
    required this.title,
    required this.kind,
    required this.startsAt,
    required this.endsAt,
    this.travelMinutes = 0,
  });

  Duration get duration => endsAt.difference(startsAt);
}

/// Một đoạn thời gian đã được cắt gọn vào đúng một ngày lịch địa phương [00:00..24:00].
///
/// Dùng để hiển thị các khoảng qua ngày (ca đêm 22:00–06:00, ngủ 23:30–07:00)
/// một cách mạch lạc và không bao giờ mất đoạn hay tính sai giờ trên UI.
class DailyTimelineSegment {
  final String sourceId;
  final String title;
  final RoutineBlockKind kind;

  /// Ngày lịch địa phương (00:00:00) chứa đoạn này.
  final DateTime date;

  /// Phút bắt đầu trong ngày (0..1439).
  final int startMinute;

  /// Phút kết thúc trong ngày (1..1440; 1440 = 24:00).
  final int endMinute;

  /// Đoạn này tiếp nối từ ngày hôm trước (bắt đầu từ 00:00).
  final bool continuedFromPreviousDay;

  /// Đoạn này kéo dài sang ngày hôm sau (kết thúc lúc 24:00).
  final bool continuesToNextDay;

  /// Ghi chú phụ (ví dụ: mức tỉnh táo hoặc thời gian di chuyển).
  final String? subtitle;

  const DailyTimelineSegment({
    required this.sourceId,
    required this.title,
    required this.kind,
    required this.date,
    required this.startMinute,
    required this.endMinute,
    this.continuedFromPreviousDay = false,
    this.continuesToNextDay = false,
    this.subtitle,
  });

  int get durationMinutes => endMinute - startMinute;

  String get formattedRange {
    final startStr = _formatMinuteOfDay(startMinute);
    final endStr = _formatMinuteOfDay(endMinute);
    final prefix = continuedFromPreviousDay ? '← ' : '';
    final suffix = continuesToNextDay ? ' →' : '';
    return '$prefix$startStr – $endStr$suffix';
  }

  static String _formatMinuteOfDay(int minute) {
    if (minute >= 1440) return '24:00';
    final h = (minute ~/ 60).toString().padLeft(2, '0');
    final m = (minute % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
