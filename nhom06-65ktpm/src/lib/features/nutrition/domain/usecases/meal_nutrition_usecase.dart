import '../../../../core/utils/id_generator.dart';
import '../../../recommendations/domain/entities/meal_catalog_item.dart';
import '../../../recommendations/domain/entities/recommendation_profile.dart';
import '../../../recommendations/domain/usecases/get_recommendations_usecase.dart';
import '../entities/meal_log.dart';
import '../entities/meal_photo_attachment.dart';
import '../entities/meal_suggestion_session.dart';
import '../repositories/meal_log_repository.dart';
import '../repositories/meal_photo_picker.dart';
import '../repositories/meal_photo_storage.dart';

/// Use case điều phối luồng cốt lõi của nhật ký bữa ăn:
/// 1. Gợi ý & đổi món theo hồ sơ thông qua [GetRecommendationsUseCase] (Issue #10).
/// 2. Chụp/chọn ảnh bữa ăn qua [MealPhotoPicker].
/// 3. Lưu nhật ký với tên món do người dùng xác nhận và đường dẫn ảnh riêng tư.
class MealNutritionUseCase {
  final GetRecommendationsUseCase recommendationsUseCase;
  final MealLogRepository mealLogRepository;
  final MealPhotoPicker photoPicker;
  final MealPhotoStorage photoStorage;

  const MealNutritionUseCase({
    required this.recommendationsUseCase,
    required this.mealLogRepository,
    required this.photoPicker,
    required this.photoStorage,
  });

  /// Lấy danh sách món gợi ý và lựa chọn thay thế hợp lệ theo hồ sơ người dùng.
  Future<MealSuggestionSession> loadSuggestions({
    required RecommendationProfile profile,
    String? mealType,
    List<String> recentSlugs = const [],
    int maxResults = 3,
  }) async {
    final result = await recommendationsUseCase.getMealRecommendations(
      profile: profile,
      mealType: mealType,
      recentSlugs: recentSlugs,
      maxResults: maxResults,
    );
    return MealSuggestionSession(mealType: mealType, result: result);
  }

  /// Đổi sang món thay thế tiếp theo trong danh sách đã lọc an toàn.
  MealSuggestionSession swapSuggestion(MealSuggestionSession session) {
    return session.swapToNext();
  }

  /// Chọn trực tiếp một món thay thế trong phiên gợi ý hiện tại.
  MealSuggestionSession selectSuggestionBySlug(
    MealSuggestionSession session,
    String slug,
  ) {
    return session.selectBySlug(slug);
  }

  /// Chụp ảnh từ camera hoặc chọn ảnh từ thư viện thiết bị.
  Future<SelectedMealPhoto?> captureOrPickPhoto(MealPhotoSource source) {
    return photoPicker.pickPhoto(source);
  }

  /// Ghi nhật ký bữa ăn với tên món do người dùng xác nhận và ảnh (nếu có).
  Future<MealLog> confirmAndLogMeal({
    required String ownerUid,
    required String confirmedMealName,
    String mealType = 'lunch',
    MealCatalogItem? selectedCatalogMeal,
    SelectedMealPhoto? selectedPhoto,
    DateTime? consumedAt,
    String? note,
  }) async {
    final trimmedOwner = ownerUid.trim();
    if (trimmedOwner.isEmpty) {
      throw ArgumentError.value(
        ownerUid,
        'ownerUid',
        'Thiếu định danh chủ tài khoản.',
      );
    }

    final trimmedMealName = confirmedMealName.trim();
    if (trimmedMealName.isEmpty) {
      throw ArgumentError.value(
        confirmedMealName,
        'confirmedMealName',
        'Người dùng cần nhập hoặc xác nhận tên món ăn trước khi lưu.',
      );
    }

    final now = DateTime.now().toUtc();
    final logId = IdGenerator.generateUuid();
    StoredMealPhoto? storedPhoto;

    if (selectedPhoto != null) {
      storedPhoto = await photoStorage.uploadPrivatePhoto(
        ownerUid: trimmedOwner,
        logId: logId,
        photo: selectedPhoto,
      );
    }

    final normalizedNote = note?.trim();
    final log = MealLog(
      id: logId,
      ownerUid: trimmedOwner,
      mealId: selectedCatalogMeal?.id,
      catalogSlug: selectedCatalogMeal?.slug,
      mealName: trimmedMealName,
      userConfirmedName: true,
      mealType: mealType,
      consumedAt: (consumedAt ?? now).toUtc(),
      imagePath: storedPhoto?.storagePath,
      photoSource: storedPhoto?.source,
      photoUploadStatus: storedPhoto?.uploadStatus ?? MealPhotoUploadStatus.none,
      note: (normalizedNote == null || normalizedNote.isEmpty)
          ? null
          : normalizedNote,
      createdAt: now,
      updatedAt: now,
      version: 1,
    );

    return mealLogRepository.saveMealLog(log);
  }

  Future<List<MealLog>> getMealHistory({required String ownerUid}) {
    return mealLogRepository.getMealLogs(ownerUid: ownerUid);
  }
}
