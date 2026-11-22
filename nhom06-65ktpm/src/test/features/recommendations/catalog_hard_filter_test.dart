import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/recommendations/data/fixtures/sample_catalog_fixture.dart';
import 'package:healthylife/features/recommendations/domain/entities/hard_filter_result.dart';
import 'package:healthylife/features/recommendations/domain/entities/meal_catalog_item.dart';
import 'package:healthylife/features/recommendations/domain/entities/recommendation_profile.dart';
import 'package:healthylife/features/recommendations/domain/services/catalog_hard_filter.dart';

void main() {
  const filter = CatalogHardFilter();

  RecommendationProfile validAdultProfile({
    bool isAdultConfirmed = true,
    bool requiresProfessionalGuidance = false,
    String? timezone = 'Asia/Ho_Chi_Minh',
    String? goal = 'regular_activity',
    int? availableMinutesPerSession = 30,
    int? sessionsPerWeek = 3,
    String experienceLevel = 'intermediate',
    List<String> availableEquipment = const ['mat'],
    List<String> movementLimitations = const [],
    String preferredEnvironment = 'any',
    int? maxExerciseBudgetVnd,
    List<String> dislikedExerciseCategories = const [],
    bool allergiesConfirmed = true,
    List<String> allergies = const [],
    List<String> avoidedIngredients = const [],
    bool canCook = true,
    int? maxMealPrepMinutes,
    int? maxMealBudgetVnd,
    List<String> requiredDietTags = const [],
  }) {
    return RecommendationProfile(
      isAdultConfirmed: isAdultConfirmed,
      requiresProfessionalGuidance: requiresProfessionalGuidance,
      timezone: timezone,
      goal: goal,
      availableMinutesPerSession: availableMinutesPerSession,
      sessionsPerWeek: sessionsPerWeek,
      experienceLevel: experienceLevel,
      availableEquipment: availableEquipment,
      movementLimitations: movementLimitations,
      preferredEnvironment: preferredEnvironment,
      maxExerciseBudgetVnd: maxExerciseBudgetVnd,
      dislikedExerciseCategories: dislikedExerciseCategories,
      allergiesConfirmed: allergiesConfirmed,
      allergies: allergies,
      avoidedIngredients: avoidedIngredients,
      canCook: canCook,
      maxMealPrepMinutes: maxMealPrepMinutes,
      maxMealBudgetVnd: maxMealBudgetVnd,
      requiredDietTags: requiredDietTags,
    );
  }

  group('Kiểm tra đầu vào bắt buộc trước gợi ý (Tiêu chí 2)', () {
    test('chặn gợi ý khi chưa xác nhận đủ 18 tuổi', () {
      final result = filter.filterExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: validAdultProfile(isAdultConfirmed: false),
      );

      expect(result.status, RecommendationGateStatus.underageBlocked);
      expect(result.eligibleItems, isEmpty);
      expect(result.missingFields, contains('isAdultConfirmed'));
    });

    test('chặn gợi ý tự động khi người dùng tự khai báo cần tư vấn chuyên môn', () {
      final result = filter.filterMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: validAdultProfile(requiresProfessionalGuidance: true),
      );

      expect(
        result.status,
        RecommendationGateStatus.professionalGuidanceRequired,
      );
      expect(result.eligibleItems, isEmpty);
    });

    test('chặn mục tiêu điều trị hoặc giảm cân nhanh', () {
      final treatmentResult = filter.filterMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: validAdultProfile(goal: 'medical_treatment'),
      );
      final rapidLossResult = filter.filterExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: validAdultProfile(goal: 'giảm cân nhanh'),
      );

      expect(treatmentResult.status, RecommendationGateStatus.unsafeGoalBlocked);
      expect(treatmentResult.eligibleItems, isEmpty);
      expect(rapidLossResult.status, RecommendationGateStatus.unsafeGoalBlocked);
      expect(rapidLossResult.eligibleItems, isEmpty);
    });

    test('trả missingRequiredInput khi thiếu múi giờ, mục tiêu hoặc thời lượng bất hợp lý', () {
      final result = filter.filterExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: validAdultProfile(
          timezone: '',
          goal: null,
          availableMinutesPerSession: 0,
          sessionsPerWeek: 20,
        ),
      );

      expect(result.status, RecommendationGateStatus.missingRequiredInput);
      expect(result.eligibleItems, isEmpty);
      expect(
        result.missingFields,
        containsAll([
          'timezone',
          'goal',
          'availableMinutesPerSession',
          'sessionsPerWeek',
        ]),
      );
    });

    test('chưa xác nhận dị ứng thì chưa bật gợi ý món ăn', () {
      final result = filter.filterMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: validAdultProfile(allergiesConfirmed: false),
      );

      expect(result.status, RecommendationGateStatus.allergiesUnconfirmed);
      expect(result.eligibleItems, isEmpty);
      expect(result.missingFields, contains('allergiesConfirmed'));
    });
  });

  group('Lọc cứng môn tập theo giới hạn, thiết bị và điều kiện (Tiêu chí 2)', () {
    test('loại bài tập chưa kiểm duyệt, thiếu thiết bị và vi phạm giới hạn vận động', () {
      final combinedCatalog = [
        ...SampleCatalogFixture.sampleExercises,
        ...SampleCatalogFixture.edgeCaseExercisesForTesting,
      ];

      final result = filter.filterExercises(
        catalog: combinedCatalog,
        profile: validAdultProfile(
          availableEquipment: const ['mat'],
          movementLimitations: const ['knee_impact'],
          availableMinutesPerSession: 30,
          experienceLevel: 'intermediate',
        ),
      );

      expect(result.status, RecommendationGateStatus.ready);
      final slugs = result.eligibleItems.map((e) => e.slug).toSet();

      expect(slugs, containsAll(['walking', 'stretching', 'desk-mobility-break', 'yoga-mobility']));
      expect(slugs, isNot(contains('bodyweight-workout'))); // knee_impact
      expect(slugs, isNot(contains('jump-rope'))); // knee_impact + thiếu jump_rope
      expect(slugs, isNot(contains('jogging-easy'))); // knee_impact + thiếu running_shoes
      expect(slugs, isNot(contains('dumbbell-full-body'))); // thiếu dumbbells + 35 phút
      expect(slugs, isNot(contains('cycling-steady'))); // thiếu bicycle + 40 phút
      expect(slugs, isNot(contains('unverified-extreme-routine'))); // chưa kiểm duyệt
    });

    test('không nới ràng buộc khi không có bài tập nào khớp thời gian hoặc môi trường', () {
      final result = filter.filterExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: validAdultProfile(
          availableEquipment: const [],
          preferredEnvironment: 'outdoor',
          availableMinutesPerSession: 5,
        ),
      );

      expect(result.status, RecommendationGateStatus.ready);
      expect(result.eligibleItems, isEmpty);
      expect(result.message, isNotNull);
    });
  });

  group('Lọc cứng món ăn theo dị nguyên và độ rõ thành phần (Tiêu chí 2)', () {
    test('loại món không rõ thành phần, món chưa kiểm duyệt và món chứa dị nguyên/nguyên liệu tránh', () {
      const unknownMarkerMeal = MealCatalogItem(
        id: 'meal-unknown-marker',
        slug: 'unknown-ingredient-meal',
        name: 'Món có thành phần chưa rõ',
        mealType: 'lunch',
        ingredients: ['gao_te', 'khong_ro'],
        allergens: [],
        dietTags: ['balanced'],
        requiresCooking: false,
        budgetTier: 'low',
        estimatedCostVnd: 25000,
        prepTimeMinutes: 10,
        isVerified: true,
        source: SampleCatalogFixture.whoHealthyDietSource,
        description: 'Món kiểm thử chứa từ khóa không rõ nguyên liệu.',
      );

      final combinedCatalog = [
        ...SampleCatalogFixture.sampleMeals,
        ...SampleCatalogFixture.edgeCaseMealsForTesting,
        unknownMarkerMeal,
      ];

      final result = filter.filterMeals(
        catalog: combinedCatalog,
        profile: validAdultProfile(
          allergiesConfirmed: true,
          allergies: const ['dairy', 'peanut', 'seafood'],
          avoidedIngredients: const ['trung_ga'],
        ),
      );

      expect(result.status, RecommendationGateStatus.ready);
      final slugs = result.eligibleItems.map((m) => m.slug).toSet();

      expect(slugs, isNot(contains('mystery-combo-box'))); // rỗng thành phần
      expect(slugs, isNot(contains('unknown-ingredient-meal'))); // chứa khong_ro
      expect(slugs, isNot(contains('unverified-homemade-dish'))); // chưa kiểm duyệt
      expect(slugs, isNot(contains('oat-yogurt-fruit'))); // dairy
      expect(slugs, isNot(contains('peanut-banana-wholewheat-toast'))); // peanut
      expect(slugs, isNot(contains('shrimp-fresh-spring-rolls'))); // seafood
      expect(slugs, isNot(contains('salmon-brown-rice-bowl'))); // seafood
      expect(slugs, isNot(contains('rice-vegetable-egg'))); // avoidedIngredient trung_ga
      expect(slugs, containsAll(['lentil-soup', 'tofu-mushroom-rice', 'steamed-corn-fruit-snack']));
    });

    test('trả rỗng khi không có món đáp ứng đồng thời không nấu và ngân sách quá thấp', () {
      final result = filter.filterMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: validAdultProfile(
          allergiesConfirmed: true,
          canCook: false,
          maxMealBudgetVnd: 10000,
        ),
      );

      expect(result.status, RecommendationGateStatus.ready);
      expect(result.eligibleItems, isEmpty);
      expect(result.message, isNotNull);
    });
  });
}
