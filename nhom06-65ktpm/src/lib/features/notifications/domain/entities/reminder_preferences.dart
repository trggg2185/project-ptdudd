import 'package:timezone/timezone.dart' as tz;

import '../../../profile/domain/profile_time.dart';

/// Cấu hình nhắc lịch cục bộ và giờ yên lặng của người dùng (Issue #6).
///
/// Ánh xạ 1:1 với bảng `public.reminder_preferences` trong Supabase:
/// - `owner_uid` (TEXT, PK)
/// - `quiet_hours_start` (`time`, ví dụ `22:00:00`)
/// - `quiet_hours_end` (`time`, ví dụ `07:00:00`)
/// - `reminders_enabled` (`boolean`)
/// - `timezone` (`text`, mặc định `Asia/Ho_Chi_Minh`)
/// - `version` (`integer`)
///
/// Hỗ trợ cả khung giờ yên lặng qua nửa đêm (ví dụ `22:00 – 07:00`) lẫn khung ban ngày
/// cho người làm ca đêm (ví dụ `08:00 – 15:00`).
class ReminderPreferences {
  final String ownerUid;
  final bool remindersEnabled;

  /// Phút trong ngày (`0..1439`) bắt đầu giờ yên lặng; `null` nếu không bật giờ yên lặng.
  final int? quietHoursStartMinute;

  /// Phút trong ngày (`0..1439`) kết thúc giờ yên lặng; `null` nếu không bật giờ yên lặng.
  final int? quietHoursEndMinute;

  /// Múi giờ IANA chuẩn (ví dụ `Asia/Ho_Chi_Minh`, `Asia/Tokyo`, `UTC`).
  final String timezone;

  /// Mặc định bật ẩn toàn bộ chi tiết sức khỏe trên màn hình khóa.
  final bool hideHealthDetailsOnLockScreen;

  /// Thời lượng tạm hoãn (snooze) mặc định tính theo phút.
  final int defaultSnoozeMinutes;

  final int version;
  final DateTime? updatedAt;

  const ReminderPreferences({
    required this.ownerUid,
    this.remindersEnabled = true,
    this.quietHoursStartMinute = 22 * 60,
    this.quietHoursEndMinute = 7 * 60,
    this.timezone = defaultProfileZone,
    this.hideHealthDetailsOnLockScreen = true,
    this.defaultSnoozeMinutes = 10,
    this.version = 1,
    this.updatedAt,
  });

  /// Có đang bật khoảng giờ yên lặng hợp lệ hay không.
  bool get hasQuietHours =>
      quietHoursStartMinute != null &&
      quietHoursEndMinute != null &&
      validClockMinute(quietHoursStartMinute!) &&
      validClockMinute(quietHoursEndMinute!) &&
      quietHoursStartMinute != quietHoursEndMinute;

  /// Khung giờ yên lặng đi qua mốc 00:00 (ví dụ `22:00 – 07:00`).
  bool get quietHoursCrossesMidnight =>
      hasQuietHours && quietHoursStartMinute! > quietHoursEndMinute!;

  /// Nhãn hiển thị ngắn gọn cho khoảng giờ yên lặng.
  String get quietHoursLabel {
    if (!hasQuietHours) return 'Tắt';
    return '${clockLabel(quietHoursStartMinute!)} – ${clockLabel(quietHoursEndMinute!)}';
  }

  /// Kiểm tra phút trong ngày (`0..1439`) theo múi giờ người dùng có nằm trong giờ yên lặng hay không.
  /// Khoảng yên lặng áp dụng nửa mở `[start, end)`.
  bool isMinuteInQuietHours(int minuteOfDay) {
    if (!hasQuietHours) return false;
    final start = quietHoursStartMinute!;
    final end = quietHoursEndMinute!;
    if (start < end) {
      return minuteOfDay >= start && minuteOfDay < end;
    }
    // Qua nửa đêm: [start, 1440) U [0, end)
    return minuteOfDay >= start || minuteOfDay < end;
  }

  /// Kiểm tra một mốc `DateTime` (bất kỳ UTC/local) có rơi vào giờ yên lặng theo múi giờ cấu hình không.
  bool isInQuietHours(DateTime instantUtc) {
    if (!hasQuietHours) return false;
    final location = resolveLocation();
    final zoned = tz.TZDateTime.from(instantUtc.toUtc(), location);
    return isMinuteInQuietHours(zoned.hour * 60 + zoned.minute);
  }

  /// Điều chỉnh mốc thời gian ra ngay sau khi kết thúc giờ yên lặng nếu nó rơi vào khoảng yên lặng.
  /// Trả về bản ghi `(effectiveUtc, wasDeferred)` bảo toàn chuẩn chuyển đổi DST theo `tz.Location`.
  ({DateTime effectiveUtc, bool deferred}) adjustForQuietHours(
    DateTime instantUtc,
  ) {
    final utc = instantUtc.toUtc();
    if (!hasQuietHours) {
      return (effectiveUtc: utc, deferred: false);
    }

    final location = resolveLocation();
    final zoned = tz.TZDateTime.from(utc, location);
    final minuteOfDay = zoned.hour * 60 + zoned.minute;
    if (!isMinuteInQuietHours(minuteOfDay)) {
      return (effectiveUtc: utc, deferred: false);
    }

    final start = quietHoursStartMinute!;
    final end = quietHoursEndMinute!;
    final endHour = end ~/ 60;
    final endMinute = end % 60;

    final int targetDayOffset = (start > end && minuteOfDay >= start) ? 1 : 0;
    final adjustedZoned = tz.TZDateTime(
      location,
      zoned.year,
      zoned.month,
      zoned.day + targetDayOffset,
      endHour,
      endMinute,
    );

    return (effectiveUtc: adjustedZoned.toUtc(), deferred: true);
  }

