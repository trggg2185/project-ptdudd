import '../../../core/utils/id_generator.dart';
import '../../profile/domain/profile_repository.dart';
import '../../profile/domain/profile_time.dart';
import '../../recommendations/domain/usecases/get_recommendations_usecase.dart';
import 'weekly_plan.dart';

class PlannerReservation {
  const PlannerReservation(this.title, this.interval);

  final String title;
  final PlanInterval interval;
}

class PlannerCalendar {
  PlannerCalendar(this.week, this.profileData)
    : reservations = List.unmodifiable(_reservations(week, profileData));

  final PlanWeek week;
  final ProfileData profileData;
  final List<PlannerReservation> reservations;

  static Iterable<PlannerReservation> _reservations(
    PlanWeek week,
    ProfileData data,
  ) sync* {
    final range = week.interval;
    for (final block in data.blocks) {
      final title = block.travelMinutes > 0
          ? '${block.title} · gồm thời gian đi lại'
          : block.title;
      for (final time in block.occupiedTimesBetween(range.start, range.end)) {
        yield PlannerReservation(title, time);
      }
    }
    final start = data.profile.sleepStart;
    final end = data.profile.sleepEnd;
    if (start == null ||
        end == null ||
        !validClockMinute(start) ||
        !validClockMinute(end) ||
        start == end) {
      return;
    }
    for (var day = -1; day < 7; day++) {
      final interval = (
        start: week.at(week.day(day), start),
        end: week.at(week.day(day + (end < start ? 1 : 0)), end),
      );
      if (interval.end.isAfter(interval.start) &&
          intervalsOverlap(interval, range)) {
        yield PlannerReservation('Giờ ngủ mong muốn', interval);
      }
    }
  }

  String? conflictFor(PlanItem item, Iterable<PlanItem> items) {
    if (!item.endsAt.isAfter(item.startsAt) || !week.contains(item.interval)) {
      return 'Khoảng giờ nằm ngoài tuần theo múi giờ hiện tại.';
    }
    for (final reservation in reservations) {
      if (intervalsOverlap(item.interval, reservation.interval)) {
        return 'Trùng với ${reservation.title}.';
      }
    }
    for (final other in items) {
      if (other.id != item.id &&
          intervalsOverlap(item.interval, other.interval)) {
        return 'Trùng với ${other.title}.';
      }
    }
    return null;
  }
}

class WeeklyPlanner {
  const WeeklyPlanner(this.recommendations);

  final GetRecommendationsUseCase recommendations;

  static const _mealWindows = [
    (code: 'breakfast', label: 'bữa sáng', start: 360, end: 600),
    (code: 'lunch', label: 'bữa trưa', start: 660, end: 900),
    (code: 'dinner', label: 'bữa tối', start: 1020, end: 1320),
  ];

