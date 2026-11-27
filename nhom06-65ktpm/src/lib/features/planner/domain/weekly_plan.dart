import 'package:timezone/timezone.dart' as tz;

import '../../profile/domain/profile_time.dart';

typedef PlanInterval = ({DateTime start, DateTime end});

bool intervalsOverlap(PlanInterval a, PlanInterval b) =>
    a.start.isBefore(b.end) && b.start.isBefore(a.end);

class PlanWeek {
  PlanWeek(DateTime date, this.timeZone) : monday = mondayOf(date);

  factory PlanWeek.containing(DateTime instant, String timeZone) => PlanWeek(
    tz.TZDateTime.from(instant, profileLocation(timeZone)!),
    timeZone,
  );

  final DateTime monday;
  final String timeZone;

  static DateTime mondayOf(DateTime date) =>
      calendarDate(date)
          .subtract(Duration(days: date.weekday - DateTime.monday));

  DateTime day(int offset) => monday.add(Duration(days: offset));
  String get key => calendarDateKey(monday);

  tz.TZDateTime local(DateTime instant) =>
      tz.TZDateTime.from(instant, profileLocation(timeZone)!);

  DateTime at(DateTime date, int minute) => tz.TZDateTime(
    profileLocation(timeZone)!,
    date.year,
    date.month,
    date.day,
    minute ~/ 60,
    minute % 60,
  ).toUtc();

  PlanInterval get interval => (start: at(monday, 0), end: at(day(7), 0));

  bool contains(PlanInterval item) =>
      !item.start.isBefore(interval.start) && !item.end.isAfter(interval.end);

  PlanInterval dayInterval(int offset) =>
      (start: at(day(offset), 0), end: at(day(offset + 1), 0));
}

enum PlanItemKind {
  exercise('Vận động'),
  meal('Bữa ăn'),
  sleep('Giấc ngủ'),
  habit('Thói quen'),
  manual('Hoạt động tự đặt');

  const PlanItemKind(this.label);
  final String label;
}

enum PlanItemStatus { draft, approved, completed, skipped }

class PlanItem {
  const PlanItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.status = PlanItemStatus.draft,
    this.isLocked = false,
    this.reason,
    this.mealType,
  });

  final String id;
  final PlanItemKind kind;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final PlanItemStatus status;
  final bool isLocked;
  final String? reason;
  final String? mealType;

  PlanInterval get interval => (start: startsAt, end: endsAt);

  bool get recorded =>
      status == PlanItemStatus.completed || status == PlanItemStatus.skipped;

  bool hasStarted(DateTime now) => !startsAt.isAfter(now);

  PlanItem withLock(bool locked) => PlanItem(
    id: id,
    kind: kind,
    title: title,
    startsAt: startsAt,
    endsAt: endsAt,
    status: status,
    isLocked: locked,
    reason: reason,
    mealType: mealType,
  );
}

class WeeklyPlan {
  WeeklyPlan({required this.version, required Iterable<PlanItem> items})
    : items = List.unmodifiable(items);

  final int version;
  final List<PlanItem> items;

  List<PlanItem> upcomingReminderItems(DateTime now) => items
      .where(
        (item) =>
            item.status == PlanItemStatus.approved &&
            item.startsAt.isAfter(now),
      )
      .toList(growable: false);
}

class PlannerDraft {
  PlannerDraft(Iterable<PlanItem> items, Iterable<String> notices)
    : items = List.unmodifiable(items),
      notices = List.unmodifiable(notices);

  final List<PlanItem> items;
  final List<String> notices;
}
