import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/recommendations/data/fixtures/sample_catalog_fixture.dart';
import 'package:healthylife/features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'package:healthylife/features/recommendations/domain/entities/hard_filter_result.dart';
import 'package:healthylife/features/recommendations/domain/entities/recommendation_profile.dart';
import 'package:healthylife/features/recommendations/domain/services/recommendation_engine.dart';
import 'package:healthylife/features/recommendations/domain/usecases/get_recommendations_usecase.dart';

void main() {
  const engine = RecommendationEngine();

  group('Xếp hạng và giải thích môn tập (Tiêu chí 3)', () {
    test('ưu tiên Đi bộ ngoài trời cho người thích ngoài trời, không có thiết bị và rảnh 20 phút', () {
      const profile = RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'regular_activity',
        availableMinutesPerSession: 20,
        sessionsPerWeek: 3,
        experienceLevel: 'beginner',
        availableEquipment: [],
        preferredEnvironment: 'outdoor',
        preferredExerciseCategories: ['walking'],
        preferredExerciseTags: ['outdoor', 'no_equipment'],
        allergiesConfirmed: true,
      );

      final result = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: profile,
      );

      expect(result.status, RecommendationGateStatus.ready);
      expect(result.hasRecommendations, isTrue);
      expect(result.primaryRecommendation!.item.slug, 'walking');
      expect(result.primaryRecommendation!.explanation, contains('ngoài trời'));
      expect(
        result.primaryRecommendation!.explanation,
        contains('không cần thiết bị'),
      );
      expect(result.primaryRecommendation!.explanation, contains('20 phút'));
      expect(result.primaryRecommendation!.conditionsSummary, contains('WHO'));
    });

    test('phản hồi thích/không phù hợp và sự đa dạng làm thay đổi thứ hạng gợi ý', () {
      const baseProfile = RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'maintain_habit',
        availableMinutesPerSession: 25,
        sessionsPerWeek: 4,
        experienceLevel: 'beginner',
        availableEquipment: ['mat'],
        preferredEnvironment: 'indoor',
        allergiesConfirmed: true,
        likedSlugs: ['yoga-mobility'],
        dislikedSlugs: ['stretching'],
      );

      final result = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: baseProfile,
        recentSlugs: const ['desk-mobility-break'],
        maxResults: 2,
      );

      expect(result.recommendations.length, 2);
      expect(result.recommendations.first.item.slug, 'yoga-mobility');
      expect(
        result.recommendations.first.explanation,
        contains('yêu thích trước đây'),
      );
      expect(result.alternatives, isNotEmpty);
      expect(result.alternatives.last.item.slug, 'stretching');
    });

    test('trả danh sách rỗng và không nới ràng buộc khi không có bài tập hợp lệ', () {
      const strictProfile = RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'regular_activity',
        availableMinutesPerSession: 5,
        sessionsPerWeek: 3,
        experienceLevel: 'beginner',
        availableEquipment: [],
        preferredEnvironment: 'outdoor',
        preferredExerciseCategories: ['walking'],
        allergiesConfirmed: true,
      );

      final result = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: strictProfile,
      );

      expect(result.status, RecommendationGateStatus.ready);
      expect(result.isEmpty, isTrue);
      expect(result.alternatives, isEmpty);
      expect(result.emptyReason, isNotNull);
      expect(result.excludedCount, SampleCatalogFixture.sampleExercises.length);
    });
  });

  group('Xếp hạng và giải thích món ăn (Tiêu chí 3)', () {
    test('xếp hạng ưu tiên theo sở thích, thời gian chuẩn bị, ngân sách và cung cấp lựa chọn thay thế', () {
      const profile = RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'maintain_habit',
        availableMinutesPerSession: 20,
        sessionsPerWeek: 3,
        allergiesConfirmed: true,
        allergies: ['peanut', 'seafood'],
        canCook: true,
        maxMealPrepMinutes: 25,
        maxMealBudgetVnd: 40000,
        preferredDietTags: ['vegetarian', 'quick_prep'],
      );

      final result = engine.recommendMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: profile,
        maxResults: 2,
      );

      expect(result.status, RecommendationGateStatus.ready);
      expect(result.recommendations.length, 2);
      expect(result.alternatives, isNotEmpty);

      final topMeal = result.primaryRecommendation!;
      expect(topMeal.item.allergens, isNot(contains('peanut')));
      expect(topMeal.item.allergens, isNot(contains('seafood')));
      expect(topMeal.item.estimatedCostVnd, lessThanOrEqualTo(40000));
      expect(topMeal.item.prepTimeMinutes, lessThanOrEqualTo(25));
      expect(topMeal.explanation, contains('không chứa dị nguyên'));
      expect(topMeal.explanation, contains('VND'));
      expect(topMeal.conditionsSummary, contains('WHO'));
    });

    test('trả rỗng và không nới ràng buộc khi dị ứng loại hết món ăn', () {
      const profile = RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'maintain_habit',
        availableMinutesPerSession: 20,
        sessionsPerWeek: 3,
        allergiesConfirmed: true,
        allergies: ['dairy', 'gluten', 'egg', 'soy', 'seafood', 'shellfish'],
        canCook: false,
        maxMealBudgetVnd: 15000,
      );

      final result = engine.recommendMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: profile,
      );

      expect(result.status, RecommendationGateStatus.ready);
      expect(result.isEmpty, isTrue);
      expect(result.alternatives, isEmpty);
      expect(result.emptyReason, contains('không nới lỏng'));
    });
  });

  group('GetRecommendationsUseCase với FixtureCatalogRepository (Tiêu chí 3)', () {
    test('trả về gợi ý môn tập và món ăn xuyên suốt qua repository fixture', () async {
      const useCase = GetRecommendationsUseCase(
        repository: FixtureCatalogRepository(),
      );
      const profile = RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'regular_activity',
        availableMinutesPerSession: 25,
        sessionsPerWeek: 3,
        experienceLevel: 'beginner',
        availableEquipment: ['mat'],
        preferredEnvironment: 'any',
        allergiesConfirmed: true,
        allergies: ['dairy'],
        maxMealBudgetVnd: 45000,
      );

      final exercises = await useCase.getExerciseRecommendations(
        profile: profile,
      );
      final meals = await useCase.getMealRecommendations(
        profile: profile,
        mealType: 'dinner',
      );

      expect(exercises.hasRecommendations, isTrue);
      expect(meals.hasRecommendations, isTrue);
      expect(
        meals.recommendations.every((r) => r.item.mealType == 'dinner'),
        isTrue,
      );
      expect(
        meals.recommendations.every((r) => !r.item.allergens.contains('dairy')),
        isTrue,
      );
    });
  });
}
