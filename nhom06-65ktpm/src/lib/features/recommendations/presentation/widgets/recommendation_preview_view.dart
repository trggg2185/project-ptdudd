import 'package:flutter/material.dart';

import '../../domain/entities/exercise_catalog_item.dart';
import '../../domain/entities/meal_catalog_item.dart';
import '../../domain/entities/recommendation_result.dart';

/// Giao diện hiển thị gợi ý môn tập và món ăn có giải thích (độc lập với `main.dart`).
/// Dùng để nhóm trưởng tích hợp vào điều hướng chung và phục vụ widget test.
class RecommendationPreviewView extends StatelessWidget {
  final RecommendationResult<ExerciseCatalogItem> exerciseResult;
  final RecommendationResult<MealCatalogItem> mealResult;
  final ValueChanged<ExerciseCatalogItem>? onSelectExercise;
  final ValueChanged<MealCatalogItem>? onSelectMeal;

  const RecommendationPreviewView({
    super.key,
    required this.exerciseResult,
    required this.mealResult,
    this.onSelectExercise,
    this.onSelectMeal,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              RecommendationResult.productRuleDisclaimer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Gợi ý môn tập',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (exerciseResult.isEmpty)
          _EmptyNoticeCard(
            message:
                exerciseResult.emptyReason ?? 'Chưa có gợi ý môn tập phù hợp.',
          )
        else
          ...exerciseResult.recommendations.map(
            (rec) => _RecommendationCard(
              title: rec.item.name,
              explanation: rec.explanation,
              conditions: rec.conditionsSummary,
              onSelect: onSelectExercise == null
                  ? null
                  : () => onSelectExercise!(rec.item),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Gợi ý món ăn',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (mealResult.isEmpty)
          _EmptyNoticeCard(
            message: mealResult.emptyReason ?? 'Chưa có gợi ý món ăn phù hợp.',
          )
        else
          ...mealResult.recommendations.map(
            (rec) => _RecommendationCard(
              title: rec.item.name,
              explanation: rec.explanation,
              conditions: rec.conditionsSummary,
              onSelect:
                  onSelectMeal == null ? null : () => onSelectMeal!(rec.item),
            ),
          ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final String title;
  final String explanation;
  final String conditions;
  final VoidCallback? onSelect;

  const _RecommendationCard({
    required this.title,
    required this.explanation,
    required this.conditions,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(explanation),
            const SizedBox(height: 4),
            Text(
              conditions,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onSelect != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onSelect,
                  child: const Text('Chọn gợi ý này'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyNoticeCard extends StatelessWidget {
  final String message;

  const _EmptyNoticeCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message),
      ),
    );
  }
}
