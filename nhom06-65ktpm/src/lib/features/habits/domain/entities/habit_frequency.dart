import '../../../../core/utils/date_helper.dart';

/// Kiểu chu kỳ lặp của thói quen.
enum FrequencyType {
  /// Lặp mỗi ngày (T2 - CN).
  daily,

  /// Lặp theo các ngày cụ thể trong tuần.
  customDays,
}

/// Chu kỳ lặp của thói quen (ngày trong tuần từ 1 = T2 đến 7 = CN).
class HabitFrequency {
  final FrequencyType type;

  /// Tập các ngày trong tuần được lên lịch (1 = DateTime.monday, ..., 7 = DateTime.sunday).
  final Set<int> scheduledDays;

  const HabitFrequency({
    this.type = FrequencyType.daily,
    this.scheduledDays = const {1, 2, 3, 4, 5, 6, 7},
  });

  /// Tạo chu kỳ mỗi ngày.
  const HabitFrequency.daily()
      : type = FrequencyType.daily,
        scheduledDays = const {1, 2, 3, 4, 5, 6, 7};

  /// Tạo chu kỳ các ngày làm việc (T2 - T6).
  const HabitFrequency.weekdays()
      : type = FrequencyType.customDays,
        scheduledDays = const {1, 2, 3, 4, 5};

  /// Tạo chu kỳ cuối tuần (T7, CN).
  const HabitFrequency.weekends()
      : type = FrequencyType.customDays,
        scheduledDays = const {6, 7};

  /// Tạo chu kỳ theo các ngày tùy chọn.
  HabitFrequency.custom(Set<int> days)
      : type = days.length == 7 ? FrequencyType.daily : FrequencyType.customDays,
        scheduledDays = Set.unmodifiable(days);

  /// Kiểm tra ngày [date] có phải là ngày cần thực hiện thói quen không.
  bool isDueOn(DateTime date) {
    if (type == FrequencyType.daily) return true;
    return scheduledDays.contains(date.weekday);
  }

  /// Chuỗi mô tả dễ đọc cho người dùng.
  String get displayLabel {
    if (type == FrequencyType.daily || scheduledDays.length == 7) {
      return 'Hằng ngày';
    }
    if (scheduledDays.length == 5 &&
        scheduledDays.contains(1) &&
        scheduledDays.contains(2) &&
        scheduledDays.contains(3) &&
        scheduledDays.contains(4) &&
        scheduledDays.contains(5)) {
      return 'Ngày trong tuần (T2 - T6)';
    }
    if (scheduledDays.length == 2 &&
        scheduledDays.contains(6) &&
        scheduledDays.contains(7)) {
      return 'Cuối tuần (T7, CN)';
    }
    final sortedDays = scheduledDays.toList()..sort();
    return sortedDays.map((d) => DateHelper.weekdayToVietnamese(d, short: true)).join(', ');
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'scheduledDays': scheduledDays.toList(),
    };
  }

  factory HabitFrequency.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'daily';
    final type = FrequencyType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => FrequencyType.daily,
    );
    final rawDays = json['scheduledDays'] as List<dynamic>?;
    final scheduledDays = rawDays != null
        ? rawDays.map((e) => e as int).toSet()
        : const {1, 2, 3, 4, 5, 6, 7};
    return HabitFrequency(type: type, scheduledDays: scheduledDays);
  }
}