  /// Phân giải `tz.Location` cho múi giờ cấu hình, dự phòng về `Asia/Ho_Chi_Minh` hoặc `UTC`.
  tz.Location resolveLocation() {
    return profileLocation(timezone) ??
        profileLocation(defaultProfileZone) ??
        tz.UTC;
  }

  /// Xác thực dữ liệu cấu hình trước khi lưu.
  void validate() {
    if (ownerUid.trim().isEmpty) {
      throw const FormatException('Thiếu mã tài khoản cho cấu hình nhắc lịch.');
    }
    if (profileLocation(timezone) == null) {
      throw FormatException('Múi giờ IANA không hợp lệ: $timezone.');
    }
    if ((quietHoursStartMinute == null) != (quietHoursEndMinute == null)) {
      throw const FormatException(
        'Cần nhập đủ cả giờ bắt đầu và giờ kết thúc cho giờ yên lặng.',
      );
    }
    if (quietHoursStartMinute != null && quietHoursEndMinute != null) {
      if (!validClockMinute(quietHoursStartMinute!) ||
          !validClockMinute(quietHoursEndMinute!)) {
        throw const FormatException('Giờ yên lặng nằm ngoài khoảng 00:00–23:59.');
      }
      if (quietHoursStartMinute == quietHoursEndMinute) {
        throw const FormatException(
          'Giờ bắt đầu và kết thúc giờ yên lặng không được trùng nhau.',
        );
      }
    }
    if (defaultSnoozeMinutes < 1 || defaultSnoozeMinutes > 120) {
      throw const FormatException(
        'Thời gian tạm hoãn mặc định phải từ 1 đến 120 phút.',
      );
    }
  }

  ReminderPreferences copyWith({
    String? ownerUid,
    bool? remindersEnabled,
    int? quietHoursStartMinute,
    bool clearQuietHours = false,
    int? quietHoursEndMinute,
    String? timezone,
    bool? hideHealthDetailsOnLockScreen,
    int? defaultSnoozeMinutes,
    int? version,
    DateTime? updatedAt,
  }) {
    return ReminderPreferences(
      ownerUid: ownerUid ?? this.ownerUid,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      quietHoursStartMinute: clearQuietHours
          ? null
          : (quietHoursStartMinute ?? this.quietHoursStartMinute),
      quietHoursEndMinute: clearQuietHours
          ? null
          : (quietHoursEndMinute ?? this.quietHoursEndMinute),
      timezone: timezone ?? this.timezone,
      hideHealthDetailsOnLockScreen:
          hideHealthDetailsOnLockScreen ?? this.hideHealthDetailsOnLockScreen,
      defaultSnoozeMinutes: defaultSnoozeMinutes ?? this.defaultSnoozeMinutes,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Chuyển đổi sang map tương thích 100% bảng `public.reminder_preferences` trên Supabase.
  Map<String, dynamic> toSupabaseMap() {
    return {
      'owner_uid': ownerUid,
      'reminders_enabled': remindersEnabled,
      'quiet_hours_start': formatPostgresTime(quietHoursStartMinute),
      'quiet_hours_end': formatPostgresTime(quietHoursEndMinute),
      'timezone': timezone,
      'version': version,
    };
  }

  factory ReminderPreferences.fromSupabaseMap(Map<String, dynamic> map) {
    final start = parsePostgresTime(map['quiet_hours_start'] as String?);
    final end = parsePostgresTime(map['quiet_hours_end'] as String?);
    final rawTz = (map['timezone'] as String?)?.trim();
    return ReminderPreferences(
      ownerUid: map['owner_uid'] as String,
      remindersEnabled: map['reminders_enabled'] as bool? ?? true,
      quietHoursStartMinute: (start != null && end != null) ? start : null,
      quietHoursEndMinute: (start != null && end != null) ? end : null,
      timezone: (rawTz != null && profileLocation(rawTz) != null)
          ? rawTz
          : defaultProfileZone,
      hideHealthDetailsOnLockScreen: true,
      defaultSnoozeMinutes: 10,
      version: (map['version'] as num?)?.toInt() ?? 1,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
    );
  }

  /// Định dạng phút `0..1439` sang chuỗi PostgreSQL `time` (`HH:mm:00`).
  static String? formatPostgresTime(int? minuteOfDay) {
    if (minuteOfDay == null || !validClockMinute(minuteOfDay)) return null;
    final hh = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
    final mm = (minuteOfDay % 60).toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  /// Phân tích chuỗi PostgreSQL `time` (`HH:mm` hoặc `HH:mm:ss`) về phút trong ngày.
  static int? parsePostgresTime(String? raw) {
    if (raw == null) return null;
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ReminderPreferences &&
            other.ownerUid == ownerUid &&
            other.remindersEnabled == remindersEnabled &&
            other.quietHoursStartMinute == quietHoursStartMinute &&
            other.quietHoursEndMinute == quietHoursEndMinute &&
            other.timezone == timezone &&
            other.hideHealthDetailsOnLockScreen ==
                hideHealthDetailsOnLockScreen &&
            other.defaultSnoozeMinutes == defaultSnoozeMinutes &&
            other.version == version);
  }

  @override
  int get hashCode => Object.hash(
    ownerUid,
    remindersEnabled,
    quietHoursStartMinute,
    quietHoursEndMinute,
    timezone,
    hideHealthDetailsOnLockScreen,
    defaultSnoozeMinutes,
    version,
  );
}
