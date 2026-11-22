import '../entities/exercise_catalog_item.dart';
import '../entities/meal_catalog_item.dart';
import '../entities/recommendation_profile.dart';
import '../entities/recommendation_result.dart';
import 'catalog_hard_filter.dart';

/// Bộ gợi ý theo quy tắc có giải thích cho môn tập và món ăn.
///
/// Luồng cố định:
/// 1. Chạy [CatalogHardFilter] trước để kiểm tra đầu vào bắt buộc và lọc cứng an toàn.
/// 2. Nếu bị chặn hoặc không còn ứng viên hợp lệ -> trả danh sách rỗng, không nới ràng buộc.
/// 3. Xếp hạng ứng viên hợp lệ theo sở thích, thời gian, ngân sách, đa dạng và phản hồi trước đó.
/// 4. Sinh câu giải thích cụ thể cùng danh sách lựa chọn thay thế.
class RecommendationEngine {
  final CatalogHardFilter hardFilter;

  const RecommendationEngine({this.hardFilter = const CatalogHardFilter()});

  /// Gợi ý môn tập / hoạt động từ danh mục theo hồ sơ cá nhân.
  RecommendationResult<ExerciseCatalogItem> recommendExercises({
    required List<ExerciseCatalogItem> catalog,
    required RecommendationProfile profile,
    List<String> recentSlugs = const [],
    int maxResults = 3,
  }) {
    final filtered = hardFilter.filterExercises(
      catalog: catalog,
      profile: profile,
    );

    if (!filtered.canProceed || filtered.eligibleItems.isEmpty) {
      return RecommendationResult<ExerciseCatalogItem>(
        status: filtered.status,
        emptyReason: filtered.message,
        missingFields: filtered.missingFields,
        excludedCount: filtered.excludedItems.length,
      );
    }

    final preferredCategories = profile.preferredExerciseCategories
        .map(_normalize)
        .toSet();
    final preferredTags = profile.preferredExerciseTags.map(_normalize).toSet();
    final preferredEnv = _normalize(profile.preferredEnvironment);
    final likedSlugs = profile.likedSlugs.map(_normalize).toSet();
    final dislikedSlugs = profile.dislikedSlugs.map(_normalize).toSet();
    final recentSet = recentSlugs.map(_normalize).toSet();
    final availableMinutes = profile.availableMinutesPerSession!;

    final scored = filtered.eligibleItems.map((item) {
      var score = 0.0;
      final reasons = <String>[];

      // 1. Sở thích theo nhóm hoạt động, môi trường và thẻ
      if (preferredCategories.contains(_normalize(item.category)) ||
          preferredCategories.contains(_normalize(item.slug))) {
        score += 30;
        reasons.add('khớp nhóm hoạt động bạn yêu thích (${item.category})');
      }

      if (preferredEnv == 'outdoor' &&
          (_normalize(item.environment) == 'outdoor' ||
              _normalize(item.environment) == 'both')) {
        score += 18;
        reasons.add('bạn thích hoạt động ngoài trời');
      } else if (preferredEnv == 'indoor' &&
          (_normalize(item.environment) == 'indoor' ||
              _normalize(item.environment) == 'both')) {
        score += 18;
        reasons.add('phù hợp tập trong nhà theo ưu tiên của bạn');
      }

      final matchedTags = item.tags
          .map(_normalize)
          .where(preferredTags.contains)
          .toList();
      if (matchedTags.isNotEmpty) {
        score += (matchedTags.length * 12).clamp(0, 24);
        reasons.add('khớp sở thích (${matchedTags.join(', ')})');
      }

      // 2. Thời gian rảnh
      final gapMinutes = availableMinutes - item.durationMinutes;
      if (gapMinutes <= 10) {
        score += 20;
        reasons.add(
          'vừa vặn với khoảng trống $availableMinutes phút (cần ${item.durationMinutes} phút)',
        );
      } else {
        score += 10;
        reasons.add(
          'phù hợp quỹ thời gian $availableMinutes phút rảnh (${item.durationMinutes} phút)',
        );
      }

      // 3. Thiết bị & Ngân sách
      if (!item.requiresEquipment) {
        score += 14;
        reasons.add('không cần thiết bị');
      } else {
        score += 8;
        reasons.add(
          'dùng đúng thiết bị bạn sẵn có (${item.equipmentNeeded.join(', ')})',
        );
      }

      switch (_normalize(item.budgetTier)) {
        case 'free':
          score += 15;
          reasons.add('miễn phí');
          break;
        case 'low':
          score += 10;
          reasons.add('ngân sách thấp');
          break;
        case 'medium':
          score += 5;
          reasons.add('ngân sách trung bình');
          break;
        default:
          score += 2;
      }

      // 4. Phản hồi thích / không phù hợp từ các lần trước
      final slug = _normalize(item.slug);
      if (likedSlugs.contains(slug)) {
        score += 20;
        reasons.add('bạn từng đánh dấu yêu thích trước đây');
      } else if (dislikedSlugs.contains(slug)) {
        score -= 25;
      }

      // 5. Sự đa dạng
      if (recentSet.contains(slug)) {
        score -= 8;
      } else if (recentSet.isNotEmpty) {
        score += 10;
        reasons.add('giúp đa dạng hóa lịch vận động gần đây');
      }

      final explanation =
          'Gợi ý "${item.name}" vì ${reasons.join(', ')}.';
      final equipmentText = item.requiresEquipment
          ? item.equipmentNeeded.join(', ')
          : 'Không cần thiết bị';
      final conditionsSummary =
          'Thời lượng: ${item.durationMinutes} phút | Thiết bị: $equipmentText | Mức: ${item.experienceLevel} | Nguồn: ${item.verifiedSource}';

      return RankedRecommendation<ExerciseCatalogItem>(
        item: item,
        score: score,
        reasons: List<String>.unmodifiable(reasons),
        explanation: explanation,
        conditionsSummary: conditionsSummary,
      );
    }).toList();

    scored.sort((a, b) {
      final scoreDiff = b.score.compareTo(a.score);
      if (scoreDiff != 0) return scoreDiff;
      final aGap = (availableMinutes - a.item.durationMinutes).abs();
      final bGap = (availableMinutes - b.item.durationMinutes).abs();
      final gapDiff = aGap.compareTo(bGap);
      if (gapDiff != 0) return gapDiff;
      final costDiff = a.item.estimatedCostVnd.compareTo(b.item.estimatedCostVnd);
      if (costDiff != 0) return costDiff;
      return a.item.slug.compareTo(b.item.slug);
    });

    final safeLimit = maxResults < 1 ? 1 : maxResults;
    final top = scored.take(safeLimit).toList();
    final alt = scored.skip(safeLimit).toList();

    return RecommendationResult<ExerciseCatalogItem>(
      status: filtered.status,
      recommendations: List<RankedRecommendation<ExerciseCatalogItem>>.unmodifiable(
        top,
      ),
      alternatives: List<RankedRecommendation<ExerciseCatalogItem>>.unmodifiable(
        alt,
      ),
      excludedCount: filtered.excludedItems.length,
    );
  }

