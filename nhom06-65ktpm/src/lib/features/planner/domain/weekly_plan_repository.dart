import 'weekly_plan.dart';

class PlannerSaveException implements Exception {
  const PlannerSaveException(this.message);
  final String message;
}

abstract interface class WeeklyPlanRepository {
  Future<WeeklyPlan?> load(PlanWeek week);

  Future<WeeklyPlan> approve({
    required PlanWeek week,
    required int? expectedVersion,
    required List<PlanItem> items,
  });

  Future<WeeklyPlan> recordOutcome({
    required PlanWeek week,
    required int expectedVersion,
    required String itemId,
    required PlanItemStatus outcome,
  });
}
