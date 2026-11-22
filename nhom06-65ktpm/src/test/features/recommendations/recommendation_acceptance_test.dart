import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/recommendations/data/fixtures/sample_catalog_fixture.dart';
import 'package:healthylife/features/recommendations/data/fixtures/sample_profile_fixtures.dart';
import 'package:healthylife/features/recommendations/domain/entities/exercise_catalog_item.dart';
import 'package:healthylife/features/recommendations/domain/entities/hard_filter_result.dart';
import 'package:healthylife/features/recommendations/domain/entities/meal_catalog_item.dart';
import 'package:healthylife/features/recommendations/domain/services/recommendation_engine.dart';
import 'package:healthylife/features/recommendations/presentation/widgets/recommendation_preview_view.dart';

void main() {
  const engine = RecommendationEngine();

  group('Kiểm thử nghiệm thu đầu vào thiếu và điều kiện bắt buộc (Tiêu chí 4)', () {
    test('đầu vào thiếu múi giờ/mục tiêu/thời lượng trả missingRequiredInput và không gợi ý', () {
      final exResult = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: SampleProfileFixtures.missingRequiredInputs,
      );
      final mealResult = engine.recommendMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: SampleProfileFixtures.missingRequiredInputs,
      );

      expect(exResult.status, RecommendationGateStatus.missingRequiredInput);
      expect(exResult.isEmpty, isTrue);
      expect(
        exResult.missingFields,
        containsAll(['timezone', 'goal', 'availableMinutesPerSession', 'sessionsPerWeek']),
      );
      expect(mealResult.status, RecommendationGateStatus.missingRequiredInput);
      expect(mealResult.isEmpty, isTrue);
    });

    test('chưa xác nhận đủ 18 tuổi chặn cả môn tập và món ăn', () {
      final exResult = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: SampleProfileFixtures.underageProfile,
      );
      final mealResult = engine.recommendMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: SampleProfileFixtures.underageProfile,
      );

      expect(exResult.status, RecommendationGateStatus.underageBlocked);
      expect(exResult.isEmpty, isTrue);
      expect(mealResult.status, RecommendationGateStatus.underageBlocked);
      expect(mealResult.isEmpty, isTrue);
    });

    test('chưa xác nhận dị ứng chỉ khóa gợi ý món ăn nhưng vẫn gợi ý môn tập bình thường', () {
      final exResult = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: SampleProfileFixtures.unconfirmedAllergies,
      );
      final mealResult = engine.recommendMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: SampleProfileFixtures.unconfirmedAllergies,
      );

      expect(exResult.status, RecommendationGateStatus.ready);
      expect(exResult.hasRecommendations, isTrue);
      expect(mealResult.status, RecommendationGateStatus.allergiesUnconfirmed);
      expect(mealResult.isEmpty, isTrue);
    });
  });

  group('Kiểm thử nghiệm thu dị ứng và thiếu thiết bị (Tiêu chí 4)', () {
    test('hồ sơ sinh viên không bếp, ngân sách 30k và dị ứng đậu phộng chỉ nhận món an toàn phù hợp', () {
      final mealResult = engine.recommendMeals(
        catalog: [
          ...SampleCatalogFixture.sampleMeals,
          ...SampleCatalogFixture.edgeCaseMealsForTesting,
        ],
        profile: SampleProfileFixtures.studentLowBudgetNoCook,
      );

      expect(mealResult.status, RecommendationGateStatus.ready);
      expect(mealResult.hasRecommendations, isTrue);
      for (final rec in [
        ...mealResult.recommendations,
        ...mealResult.alternatives,
      ]) {
        expect(rec.item.hasVerifiedSource, isTrue);
        expect(rec.item.hasClearIngredients, isTrue);
        expect(rec.item.requiresCooking, isFalse);
        expect(rec.item.estimatedCostVnd, lessThanOrEqualTo(30000));
        expect(rec.item.allergens, isNot(contains('peanut')));
      }
    });

    test('hồ sơ không có thiết bị tuyệt đối không nhận bài tập yêu cầu dụng cụ', () {
      final exResult = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: SampleProfileFixtures.officeWorkerWalking,
      );

      expect(exResult.hasRecommendations, isTrue);
      for (final rec in [
        ...exResult.recommendations,
        ...exResult.alternatives,
      ]) {
        expect(rec.item.equipmentNeeded, isEmpty);
        expect(rec.item.durationMinutes, lessThanOrEqualTo(20));
      }
    });

    test('người làm ca đêm giới hạn knee_impact và dị ứng dairy/egg không nhận ứng viên vi phạm', () {
      final exResult = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: SampleProfileFixtures.shiftWorkerNight,
      );
      final mealResult = engine.recommendMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: SampleProfileFixtures.shiftWorkerNight,
      );

      expect(exResult.hasRecommendations, isTrue);
      for (final rec in [
        ...exResult.recommendations,
        ...exResult.alternatives,
      ]) {
        expect(rec.item.contraindicatedLimitations, isNot(contains('knee_impact')));
      }

      expect(mealResult.hasRecommendations, isTrue);
      for (final rec in [
        ...mealResult.recommendations,
        ...mealResult.alternatives,
      ]) {
        expect(rec.item.allergens, isNot(contains('dairy')));
        expect(rec.item.allergens, isNot(contains('egg')));
      }
    });

    test('không còn ứng viên hợp lệ do thiếu thiết bị hoặc đa dị ứng đều trả rỗng không nới ràng buộc', () {
      final exResult = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: SampleProfileFixtures.noEquipmentStrictProfile,
      );
      final mealResult = engine.recommendMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: SampleProfileFixtures.multiAllergyNoMatchProfile,
      );

      expect(exResult.isEmpty, isTrue);
      expect(exResult.alternatives, isEmpty);
      expect(mealResult.isEmpty, isTrue);
      expect(mealResult.alternatives, isEmpty);
    });
  });

  group('Kiểm thử nghiệm thu an toàn: không đề xuất điều trị hoặc giảm cân nhanh (Tiêu chí 4)', () {
    test('chặn hồ sơ cần chuyên gia, mục tiêu điều trị hoặc mục tiêu giảm cân nhanh', () {
      final guidanceRes = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: SampleProfileFixtures.professionalGuidanceProfile,
      );
      final medicalRes = engine.recommendMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: SampleProfileFixtures.medicalTreatmentGoalProfile,
      );
      final rapidLossRes = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: SampleProfileFixtures.rapidWeightLossGoalProfile,
      );

      expect(
        guidanceRes.status,
        RecommendationGateStatus.professionalGuidanceRequired,
      );
      expect(guidanceRes.isEmpty, isTrue);
      expect(medicalRes.status, RecommendationGateStatus.unsafeGoalBlocked);
      expect(medicalRes.isEmpty, isTrue);
      expect(rapidLossRes.status, RecommendationGateStatus.unsafeGoalBlocked);
      expect(rapidLossRes.isEmpty, isTrue);
    });

    test('loại bỏ item trong danh mục nếu chứa nội dung điều trị hoặc giảm cân nhanh', () {
      const unsafeExercise = ExerciseCatalogItem(
        id: 'ex-unsafe',
        slug: 'rapid-fat-burn',
        name: 'Bài tập giảm cân nhanh trong 7 ngày',
        category: 'cardio',
        durationMinutes: 15,
        equipmentNeeded: [],
        experienceLevel: 'beginner',
        environment: 'both',
        budgetTier: 'free',
        estimatedCostVnd: 0,
        contraindicatedLimitations: [],
        tags: ['outdoor'],
        isVerified: true,
        source: SampleCatalogFixture.whoPhysicalActivitySource,
        description: 'Ép cường độ cao để giảm cân nhanh.',
      );

      const unsafeMeal = MealCatalogItem(
        id: 'meal-unsafe',
        slug: 'clinical-cure-soup',
        name: 'Súp thực đơn điều trị bệnh dạ dày',
        mealType: 'dinner',
        ingredients: ['bi_do', 'ca_rot'],
        allergens: [],
        dietTags: ['balanced'],
        requiresCooking: true,
        budgetTier: 'low',
        estimatedCostVnd: 25000,
        prepTimeMinutes: 15,
        isVerified: true,
        source: SampleCatalogFixture.whoHealthyDietSource,
        description: 'Thực đơn điều trị chuyên biệt.',
      );

      final exResult = engine.recommendExercises(
        catalog: [unsafeExercise, ...SampleCatalogFixture.sampleExercises],
        profile: SampleProfileFixtures.officeWorkerWalking,
      );
      final mealResult = engine.recommendMeals(
        catalog: [unsafeMeal, ...SampleCatalogFixture.sampleMeals],
        profile: SampleProfileFixtures.officeWorkerWalking,
      );

      expect(
        [...exResult.recommendations, ...exResult.alternatives]
            .any((r) => r.item.slug == 'rapid-fat-burn'),
        isFalse,
      );
      expect(
        [...mealResult.recommendations, ...mealResult.alternatives]
            .any((r) => r.item.slug == 'clinical-cure-soup'),
        isFalse,
      );
    });
  });

  group('Widget test giao diện RecommendationPreviewView (Tiêu chí 4)', () {
    testWidgets('hiển thị gợi ý có giải thích và thông báo khi món ăn chưa xác nhận dị ứng', (
      tester,
    ) async {
      final exResult = engine.recommendExercises(
        catalog: SampleCatalogFixture.sampleExercises,
        profile: SampleProfileFixtures.unconfirmedAllergies,
      );
      final mealResult = engine.recommendMeals(
        catalog: SampleCatalogFixture.sampleMeals,
        profile: SampleProfileFixtures.unconfirmedAllergies,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecommendationPreviewView(
              exerciseResult: exResult,
              mealResult: mealResult,
            ),
          ),
        ),
      );

      expect(find.text('Gợi ý môn tập'), findsOneWidget);
      expect(find.textContaining('quy tắc sản phẩm'), findsOneWidget);
      expect(find.textContaining('Gợi ý "'), findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Gợi ý món ăn'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Gợi ý món ăn'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Chưa xác nhận tình trạng dị ứng'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.textContaining('Chưa xác nhận tình trạng dị ứng'), findsOneWidget);
    });
  });
}
