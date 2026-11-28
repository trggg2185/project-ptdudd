import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/planner/domain/weekly_plan.dart';
import 'package:healthylife/features/planner/domain/weekly_planner.dart';
import 'package:healthylife/features/profile/domain/health_profile.dart';
import 'package:healthylife/features/profile/domain/schedule_block.dart';
import 'package:healthylife/features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'package:healthylife/features/recommendations/domain/usecases/get_recommendations_usecase.dart';

const zone = 'Asia/Ho_Chi_Minh';
final monday = DateTime.utc(2026, 12, 7);
const planner = WeeklyPlanner(
  GetRecommendationsUseCase(repository: FixtureCatalogRepository()),
);

HealthProfile profile({
  int target = 3,
  bool confirmedAllergies = true,
  String timezone = zone,
}) => HealthProfile(
  adultConfirmed: true,
  timeZone: timezone,
  goal: ProfileGoal.regularActivity,
  activityLevel: ActivityLevel.beginner,
  sessionMinutes: 30,
  sessionsPerWeek: target,
  sleepStart: 450,
  sleepEnd: 900,
  allergyStatus: confirmedAllergies
      ? AllergyStatus.none
      : AllergyStatus.unconfirmed,
);

PlanItem workout(
  PlanWeek week,
  String id,
  int day,
  int start,
  PlanItemStatus status, {
  bool locked = false,
}) => PlanItem(
  id: id,
  kind: PlanItemKind.exercise,
  title: id,
  startsAt: week.at(week.day(day), start),
  endsAt: week.at(week.day(day), start + 20),
  status: status,
  isLocked: locked,
);

