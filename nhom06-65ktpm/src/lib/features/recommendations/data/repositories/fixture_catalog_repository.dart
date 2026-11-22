import '../../domain/entities/exercise_catalog_item.dart';
import '../../domain/entities/meal_catalog_item.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../fixtures/sample_catalog_fixture.dart';

/// Triển khai mock/fixture của [CatalogRepository] để module `recommendations`
/// phát triển và kiểm thử độc lập trước khi gắn dữ liệu từ Supabase/SQLite.
class FixtureCatalogRepository implements CatalogRepository {
  final List<ExerciseCatalogItem> exercises;
  final List<MealCatalogItem> meals;

  const FixtureCatalogRepository({
    this.exercises = SampleCatalogFixture.sampleExercises,
    this.meals = SampleCatalogFixture.sampleMeals,
  });

  @override
  Future<List<ExerciseCatalogItem>> getExerciseCatalog() async {
    return List<ExerciseCatalogItem>.unmodifiable(exercises);
  }

  @override
  Future<List<MealCatalogItem>> getMealCatalog() async {
    return List<MealCatalogItem>.unmodifiable(meals);
  }
}