  /// Gợi ý món ăn từ danh mục theo hồ sơ cá nhân.
  RecommendationResult<MealCatalogItem> recommendMeals({
    required List<MealCatalogItem> catalog,
    required RecommendationProfile profile,
    String? mealType,
    List<String> recentSlugs = const [],
    int maxResults = 3,
  }) {
    final filtered = hardFilter.filterMeals(
      catalog: catalog,
      profile: profile,
      mealType: mealType,
    );

    if (!filtered.canProceed || filtered.eligibleItems.isEmpty) {
      return RecommendationResult<MealCatalogItem>(
        status: filtered.status,
        emptyReason: filtered.message,
        missingFields: filtered.missingFields,
        excludedCount: filtered.excludedItems.length,
      );
    }

    final preferredDiets = profile.preferredDietTags.map(_normalize).toSet();
    final likedSlugs = profile.likedSlugs.map(_normalize).toSet();
    final dislikedSlugs = profile.dislikedSlugs.map(_normalize).toSet();
    final recentSet = recentSlugs.map(_normalize).toSet();

    final scored = filtered.eligibleItems.map((item) {
      var score = 0.0;
      final reasons = <String>[
        'rõ thành phần và không chứa dị nguyên cần tránh',
      ];

      // 1. Sở thích chế độ ăn
      final matchedDiets = item.dietTags
          .map(_normalize)
          .where(preferredDiets.contains)
          .toList();
      if (matchedDiets.isNotEmpty) {
        score += (matchedDiets.length * 15).clamp(0, 30);
        reasons.add('phù hợp sở thích ăn uống (${matchedDiets.join(', ')})');
      }

      // 2. Thời gian chuẩn bị & khả năng nấu
      if (profile.maxMealPrepMinutes != null) {
        score += 15;
        if (item.prepTimeMinutes <= 15) {
          score += 10;
        }
        reasons.add(
          'chuẩn bị trong ${item.prepTimeMinutes} phút (nằm trong giới hạn ${profile.maxMealPrepMinutes} phút)',
        );
      } else if (item.prepTimeMinutes <= 15) {
        score += 10;
        reasons.add('chuẩn bị nhanh (${item.prepTimeMinutes} phút)');
      } else {
        score += 5;
        reasons.add('thời gian chuẩn bị ${item.prepTimeMinutes} phút');
      }

      if (!item.requiresCooking) {
        score += 6;
        reasons.add('không cần nấu phức tạp');
      }

      // 3. Ngân sách
      if (profile.maxMealBudgetVnd != null && profile.maxMealBudgetVnd! > 0) {
        final ratio = item.estimatedCostVnd / profile.maxMealBudgetVnd!;
        score += ratio <= 0.7 ? 20 : 12;
        reasons.add(
          'chi phí ước tính ${item.estimatedCostVnd} VND trong ngân sách ${profile.maxMealBudgetVnd} VND',
        );
      } else {
        switch (_normalize(item.budgetTier)) {
          case 'low':
            score += 14;
            reasons.add('ngân sách tiết kiệm (${item.estimatedCostVnd} VND)');
            break;
          case 'medium':
            score += 8;
            reasons.add('ngân sách trung bình (${item.estimatedCostVnd} VND)');
            break;
          default:
            score += 3;
            reasons.add('chi phí ước tính ${item.estimatedCostVnd} VND');
        }
      }

      // 4. Phản hồi người dùng
      final slug = _normalize(item.slug);
      if (likedSlugs.contains(slug)) {
        score += 20;
        reasons.add('bạn từng đánh dấu thích món này');
      } else if (dislikedSlugs.contains(slug)) {
        score -= 25;
      }

      // 5. Sự đa dạng
      if (recentSet.contains(slug)) {
        score -= 8;
      } else if (recentSet.isNotEmpty) {
        score += 10;
        reasons.add('giúp đa dạng thực đơn gần đây');
      }

      final explanation = 'Gợi ý "${item.name}" vì ${reasons.join(', ')}.';
      final allergenText = item.allergens.isEmpty
          ? 'Không chứa dị nguyên phổ biến'
          : item.allergens.join(', ');
      final conditionsSummary =
          'Chuẩn bị: ${item.prepTimeMinutes} phút | Chi phí: ${item.estimatedCostVnd} VND | Dị nguyên: $allergenText | Nguồn: ${item.verifiedSource}';

      return RankedRecommendation<MealCatalogItem>(
        item: item,
        score: score,
        reasons: List<String>.unmodifiable(reasons),
        explanation: explanation,
        conditionsSummary: conditionsSummary,
      );
    }).toList();

    scored.sort((a, b) {
      final scoreDiff = b.score.compareTo(a.score);
      if (scoreDiff != 0) return scoreDiff;
      final costDiff = a.item.estimatedCostVnd.compareTo(b.item.estimatedCostVnd);
      if (costDiff != 0) return costDiff;
      final prepDiff = a.item.prepTimeMinutes.compareTo(b.item.prepTimeMinutes);
      if (prepDiff != 0) return prepDiff;
      return a.item.slug.compareTo(b.item.slug);
    });

    final safeLimit = maxResults < 1 ? 1 : maxResults;
    final top = scored.take(safeLimit).toList();
    final alt = scored.skip(safeLimit).toList();

    return RecommendationResult<MealCatalogItem>(
      status: filtered.status,
      recommendations: List<RankedRecommendation<MealCatalogItem>>.unmodifiable(
        top,
      ),
      alternatives: List<RankedRecommendation<MealCatalogItem>>.unmodifiable(
        alt,
      ),
      excludedCount: filtered.excludedItems.length,
    );
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
