import '../entities/exercise_catalog_item.dart';
import '../entities/meal_catalog_item.dart';

/// Hợp đồng giao tiếp (Interface) để truy xuất danh mục môn tập và món ăn.
/// Tầng Presentation/Domain sẽ gọi qua interface này để độc lập với nguồn lưu trữ (Memory/SQLite/Supabase).
abstract class CatalogRepository {
  Future<List<ExerciseCatalogItem>> getExerciseCatalog();
  Future<List<MealCatalogItem>> getMealCatalog();
}
