import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/nutrition/data/repositories/in_memory_meal_log_repository.dart';
import 'package:healthylife/features/nutrition/data/repositories/mock_meal_photo_services.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_label_suggestion.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_attachment.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_policy.dart';
import 'package:healthylife/features/nutrition/domain/repositories/optional_meal_label_suggester.dart';
import 'package:healthylife/features/nutrition/domain/usecases/meal_nutrition_usecase.dart';
import 'package:healthylife/features/nutrition/presentation/widgets/meal_log_composer_view.dart';
import 'package:healthylife/features/recommendations/data/fixtures/sample_profile_fixtures.dart';
import 'package:healthylife/features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'package:healthylife/features/recommendations/domain/usecases/get_recommendations_usecase.dart';

class _MockOptionalAiSuggester implements OptionalMealLabelSuggester {
  int callCount = 0;
  final List<String> labelsToReturn;
  final bool shouldThrow;

  _MockOptionalAiSuggester({
    this.labelsToReturn = const [],
    this.shouldThrow = false,
  });

  @override
  Future<List<String>> suggestMealLabelsFromPhoto({
    required String ownerUid,
    required PreparedMealPhoto photo,
  }) async {
    callCount++;
    if (shouldThrow) {
      throw Exception('AI proxy timeout');
    }
    return labelsToReturn;
  }
}

