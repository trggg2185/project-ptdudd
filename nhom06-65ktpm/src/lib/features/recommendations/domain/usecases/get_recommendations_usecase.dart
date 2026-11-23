import '../entities/exercise_catalog_item.dart';
import '../entities/meal_catalog_item.dart';
import '../entities/recommendation_profile.dart';
import '../entities/recommendation_result.dart';
import '../repositories/catalog_repository.dart';
import '../services/recommendation_engine.dart';

/// Use case kết nối [CatalogRepository] và [RecommendationEngine].
/// Tầng Presentation hoặc module `planner` chỉ cần gọi use case này mà không phụ thuộc nguồn lưu trữ.
class GetRecommendationsUseCase {
  final CatalogRepository repository;
  final RecommendationEngine engine;

  const GetRecommendationsUseCase({
    required this.repository,
    this.engine = const RecommendationEngine(),
  });

  Future<RecommendationResult<ExerciseCatalogItem>> getExerciseRecommendations({
    required RecommendationProfile profile,
    List<String> recentSlugs = const [],
    int maxResults = 3,
  }) async {
    final catalog = await repository.getExerciseCatalog();
    return engine.recommendExercises(
      catalog: catalog,
      profile: profile,
      recentSlugs: recentSlugs,
      maxResults: maxResults,
    );
  }

  Future<RecommendationResult<MealCatalogItem>> getMealRecommendations({
    required RecommendationProfile profile,
    String? mealType,
    List<String> recentSlugs = const [],
    int maxResults = 3,
  }) async {
    final catalog = await repository.getMealCatalog();
    return engine.recommendMeals(
      catalog: catalog,
      profile: profile,
      mealType: mealType,
      recentSlugs: recentSlugs,
      maxResults: maxResults,
    );
  }
}
