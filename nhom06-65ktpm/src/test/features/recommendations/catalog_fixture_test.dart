import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/recommendations/data/fixtures/sample_catalog_fixture.dart';
import 'package:healthylife/features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'package:healthylife/features/recommendations/domain/entities/exercise_catalog_item.dart';
import 'package:healthylife/features/recommendations/domain/entities/meal_catalog_item.dart';

void main() {
  const forbiddenPhrases = [
    'giảm cân nhanh',
    'giam can nhanh',
    'điều trị',
    'dieu tri',
    'chữa bệnh',
    'chua benh',
    'thâm hụt calo',
    'tham hut calo',
  ];

  group('Danh mục mẫu môn tập và món ăn (Tiêu chí 1)', () {
    test('mọi bài tập mẫu đều có thời lượng, ngân sách và nguồn kiểm duyệt đầy đủ', () {
      expect(SampleCatalogFixture.sampleExercises.length, greaterThanOrEqualTo(10));

      final slugs = <String>{};
      for (final item in SampleCatalogFixture.sampleExercises) {
        expect(item.id, isNotEmpty);
        expect(slugs.add(item.slug), isTrue, reason: 'Trùng slug: ${item.slug}');
        expect(item.name, isNotEmpty);
        expect(item.durationMinutes, greaterThan(0));
        expect(
          ['free', 'low', 'medium', 'high'],
          contains(item.budgetTier),
        );
        expect(item.estimatedCostVnd, greaterThanOrEqualTo(0));
        expect(item.hasVerifiedSource, isTrue);

        final text = '${item.name} ${item.description}'.toLowerCase();
        for (final phrase in forbiddenPhrases) {
          expect(text, isNot(contains(phrase)));
        }
      }
    });

    test('mọi món ăn mẫu đều có nguyên liệu rõ ràng, ngân sách, thời gian và nguồn kiểm duyệt', () {
      expect(SampleCatalogFixture.sampleMeals.length, greaterThanOrEqualTo(10));

      final slugs = <String>{};
      for (final item in SampleCatalogFixture.sampleMeals) {
        expect(item.id, isNotEmpty);
        expect(slugs.add(item.slug), isTrue, reason: 'Trùng slug: ${item.slug}');
        expect(item.name, isNotEmpty);
        expect(item.hasClearIngredients, isTrue);
        expect(item.prepTimeMinutes, greaterThan(0));
        expect(item.estimatedCostVnd, greaterThan(0));
        expect(['low', 'medium', 'high'], contains(item.budgetTier));
        expect(item.hasVerifiedSource, isTrue);

        final text =
            '${item.name} ${item.description} ${item.notes ?? ''}'.toLowerCase();
        for (final phrase in forbiddenPhrases) {
          expect(text, isNot(contains(phrase)));
        }
      }
    });

    test('File seed JSON khớp dữ liệu và parse được qua ExerciseCatalogItem/MealCatalogItem', () {
      final seedFile = File('supabase/seed/catalog_seed.json');
      expect(seedFile.existsSync(), isTrue);

      final decoded =
          jsonDecode(seedFile.readAsStringSync()) as Map<String, dynamic>;
      final rawExercises = decoded['exercise_catalog'] as List<dynamic>;
      final rawMeals = decoded['meal_catalog'] as List<dynamic>;
      final sql = File('supabase/seed/20261121_initial_catalog.sql')
          .readAsStringSync();
      final sqlRows = RegExp(r'\$catalog\$(.*?)\$catalog\$', dotAll: true)
          .allMatches(sql)
          .map((match) => jsonDecode(match.group(1)!))
          .toList();
      expect(sqlRows, [rawExercises, rawMeals]);

      final exercises = rawExercises
          .map((e) => ExerciseCatalogItem.fromMap(e as Map<String, dynamic>))
          .toList();
      final meals = rawMeals
          .map((e) => MealCatalogItem.fromMap(e as Map<String, dynamic>))
          .toList();

      expect(exercises.length, SampleCatalogFixture.sampleExercises.length);
      expect(meals.length, SampleCatalogFixture.sampleMeals.length);
      expect(
        exercises.map((e) => e.slug).toList(),
        SampleCatalogFixture.sampleExercises.map((e) => e.slug).toList(),
      );
      expect(
        meals.map((e) => e.slug).toList(),
        SampleCatalogFixture.sampleMeals.map((e) => e.slug).toList(),
      );
      expect(exercises.every((e) => e.hasVerifiedSource), isTrue);
      expect(meals.every((e) => e.hasVerifiedSource && e.hasClearIngredients), isTrue);
      expect(
        exercises.map((item) => item.toMap()),
        SampleCatalogFixture.sampleExercises.map((item) => item.toMap()),
      );
      expect(
        meals.map((item) => item.toMap()),
        SampleCatalogFixture.sampleMeals.map((item) => item.toMap()),
      );
    });

    test('FixtureCatalogRepository trả về đúng danh mục mẫu và hỗ trợ round-trip map', () async {
      const repo = FixtureCatalogRepository();
      final exercises = await repo.getExerciseCatalog();
      final meals = await repo.getMealCatalog();

      expect(exercises.length, SampleCatalogFixture.sampleExercises.length);
      expect(meals.length, SampleCatalogFixture.sampleMeals.length);

      final roundTripExercise = ExerciseCatalogItem.fromMap(exercises.first.toMap());
      expect(roundTripExercise.slug, exercises.first.slug);
      expect(roundTripExercise.source.url, exercises.first.source.url);

      final roundTripMeal = MealCatalogItem.fromMap(meals.first.toMap());
      expect(roundTripMeal.slug, meals.first.slug);
      expect(roundTripMeal.allergens, meals.first.allergens);
    });
  });
}