void main() {
  Future<PreparedMealPhoto> buildPreparedSamplePhoto(
    MealNutritionUseCase useCase,
  ) async {
    final selected = SelectedMealPhoto(
      source: MealPhotoSource.camera,
      fileName: 'meal.jpg',
      mimeType: 'image/jpeg',
      bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
    );
    return useCase.preparePhoto(selected);
  }

  group('Ranh giới an toàn ảnh & AI mở rộng (Issue #11 - Tiêu chí 4)', () {
    test('bản cốt lõi không cần AI vẫn lưu nhật ký bình thường và không suy ra calo/dị nguyên', () async {
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: MockMealPhotoPicker(),
        photoStorage: InMemoryPrivateMealPhotoStorage(),
      );

      final prepared = await buildPreparedSamplePhoto(useCase);
      final aiResult = await useCase.requestOptionalPhotoLabelSuggestions(
        ownerUid: 'uid-dai',
        photo: prepared,
        aiConsentGranted: true,
      );

      expect(aiResult.status, MealLabelSuggestionStatus.disabled);
      expect(aiResult.hasCandidates, isFalse);
      expect(aiResult.infersCaloriesFromPhoto, isFalse);
      expect(aiResult.infersAllergenSafetyFromPhoto, isFalse);
      expect(aiResult.requiresUserConfirmation, isTrue);

      final saved = await useCase.saveMealLogResilient(
        ownerUid: 'uid-dai',
        confirmedMealName: 'Cơm gạo lứt ức gà',
        preparedPhoto: prepared,
      );
      final payload = saved.log.toSupabasePayload();
      expect(payload.containsKey('calories'), isFalse);
      expect(payload.containsKey('allergen_free'), isFalse);
      expect(saved.log.userConfirmedName, isTrue);
    });

    test('không gọi AI mở rộng khi người dùng chưa cấp đồng ý riêng', () async {
      final ai = _MockOptionalAiSuggester(labelsToReturn: ['Phở gà']);
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: MockMealPhotoPicker(),
        photoStorage: InMemoryPrivateMealPhotoStorage(),
        optionalLabelSuggester: ai,
      );

      final prepared = await buildPreparedSamplePhoto(useCase);
      final aiResult = await useCase.requestOptionalPhotoLabelSuggestions(
        ownerUid: 'uid-dai',
        photo: prepared,
        aiConsentGranted: false,
      );

      expect(aiResult.status, MealLabelSuggestionStatus.consentRequired);
      expect(ai.callCount, 0);
      expect(aiResult.candidateLabels, isEmpty);
    });

    test('AI mở rộng lỗi sẽ fallback về nhập tay và không chặn luồng lưu cốt lõi', () async {
      final ai = _MockOptionalAiSuggester(shouldThrow: true);
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: MockMealPhotoPicker(),
        photoStorage: InMemoryPrivateMealPhotoStorage(),
        optionalLabelSuggester: ai,
      );

      final prepared = await buildPreparedSamplePhoto(useCase);
      final aiResult = await useCase.requestOptionalPhotoLabelSuggestions(
        ownerUid: 'uid-dai',
        photo: prepared,
        aiConsentGranted: true,
      );

      expect(aiResult.status, MealLabelSuggestionStatus.fallbackToManual);
      expect(aiResult.hasCandidates, isFalse);

      // Luồng cốt lõi vẫn lưu nhật ký bình thường
      final saved = await useCase.saveMealLogResilient(
        ownerUid: 'uid-dai',
        confirmedMealName: 'Bún chả tự xác nhận',
        preparedPhoto: prepared,
      );
      expect(saved.log.mealName, 'Bún chả tự xác nhận');
      expect(saved.log.hasPhoto, isTrue);
    });

    test('lọc bỏ mọi nhãn suy đoán calo hoặc khẳng định an toàn dị nguyên từ AI', () async {
      final ai = _MockOptionalAiSuggester(
        labelsToReturn: [
          'Phở gà nạc',
          'Phở gà khoảng 450 kcal',
          'Món không chứa dị nguyên đậu phộng',
          'Allergen-free salad',
          'Cơm rau luộc',
        ],
      );
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: MockMealPhotoPicker(),
        photoStorage: InMemoryPrivateMealPhotoStorage(),
        optionalLabelSuggester: ai,
      );

      final prepared = await buildPreparedSamplePhoto(useCase);
      final aiResult = await useCase.requestOptionalPhotoLabelSuggestions(
        ownerUid: 'uid-dai',
        photo: prepared,
        aiConsentGranted: true,
      );

      expect(aiResult.status, MealLabelSuggestionStatus.suggestedForConfirmation);
      expect(aiResult.candidateLabels, ['Phở gà nạc', 'Cơm rau luộc']);
      expect(aiResult.infersCaloriesFromPhoto, isFalse);
      expect(aiResult.infersAllergenSafetyFromPhoto, isFalse);
      expect(aiResult.requiresUserConfirmation, isTrue);
    });

    testWidgets('MealLogComposerView hiển thị cảnh báo an toàn ảnh và không tự ghi đè tên món khi AI gợi ý nhãn', (
      tester,
    ) async {
      final ai = _MockOptionalAiSuggester(labelsToReturn: ['Bún bò tự chọn']);
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: MockMealPhotoPicker(),
        photoStorage: InMemoryPrivateMealPhotoStorage(),
        optionalLabelSuggester: ai,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealLogComposerView(
              ownerUid: 'uid-dai',
              profile: SampleProfileFixtures.officeWorkerWalking,
              useCase: useCase,
              aiPhotoLabelConsentGranted: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('không suy ra lượng calo hay khẳng định món ăn không chứa dị nguyên'),
        findsOneWidget,
      );

      final mealNameField = find.byType(TextFormField).first;
      final beforePhotoName =
          tester.widget<TextFormField>(mealNameField).controller!.text;

      await tester.ensureVisible(find.text('Chụp ảnh bữa ăn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chụp ảnh bữa ăn'));
      await tester.pumpAndSettle();

      // Không tự ghi đè tên món trước khi người dùng chủ động bấm chip xác nhận
      expect(
        tester.widget<TextFormField>(mealNameField).controller!.text,
        beforePhotoName,
      );
      await tester.ensureVisible(find.text('Bún bò tự chọn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bún bò tự chọn'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextFormField>(mealNameField).controller!.text,
        'Bún bò tự chọn',
      );
    });
  });
}