  Future<PlannerDraft> generate({
    required PlannerCalendar calendar,
    required List<PlanItem> current,
    required DateTime now,
  }) async {
    final week = calendar.week;
    final profile = calendar.profileData.profile;
    final items = [
      for (final item in current)
        if (item.isLocked ||
            item.recorded ||
            (item.status == PlanItemStatus.approved && item.hasStarted(now)))
          item,
    ];
    final notices = <String>[];
    final reason = profile.automaticScheduleBlockReason;
    if (reason != null ||
        profile.sleepStart == null ||
        profile.sleepEnd == null ||
        !validClockMinute(profile.sleepStart!) ||
        !validClockMinute(profile.sleepEnd!) ||
        profile.sleepStart == profile.sleepEnd) {
      return PlannerDraft(current, [
        reason ?? 'Đặt khoảng ngủ mong muốn trong hồ sơ để tạo lịch tự động.',
        'Bạn vẫn có thể thêm hoạt động thủ công.',
      ]);
    }
    final recommendationProfile = profile.toRecommendationProfile();
    final exercises = await recommendations.getExerciseRecommendations(
      profile: recommendationProfile,
    );
    final mealResults = await Future.wait([
      for (final window in _mealWindows)
        recommendations.getMealRecommendations(
          profile: recommendationProfile,
          mealType: window.code,
        ),
    ]);
    if (exercises.isEmpty && exercises.emptyReason != null) {
      notices.add(exercises.emptyReason!);
    }

    final workoutTarget = profile.sessionsPerWeek!;
    var workoutCount = items
        .where((item) => item.kind == PlanItemKind.exercise)
        .length;
    var missingMeals = 0;
    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
      final date = week.day(dayIndex);
      final day = week.dayInterval(dayIndex);
      if (!day.end.isAfter(now)) continue;
      for (final (index, window) in _mealWindows.indexed) {
        if (items.any(
          (item) =>
              item.kind == PlanItemKind.meal &&
              item.mealType == window.code &&
              intervalsOverlap(item.interval, day),
        )) {
          continue;
        }
        final candidates = mealResults[index].recommendations;
        if (candidates.isEmpty) continue;
        final mealWindow = (
          start: week.at(date, window.start),
          end: week.at(date, window.end),
        );
        if (!mealWindow.end.isAfter(now)) continue;
        final start = _freeStart(
          calendar,
          items,
          mealWindow,
          const Duration(minutes: 30),
          now,
        );
        if (start == null) {
          missingMeals++;
          continue;
        }
        final candidate = candidates[dayIndex % candidates.length];
        items.add(
          PlanItem(
            id: IdGenerator.generateUuid(),
            kind: PlanItemKind.meal,
            title: candidate.item.name,
            startsAt: start,
            endsAt: start.add(const Duration(minutes: 30)),
            reason:
                '${candidate.explanation} Có đủ 30 phút cho ${window.label}.',
            mealType: window.code,
          ),
        );
      }

      if (workoutCount >= workoutTarget ||
          items.any(
            (item) =>
                item.kind == PlanItemKind.exercise &&
                intervalsOverlap(item.interval, day),
          )) {
        continue;
      }
      for (final exercise in exercises.recommendations) {
        final duration = Duration(minutes: exercise.item.durationMinutes);
        if (duration <= Duration.zero) continue;
        final start = _freeStart(calendar, items, day, duration, now);
        if (start == null) continue;
        items.add(
          PlanItem(
            id: IdGenerator.generateUuid(),
            kind: PlanItemKind.exercise,
            title: exercise.item.name,
            startsAt: start,
            endsAt: start.add(duration),
            reason:
                '${exercise.explanation} Còn đủ ${duration.inMinutes} phút trong lịch.',
          ),
        );
        workoutCount++;
        break;
      }
    }

    if (workoutCount < workoutTarget && exercises.hasRecommendations) {
      notices.add(
        'Xếp được $workoutCount/$workoutTarget buổi tập. Các buổi còn thiếu cần thêm khoảng trống.',
      );
    }
    if (missingMeals > 0) {
      notices.add(
        '$missingMeals bữa chưa có đủ 30 phút rảnh trong khung giờ gợi ý.',
      );
    }
    final unavailableMeals = [
      for (final (index, window) in _mealWindows.indexed)
        if (mealResults[index].isEmpty) window.label,
    ];
    if (unavailableMeals.isNotEmpty) {
      final reason = !profile.allergiesAreConfirmed
          ? 'Xác nhận thông tin dị ứng để nhận gợi ý món ăn.'
          : 'Chưa có món phù hợp hồ sơ cho ${unavailableMeals.join(', ')}.';
      notices.add(reason);
    }
    items.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return PlannerDraft(items, notices);
  }

  static DateTime? _freeStart(
    PlannerCalendar calendar,
    List<PlanItem> items,
    PlanInterval window,
    Duration duration,
    DateTime now,
  ) {
    final blocked = [
      ...calendar.reservations.map((reservation) => reservation.interval),
      ...items.map((item) => item.interval),
    ]..sort((a, b) => a.start.compareTo(b.start));
    var start = window.start.isBefore(now)
        ? DateTime.fromMillisecondsSinceEpoch(
            ((now.millisecondsSinceEpoch ~/ 60000) + 1) * 60000,
            isUtc: true,
          )
        : window.start;
    for (final interval in blocked) {
      if (!interval.end.isAfter(start)) continue;
      if (!interval.start.isBefore(window.end) ||
          !start.add(duration).isAfter(interval.start)) {
        break;
      }
      start = interval.end;
    }
    return start.add(duration).isAfter(window.end) ? null : start;
  }
}
