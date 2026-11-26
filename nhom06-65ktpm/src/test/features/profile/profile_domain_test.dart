import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/profile/domain/health_profile.dart';
import 'package:healthylife/features/profile/domain/schedule_block.dart';
import 'package:healthylife/features/recommendations/data/fixtures/sample_catalog_fixture.dart';
import 'package:healthylife/features/recommendations/domain/services/catalog_hard_filter.dart';

void main() {
  HealthProfile complete({
    AllergyStatus allergyStatus = AllergyStatus.unconfirmed,
  }) => HealthProfile(
    adultConfirmed: true,
    timeZone: 'Asia/Ho_Chi_Minh',
    activityLevel: ActivityLevel.beginner,
    goal: ProfileGoal.regularActivity,
    sessionMinutes: 30,
    sessionsPerWeek: 3,
    allergyStatus: allergyStatus,
    allergens: const ['fish'],
    avoidedIngredients: const ['Đậu phộng'],
  );

  test(
    'profile readiness requires confirmation, a valid zone and activity data',
    () {
      expect(HealthProfile().automaticScheduleBlockReason, isNotNull);
      final missingActivity = HealthProfile(
        adultConfirmed: true,
        timeZone: 'Asia/Ho_Chi_Minh',
        goal: ProfileGoal.regularActivity,
        sessionMinutes: 30,
        sessionsPerWeek: 3,
      );
      expect(missingActivity.automaticScheduleBlockReason, isNotNull);
      expect(
        const CatalogHardFilter().validateBaseInput<Object>(
          missingActivity.toRecommendationProfile(),
        ),
        isNotNull,
      );
      expect(complete().automaticScheduleBlockReason, isNull);
      expect(complete().toRecommendationProfile().allergiesConfirmed, isFalse);
      expect(
        HealthProfile(timeZone: 'Invalid/Zone').validate,
        throwsFormatException,
      );
    },
  );

  test('validate rejects contradictory or partial preferences', () {
    expect(HealthProfile(sessionMinutes: 241).validate, throwsFormatException);
    expect(HealthProfile(mealBudget: -1).validate, throwsFormatException);
    expect(HealthProfile(sleepStart: 1320).validate, throwsFormatException);
    expect(
      HealthProfile(sleepStart: 1320, sleepEnd: 360).validate,
      returnsNormally,
    );
    expect(
      HealthProfile(allergyStatus: AllergyStatus.declared).validate,
      throwsFormatException,
    );
    expect(
      HealthProfile(
        preferredSports: ['cardio'],
        dislikedSports: ['cardio'],
      ).validate,
      throwsFormatException,
    );
  });

  test('confirmed allergies and Vietnamese ingredient names reach the recommendation filter', () {
    final input = complete(allergyStatus: AllergyStatus.declared)
        .toRecommendationProfile();
    expect(input.allergiesConfirmed, isTrue);
    expect(input.avoidedIngredients, ['dau_phong']);
    final result = const CatalogHardFilter().filterMeals(
      catalog: SampleCatalogFixture.sampleMeals,
      profile: input,
    );
    final excluded = result.excludedItems.map((entry) => entry.item.slug);
    expect(
      excluded,
      containsAll(['salmon-brown-rice-bowl', 'shrimp-fresh-spring-rolls']),
    );
  });

  test('the current and legacy movement codes both exclude jump rope', () {
    const filter = CatalogHardFilter();
    final rope = SampleCatalogFixture.sampleExercises.singleWhere(
      (exercise) => exercise.slug == 'jump-rope',
    );
    HealthProfile withLimits(Iterable<String> limits) => HealthProfile(
      adultConfirmed: true,
      timeZone: 'Asia/Ho_Chi_Minh',
      goal: ProfileGoal.regularActivity,
      activityLevel: ActivityLevel.advanced,
      sessionMinutes: 45,
      sessionsPerWeek: 3,
      equipment: const ['jump_rope'],
      movementLimits: limits,
    );
    expect(
      filter
          .filterExercises(
            catalog: [rope],
            profile: withLimits(const []).toRecommendationProfile(),
          )
          .eligibleItems,
      [rope],
    );
    expect(
      HealthProfile.movementOptions,
      contains('high_intensity_restricted'),
    );
    for (final code in ['high_intensity_restricted', 'high_impact']) {
      final profile = withLimits([code]);
      expect(profile.movementLimits, {'high_intensity_restricted'});
      final result = filter.filterExercises(
        catalog: [rope],
        profile: profile.toRecommendationProfile(),
      );
      expect(result.eligibleItems, isEmpty);
      expect(
        result.excludedItems.single.reasons.join(' '),
        contains('high_intensity_restricted'),
      );
    }
  });

  test(
    'overnight work reserves both travel legs and skips weekly exceptions',
    () {
      final block = ScheduleBlock.fromLocal(
        id: 'shift',
        kind: ScheduleKind.work,
        title: 'Ca đêm',
        timeZone: 'Asia/Ho_Chi_Minh',
        date: DateTime.utc(2026, 11, 24),
        startMinute: 22 * 60,
        endMinute: 6 * 60,
        travelMinutes: 30,
        repeatsWeekly: true,
        exceptionDates: [DateTime.utc(2026, 12, 1)],
      );
      expect(block.startsAt, DateTime.utc(2026, 11, 24, 15));
      expect(block.endsAt, DateTime.utc(2026, 11, 24, 23));
      expect(block.localEnd.day, 25);
      expect(block.occupiedTimeOn(DateTime.utc(2026, 11, 24)), (
        start: DateTime.utc(2026, 11, 24, 14, 30),
        end: DateTime.utc(2026, 11, 24, 23, 30),
      ));
      expect(block.occupiedTimeOn(DateTime.utc(2026, 12, 1)), isNull);
      expect(block.occupiedTimeOn(DateTime.utc(2026, 12, 2)), isNull);
      expect(
        block.occupiedTimeOn(DateTime.utc(2026, 12, 8))?.start,
        DateTime.utc(2026, 12, 8, 14, 30),
      );
    },
  );

  test('weekly slots keep the same wall time across a DST change', () {
    final block = ScheduleBlock.fromLocal(
      id: 'weekly',
      kind: ScheduleKind.busy,
      title: 'Lịch bận',
      timeZone: 'America/New_York',
      date: DateTime.utc(2026, 3, 1),
      startMinute: 22 * 60,
      endMinute: 23 * 60,
      repeatsWeekly: true,
    );
    expect(block.startsAt, DateTime.utc(2026, 3, 2, 3));
    expect(
      block.occupiedTimeOn(DateTime.utc(2026, 3, 8))?.start,
      DateTime.utc(2026, 3, 9, 2),
    );
    expect(
      () => ScheduleBlock.fromLocal(
        id: 'invalid',
        kind: ScheduleKind.manual,
        title: 'Giờ không tồn tại',
        timeZone: 'America/New_York',
        date: DateTime.utc(2026, 3, 8),
        startMinute: 150,
        endMinute: 210,
      ),
      throwsFormatException,
    );
  });

  test('equal times and exceptions on other weekdays are rejected', () {
    ScheduleBlock block(int end, List<DateTime> exceptions) =>
        ScheduleBlock.fromLocal(
          id: 'manual',
          kind: ScheduleKind.manual,
          title: 'Đi bộ',
          timeZone: 'UTC',
          date: DateTime.utc(2026, 11, 24),
          startMinute: 600,
          endMinute: end,
          repeatsWeekly: true,
          exceptionDates: exceptions,
        );
    expect(() => block(600, []), throwsFormatException);
    expect(
      () => block(620, [DateTime.utc(2026, 11, 25)]),
      throwsFormatException,
    );
  });
}