void main() {
  test('night shift, travel, weekly exceptions, sleep and overlapping reservations constrain proposals', () async {
    final week = PlanWeek(monday, zone);
    final night = ScheduleBlock.fromLocal(
      id: 'shift',
      kind: ScheduleKind.work,
      title: 'Ca đêm',
      timeZone: zone,
      date: week.day(-7),
      startMinute: 1320,
      endMinute: 360,
      repeatsWeekly: true,
      travelMinutes: 30,
      exceptionDates: [week.day(0)],
    );
    final previousNight = ScheduleBlock.fromLocal(
      id: 'previous',
      kind: ScheduleKind.work,
      title: 'Ca Chủ nhật',
      timeZone: zone,
      date: week.day(-1),
      startMinute: 1320,
      endMinute: 360,
      travelMinutes: 30,
    );
    final busy = ScheduleBlock.fromLocal(
      id: 'busy',
      kind: ScheduleKind.busy,
      title: 'Lịch bận',
      timeZone: zone,
      date: week.day(0),
      startMinute: 365,
      endMinute: 590,
    );
    final calendar = PlannerCalendar(week, (
      profile: profile(),
      blocks: [night, previousNight, busy],
    ));

    expect(
      calendar.reservations.any((r) => r.title.startsWith('Ca đêm')),
      isFalse,
    );
    expect(
      calendar.reservations
          .singleWhere((r) => r.title.startsWith('Ca Chủ nhật'))
          .interval
          .end,
      week.at(monday, 390),
    );
    final proposals = await planner.generate(
      calendar: calendar,
      current: [],
      now: week.at(monday, 0),
    );
    expect(
      proposals.items.where((i) => i.kind == PlanItemKind.exercise),
      hasLength(3),
    );
    expect(
      proposals.items.where((i) => i.kind == PlanItemKind.meal),
      isNotEmpty,
    );
    for (final item in proposals.items) {
      expect(calendar.conflictFor(item, proposals.items), isNull);
    }
  });

  test('insufficient time leaves activities unscheduled', () async {
    final week = PlanWeek(monday, zone);
    final unavailable = ScheduleBlock(
      id: 'long',
      kind: ScheduleKind.busy,
      title: 'Bận cả tuần',
      timeZone: zone,
      startsAt: week.interval.start,
      endsAt: week.interval.end,
    );
    final draft = await planner.generate(
      calendar: PlannerCalendar(week, (
        profile: profile(),
        blocks: [unavailable],
      )),
      current: [],
      now: week.interval.start,
    );
    expect(draft.items, isEmpty);
    expect(draft.notices, anyElement(contains('0/3 buổi tập')));
  });

  test('suggestions at the opening of a window start in the future', () async {
    final week = PlanWeek(monday, zone);
    final calendar = PlannerCalendar(week, (profile: profile(), blocks: []));

    for (final (minute, kind) in [
      (0, PlanItemKind.exercise),
      (360, PlanItemKind.meal),
    ]) {
      final now = week.at(monday, minute);
      final draft = await planner.generate(
        calendar: calendar,
        current: [],
        now: now,
      );

      expect(draft.items.where((item) => item.hasStarted(now)), isEmpty);
      final start = draft.items.firstWhere((item) => item.kind == kind).startsAt;
      expect(start.difference(now), const Duration(minutes: 1));
    }
  });

  test('a skipped item preserves history and releases its remaining time', () async {
    final week = PlanWeek(monday, zone);
    final calendar = PlannerCalendar(week, (profile: profile(), blocks: []));
    final skipped = PlanItem(
      id: 'skipped',
      kind: PlanItemKind.manual,
      title: 'Đã bỏ qua',
      startsAt: week.at(monday, 350),
      endsAt: week.at(monday, 450),
      status: PlanItemStatus.skipped,
      isLocked: true,
    );
    final draft = await planner.generate(
      calendar: calendar,
      current: [skipped],
      now: week.at(monday, 355),
    );

    expect(draft.items, contains(same(skipped)));
    final breakfast = draft.items.firstWhere(
      (item) => item.mealType == 'breakfast',
    );
    expect(breakfast.startsAt, week.at(monday, 360));
    expect(calendar.conflictFor(breakfast, draft.items), isNull);
    final completed = workout(
      week,
      'Đã hoàn thành',
      0,
      360,
      PlanItemStatus.completed,
    );
    expect(
      calendar.conflictFor(breakfast, [completed]),
      contains(completed.title),
    );
  });

  test('rotates suitable workouts through the week', () async {
    final week = PlanWeek(monday, zone);
    final userProfile = profile();
    final exercises = await planner.recommendations.getExerciseRecommendations(
      profile: userProfile.toRecommendationProfile(),
    );
    final draft = await planner.generate(
      calendar: PlannerCalendar(week, (profile: userProfile, blocks: [])),
      current: [],
      now: week.interval.start,
    );
    final workouts = draft.items.where(
      (item) => item.kind == PlanItemKind.exercise,
    );

    expect(exercises.recommendations, hasLength(3));
    expect(
      workouts.map((item) => item.title),
      exercises.recommendations.map((exercise) => exercise.item.name),
    );
    expect(
      workouts.map((item) => item.endsAt.difference(item.startsAt).inMinutes),
      exercises.recommendations.map((exercise) => exercise.item.durationMinutes),
    );
  });

  test('tries a shorter workout when the rotated choice cannot fit', () async {
    final week = PlanWeek(monday, zone);
    final shortDay = ScheduleBlock(
      id: 'busy-tuesday',
      kind: ScheduleKind.busy,
      title: 'Lịch bận thứ Ba',
      timeZone: zone,
      startsAt: week.at(week.day(1), 12),
      endsAt: week.dayInterval(1).end,
    );
    final draft = await planner.generate(
      calendar: PlannerCalendar(week, (profile: profile(), blocks: [shortDay])),
      current: [],
      now: week.interval.start,
    );
    final tuesday = draft.items.singleWhere(
      (item) =>
          item.kind == PlanItemKind.exercise &&
          intervalsOverlap(item.interval, week.dayInterval(1)),
    );
    expect(tuesday.startsAt, week.dayInterval(1).start);
    expect(tuesday.endsAt.difference(tuesday.startsAt).inMinutes, 10);
  });

  test('regenerating after a shift change preserves history and locks without catch-up workouts', () async {
    final week = PlanWeek(monday, zone);
    final now = week.at(week.day(2), 600);
    final done = workout(week, 'Đã tập', 0, 990, PlanItemStatus.completed);
    final skipped = workout(week, 'Đã bỏ', 1, 990, PlanItemStatus.skipped);
    final locked = workout(
      week,
      'Đã khóa',
      3,
      990,
      PlanItemStatus.approved,
      locked: true,
    );
    final change = ScheduleBlock.fromLocal(
      id: 'changed',
      kind: ScheduleKind.work,
      title: 'Ca vừa đổi',
      timeZone: zone,
      date: week.day(3),
      startMinute: 970,
      endMinute: 1080,
    );
    final calendar = PlannerCalendar(week, (
      profile: profile(),
      blocks: [change],
    ));
    final draft = await planner.generate(
      calendar: calendar,
      current: [
        done,
        skipped,
        locked,
        workout(week, 'Hết giờ', 2, 450, PlanItemStatus.draft),
      ],
      now: now,
    );
    expect(draft.items.where((i) => i.kind == PlanItemKind.exercise), [
      done,
      skipped,
      locked,
    ]);
    expect(calendar.conflictFor(locked, draft.items), contains('Ca vừa đổi'));
  });

  test('timezone changes keep original shift instants and account for DST week length', () {
    final week = PlanWeek(DateTime.utc(2027, 3, 8), 'America/New_York');
    final shift = ScheduleBlock.fromLocal(
      id: 'shift-vn',
      kind: ScheduleKind.work,
      title: 'Ca ở Việt Nam',
      timeZone: zone,
      date: DateTime.utc(2027, 3, 7),
      startMinute: 1320,
      endMinute: 360,
      repeatsWeekly: true,
      travelMinutes: 30,
    );
    final calendar = PlannerCalendar(week, (
      profile: profile(timezone: week.timeZone),
      blocks: [shift],
    ));
    expect(
      week.interval.end.difference(week.interval.start),
      const Duration(hours: 167),
    );
    final occupied = calendar.reservations.singleWhere(
      (r) => r.title.startsWith('Ca ở Việt Nam'),
    );
    expect(
      occupied.interval.start.isAtSameMomentAs(
        DateTime.utc(2027, 3, 14, 14, 30),
      ),
      isTrue,
    );
    expect(week.local(occupied.interval.start).hour, 10);
  });

  test('unconfirmed allergies block automatic meal items and missing sleep retains manual options', () async {
    final week = PlanWeek(monday, zone);
    final gated = await planner.generate(
      calendar: PlannerCalendar(week, (
        profile: profile(confirmedAllergies: false),
        blocks: [],
      )),
      current: [],
      now: week.interval.start,
    );
    expect(gated.items.where((i) => i.kind == PlanItemKind.meal), isEmpty);
    expect(gated.notices, anyElement(contains('dị ứng')));
    final manual = await planner.generate(
      calendar: PlannerCalendar(week, (profile: HealthProfile(), blocks: [])),
      current: [
        workout(week, 'tự đặt', 2, 990, PlanItemStatus.draft, locked: true),
      ],
      now: week.interval.start,
    );
    expect(manual.items.single.title, 'tự đặt');
    expect(manual.notices, anyElement(contains('thủ công')));
  });

  test(
    'reminder inputs contain only upcoming items from an approved snapshot',
    () {
      final week = PlanWeek(monday, zone);
      final now = week.dayInterval(1).start;
      final upcoming = workout(
        week,
        'approved',
        2,
        950,
        PlanItemStatus.approved,
      );
      final plan = WeeklyPlan(
        version: 1,
        items: [
          workout(week, 'past', 0, 950, PlanItemStatus.approved),
          workout(week, 'draft', 2, 990, PlanItemStatus.draft),
          workout(week, 'done', 2, 1030, PlanItemStatus.completed),
          upcoming,
        ],
      );
      expect(plan.upcomingReminderItems(now), [upcoming]);
    },
  );
}
