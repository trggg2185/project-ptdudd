/// Khoảng ngủ mong muốn do người dùng tự thiết lập (tính bằng phút từ 00:00, 0..1439).
///
/// Thiết kế tương thích hoàn toàn với `sleep_start` và `sleep_end` trong
/// `profiles.living_conditions['healthylife_profile']` của module Profile (Issue #2).
/// Không áp đặt mốc 22:00 cố định; hỗ trợ cả ngủ qua nửa đêm lẫn ngủ ban ngày (ca đêm).
class SleepWindow {
  /// Thời điểm bắt đầu ngủ mong muốn (phút từ 00:00, trong khoảng 0..1439).
  final int startMinute;

  /// Thời điểm thức dậy mong muốn (phút từ 00:00, trong khoảng 0..1439).
  final int endMinute;

  /// Nhãn tùy chọn mô tả lịch ngủ (ví dụ: "Ca đêm - ngủ ban ngày", "Lịch học linh hoạt").
  final String? label;

  const SleepWindow({
    required this.startMinute,
    required this.endMinute,
    this.label,
  });

  factory SleepWindow.fromHourMinute({
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    String? label,
  }) {
    return SleepWindow(
      startMinute: startHour * 60 + startMinute,
      endMinute: endHour * 60 + endMinute,
      label: label,
    );
  }

  int get startHour => startMinute ~/ 60;
  int get startMin => startMinute % 60;
  int get endHour => endMinute ~/ 60;
  int get endMin => endMinute % 60;

  /// Khoảng ngủ mong muốn có vắt qua nửa đêm (00:00) hay không.
  bool get crossesMidnight => endMinute < startMinute;

  /// Khoảng ngủ nằm trọn trong ban ngày (thường gặp với người làm ca đêm).
  bool get isDaytimeWindow => !crossesMidnight && startHour >= 5 && startHour < 18;

  /// Tổng thời lượng mong muốn tính bằng phút.
  int get durationMinutes {
    if (endMinute > startMinute) {
      return endMinute - startMinute;
    }
    return (1440 - startMinute) + endMinute;
  }

  Duration get duration => Duration(minutes: durationMinutes);

  String get formattedStart => formatClockMinute(startMinute);
  String get formattedEnd => formatClockMinute(endMinute);

  String get formattedRange {
    final suffix = crossesMidnight ? ' (+1 ngày)' : '';
    return '$formattedStart – $formattedEnd$suffix';
  }

  String get formattedDuration {
    final hours = durationMinutes ~/ 60;
    final mins = durationMinutes % 60;
    if (mins == 0) return '$hours giờ';
    return '$hours giờ $mins phút';
  }

  /// Định dạng phút (0..1439) thành chuỗi HH:mm.
  static String formatClockMinute(int totalMinutes) {
    final normalized = ((totalMinutes % 1440) + 1440) % 1440;
    final h = (normalized ~/ 60).toString().padLeft(2, '0');
    final m = (normalized % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Kiểm tra tính hợp lệ của khoảng ngủ mong muốn.
  static bool isValidClockMinute(int minute) => minute >= 0 && minute < 1440;

  /// Các mẫu gợi ý tùy chọn (người dùng tự do chỉnh bất kỳ giờ nào, không ép 22:00).
  static const List<SleepWindowPreset> presets = [
    SleepWindowPreset(
      title: 'Ngủ đêm phổ biến',
      description: 'Qua nửa đêm (23:00 – 07:00)',
      window: SleepWindow(
        startMinute: 23 * 60,
        endMinute: 7 * 60,
        label: 'Ngủ đêm phổ biến',
      ),
    ),
    SleepWindowPreset(
      title: 'Ca đêm — ngủ ban ngày',
      description: 'Sau ca trực 22:00–06:00 (07:30 – 15:00)',
      window: SleepWindow(
        startMinute: 7 * 60 + 30,
        endMinute: 15 * 60,
        label: 'Ca đêm — ngủ ban ngày',
      ),
    ),
    SleepWindowPreset(
      title: 'Ngủ muộn / làm ca tối',
      description: 'Bắt đầu sau nửa đêm (01:00 – 08:30)',
      window: SleepWindow(
        startMinute: 1 * 60,
        endMinute: 8 * 60 + 30,
        label: 'Ngủ muộn / làm ca tối',
      ),
    ),
    SleepWindowPreset(
      title: 'Ca sáng sớm',
      description: 'Qua nửa đêm (21:30 – 05:00)',
      window: SleepWindow(
        startMinute: 21 * 60 + 30,
        endMinute: 5 * 60,
        label: 'Ca sáng sớm',
      ),
    ),
  ];

  Map<String, dynamic> toProfilePreferencePatch() {
    return {
      'sleep_start': startMinute,
      'sleep_end': endMinute,
      if (label != null && label!.trim().isNotEmpty) 'sleep_label': label!.trim(),
    };
  }

  static SleepWindow? fromProfilePreferences(Map<String, dynamic>? stored) {
    if (stored == null) return null;
    final start = stored['sleep_start'];
    final end = stored['sleep_end'];
    if (start is! int || end is! int) return null;
    if (!isValidClockMinute(start) || !isValidClockMinute(end) || start == end) {
      return null;
    }
    return SleepWindow(
      startMinute: start,
      endMinute: end,
      label: stored['sleep_label'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SleepWindow &&
        other.startMinute == startMinute &&
        other.endMinute == endMinute &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(startMinute, endMinute, label);
}

/// Mẫu gợi ý khoảng ngủ mong muốn để chọn nhanh.
class SleepWindowPreset {
  final String title;
  final String description;
  final SleepWindow window;

  const SleepWindowPreset({
    required this.title,
    required this.description,
    required this.window,
  });
}
