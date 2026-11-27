import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/nutrition/data/repositories/in_memory_meal_log_repository.dart';
import 'package:healthylife/features/nutrition/data/repositories/mock_meal_photo_services.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_attachment.dart';
import 'package:healthylife/features/nutrition/domain/usecases/meal_nutrition_usecase.dart';
import 'package:healthylife/features/nutrition/presentation/widgets/meal_log_composer_view.dart';
import 'package:healthylife/features/recommendations/data/fixtures/sample_profile_fixtures.dart';
import 'package:healthylife/features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'package:healthylife/features/recommendations/domain/usecases/get_recommendations_usecase.dart';

void main() {
  late InMemoryMealLogRepository mealLogRepo;
  late InMemoryPrivateMealPhotoStorage photoStorage;
  late MockMealPhotoPicker photoPicker;
  late MealNutritionUseCase useCase;

  setUp(() {
    mealLogRepo = InMemoryMealLogRepository();
    photoStorage = InMemoryPrivateMealPhotoStorage();
    photoPicker = MockMealPhotoPicker();
    useCase = MealNutritionUseCase(
      recommendationsUseCase: const GetRecommendationsUseCase(
        repository: FixtureCatalogRepository(),
      ),
      mealLogRepository: mealLogRepo,
      photoPicker: photoPicker,
      photoStorage: photoStorage,
    );
  });

  group('Gợi ý, đổi món và ghi nhật ký bữa ăn (Issue #11 - Tiêu chí 1)', () {
    test('gợi ý và đổi món theo hồ sơ vẫn giữ nguyên ràng buộc dị ứng của Issue #10', () async {
      final session = await useCase.loadSuggestions(
        profile: SampleProfileFixtures.officeWorkerWalking,
        mealType: 'lunch',
      );

      expect(session.hasOptions, isTrue);
      expect(session.canSwap, isTrue);
      final firstSlug = session.currentOption!.item.slug;
      expect(
        session.allOptions.every(
          (option) => !option.item.allergens.contains('seafood'),
        ),
        isTrue,
      );

      final swapped = useCase.swapSuggestion(session);
      expect(swapped.currentOption!.item.slug, isNot(firstSlug));
      expect(
        swapped.currentOption!.item.allergens,
        isNot(contains('seafood')),
      );
    });

    test('lưu nhật ký với tên món người dùng xác nhận và ảnh chụp/chọn trong đường dẫn riêng tư', () async {
      final session = await useCase.loadSuggestions(
        profile: SampleProfileFixtures.officeWorkerWalking,
        mealType: 'lunch',
      );
      final chosenMeal = session.currentOption!.item;
      final cameraPhoto = await useCase.captureOrPickPhoto(
        MealPhotoSource.camera,
      );
      expect(cameraPhoto, isNotNull);

      final saved = await useCase.confirmAndLogMeal(
        ownerUid: 'firebase-uid-dai',
        confirmedMealName: 'Ức gà áp chảo ít dầu và khoai lang',
        mealType: 'lunch',
        selectedCatalogMeal: chosenMeal,
        selectedPhoto: cameraPhoto,
        note: 'Ăn trưa sau giờ học',
      );

      expect(saved.ownerUid, 'firebase-uid-dai');
      expect(saved.mealName, 'Ức gà áp chảo ít dầu và khoai lang');
      expect(saved.userConfirmedName, isTrue);
      expect(saved.hasPhoto, isTrue);
      expect(saved.imagePath, startsWith('firebase-uid-dai/'));
      expect(saved.photoSource, MealPhotoSource.camera);
      expect(saved.photoUploadStatus, MealPhotoUploadStatus.uploaded);

      final supabasePayload = saved.toSupabasePayload();
      expect(supabasePayload['meal_name'], 'Ức gà áp chảo ít dầu và khoai lang');
      expect(supabasePayload['image_path'], saved.imagePath);
      expect(supabasePayload['meal_id'], isNull); // fixture id không phải UUID
      expect(supabasePayload['note'], 'Ăn trưa sau giờ học');

      final signedForOwner = await photoStorage.createShortLivedSignedUrl(
        ownerUid: 'firebase-uid-dai',
        storagePath: saved.imagePath!,
      );
      final signedForOtherUser = await photoStorage.createShortLivedSignedUrl(
        ownerUid: 'firebase-uid-other',
        storagePath: saved.imagePath!,
      );
      expect(signedForOwner, isNotNull);
      expect(signedForOtherUser, isNull);
    });

    test('từ chối lưu khi người dùng chưa xác nhận tên món ăn', () async {
      await expectLater(
        useCase.confirmAndLogMeal(
          ownerUid: 'firebase-uid-dai',
          confirmedMealName: '   ',
        ),
        throwsArgumentError,
      );
    });

    testWidgets('MealLogComposerView cho đổi món, chụp ảnh và lưu tên món người dùng xác nhận', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealLogComposerView(
              ownerUid: 'firebase-uid-dai',
              profile: SampleProfileFixtures.officeWorkerWalking,
              useCase: useCase,
              mealType: 'lunch',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gợi ý món ăn theo hồ sơ'), findsOneWidget);
      expect(find.text('Đổi món khác'), findsOneWidget);

      final mealNameField = find.byType(TextFormField).first;
      final initialName =
          tester.widget<TextFormField>(mealNameField).controller!.text;
      expect(initialName, isNotEmpty);

      await tester.tap(find.text('Đổi món khác'));
      await tester.pumpAndSettle();
      final swappedName =
          tester.widget<TextFormField>(mealNameField).controller!.text;
      expect(swappedName, isNot(initialName));

      await tester.tap(find.text('Chụp ảnh bữa ăn'));
      await tester.pumpAndSettle();
      expect(find.textContaining('camera_meal.jpg'), findsOneWidget);

      await tester.enterText(mealNameField, 'Cơm trưa tự nấu có rau xanh');
      await tester.ensureVisible(find.text('Lưu nhật ký bữa ăn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu nhật ký bữa ăn'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Đã lưu nhật ký bữa ăn "Cơm trưa tự nấu có rau xanh" kèm ảnh riêng tư.',
        ),
        findsOneWidget,
      );
      final listScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byTooltip('Xem ảnh bữa ăn'),
        200,
        scrollable: listScrollable,
      );
      expect(
        find.byTooltip('Xem ảnh bữa ăn'),
        findsOneWidget,
      );
    });
  });
}
