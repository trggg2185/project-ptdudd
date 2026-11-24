import 'package:timezone/timezone.dart' as tz;

import 'profile_time.dart';

enum ScheduleKind { work, busy, manual }

class ScheduleBlock {
  ScheduleBlock({
    required this.id,
    required this.kind,
    required this.title,
    required this.timeZone,
    required DateTime startsAt,
    required DateTime endsAt,
    this.travelMinutes = 0,
    this.repeatsWeekly = false,
    Iterable<DateTime> exceptionDates = const [],
  }) : startsAt = startsAt.toUtc(),
       endsAt = endsAt.toUtc(),
       exceptionDates = Set.unmodifiable(exceptionDates.map(calendarDate));

  factory ScheduleBlock.fromLocal({
    required String id,
    required ScheduleKind kind,
    required String title,
    required String timeZone,
    required DateTime date,
    required int startMinute,
    required int endMinute,
    int travelMinutes = 0,
    bool repeatsWeekly = false,
    Iterable<DateTime> exceptionDates = const [],
  }) {
    final location = profileLocation(timeZone);
    if (location == null) {
      throw const FormatException('Múi giờ không hợp lệ. Hãy nhập mã IANA.');
    }
    if (!validClockMinute(startMinute) ||
        !validClockMinute(endMinute) ||
        startMinute == endMinute) {
      throw const FormatException('Giờ bắt đầu và kết thúc phải khác nhau.');
    }
    final endDate = DateTime.utc(
      date.year,
      date.month,
      date.day + (endMinute < startMinute ? 1 : 0),
    );
    final start = _clockAt(location, date, startMinute);
    final end = _clockAt(location, endDate, endMinute);
    final block = ScheduleBlock(
      id: id,
      kind: kind,
      title: title.trim(),
      timeZone: timeZone,
      startsAt: start,
      endsAt: end,
      travelMinutes: travelMinutes,
      repeatsWeekly: repeatsWeekly,
      exceptionDates: exceptionDates,
    );
    block.validate();
    return block;
  }

  final String id;
  final ScheduleKind kind;
  final String title;
  final String timeZone;
  final DateTime startsAt;
  final DateTime endsAt;
  final int travelMinutes;
  final bool repeatsWeekly;
  final Set<DateTime> exceptionDates;

  tz.TZDateTime get localStart =>
      tz.TZDateTime.from(startsAt, profileLocation(timeZone)!);
  tz.TZDateTime get localEnd =>
      tz.TZDateTime.from(endsAt, profileLocation(timeZone)!);

  void validate() {
    if (title.trim().isEmpty || title.length > 80) {
      throw const FormatException('Nhập tên khoảng lịch từ 1 đến 80 ký tự.');
    }
    if (profileLocation(timeZone) == null || !endsAt.isAfter(startsAt)) {
      throw const FormatException(
        'Khoảng thời gian hoặc múi giờ không hợp lệ.',
      );
    }
    if (travelMinutes < 0 || travelMinutes > 1440) {
      throw const FormatException(
        'Thời gian đi lại nằm trong khoảng 0–1440 phút.',
      );
    }
    final firstDate = calendarDate(localStart);
    if ((!repeatsWeekly && exceptionDates.isNotEmpty) ||
        exceptionDates.any(
          (date) =>
              date.isBefore(firstDate) || date.weekday != firstDate.weekday,
        )) {
      throw const FormatException(
        'Ngày ngoại lệ phải trùng ngày bắt đầu của một kỳ lặp.',
      );
    }
  }

  /// The argument identifies a civil day in [timeZone].
  /// The result includes the one-way travel allowance at both ends.
  ({DateTime start, DateTime end})? occupiedTimeOn(DateTime date) {
    final day = calendarDate(date);
    final startClock = localStart;
    final endClock = localEnd;
    final first = calendarDate(startClock);
    if (day.isBefore(first) ||
        exceptionDates.contains(day) ||
        (day != first && (!repeatsWeekly || day.weekday != first.weekday))) {
      return null;
    }
    final travel = Duration(minutes: travelMinutes);
    if (day == first) {
      return (start: startsAt.subtract(travel), end: endsAt.add(travel));
    }
    final location = profileLocation(timeZone)!;
    final start = tz.TZDateTime(
      location,
      day.year,
      day.month,
      day.day,
      startClock.hour,
      startClock.minute,
    );
    final dayOffset = calendarDate(endClock).difference(first).inDays;
    final end = tz.TZDateTime(
      location,
      day.year,
      day.month,
      day.day + dayOffset,
      endClock.hour,
      endClock.minute,
    );
    return (
      start: start.toUtc().subtract(travel),
      end:
          (end.isAfter(start)
                  ? end.toUtc()
                  : start.toUtc().add(endsAt.difference(startsAt)))
              .add(travel),
    );
  }

  static tz.TZDateTime _clockAt(tz.Location zone, DateTime date, int minute) {
    final hour = minute ~/ 60;
    final time = tz.TZDateTime(
      zone,
      date.year,
      date.month,
      date.day,
      hour,
      minute % 60,
    );
    if (calendarDate(time) != calendarDate(date) ||
        time.hour != hour ||
        time.minute != minute % 60) {
      throw const FormatException(
        'Giờ này không tồn tại tại ngày và múi giờ đã chọn.',
      );
    }
    return time;
  }
}
