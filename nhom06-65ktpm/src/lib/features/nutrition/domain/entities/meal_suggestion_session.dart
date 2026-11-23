import '../../../recommendations/domain/entities/meal_catalog_item.dart';
import '../../../recommendations/domain/entities/recommendation_result.dart';

/// Phiên gợi ý và đổi món ăn từ danh mục đã qua lọc cứng an toàn (Issue #10).
class MealSuggestionSession {
  final String? mealType;
  final RecommendationResult<MealCatalogItem> result;
  final int selectedIndex;

  const MealSuggestionSession({
    this.mealType,
    required this.result,
    this.selectedIndex = 0,
  });

  /// Toàn bộ các lựa chọn hợp lệ (gợi ý chính + lựa chọn thay thế) đều đã qua lọc cứng dị ứng.
  List<RankedRecommendation<MealCatalogItem>> get allOptions => [
    ...result.recommendations,
    ...result.alternatives,
  ];

  bool get hasOptions => allOptions.isNotEmpty;

  bool get canSwap => allOptions.length > 1;

  RankedRecommendation<MealCatalogItem>? get currentOption {
    final options = allOptions;
    if (options.isEmpty) return null;
    final safeIndex = selectedIndex.clamp(0, options.length - 1);
    return options[safeIndex];
  }

  /// Chuyển sang lựa chọn thay thế hợp lệ tiếp theo trong danh sách đã lọc an toàn.
  MealSuggestionSession swapToNext() {
    final options = allOptions;
    if (options.length <= 1) return this;
    final nextIndex = (selectedIndex + 1) % options.length;
    return MealSuggestionSession(
      mealType: mealType,
      result: result,
      selectedIndex: nextIndex,
    );
  }

  /// Chọn trực tiếp một món thay thế theo slug nếu nằm trong danh sách hợp lệ.
  MealSuggestionSession selectBySlug(String slug) {
    final options = allOptions;
    final index = options.indexWhere((option) => option.item.slug == slug);
    if (index < 0) return this;
    return MealSuggestionSession(
      mealType: mealType,
      result: result,
      selectedIndex: index,
    );
  }
}
