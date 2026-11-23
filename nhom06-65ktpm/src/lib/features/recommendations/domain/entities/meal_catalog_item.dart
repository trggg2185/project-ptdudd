import 'catalog_source.dart';

/// Thực thể đại diện cho một món ăn trong danh mục đã kiểm duyệt.
/// Phục vụ tiêu chí: nguyên liệu, dị nguyên, ngân sách, thời gian chuẩn bị và nguồn kiểm duyệt.
class MealCatalogItem {
  static const Set<String> _exactUnclearIngredientTokens = {
    'other',
    'misc',
    'various',
    'none',
    'etc',
    'khac',
    'khác',
    'v.v',
    'vv',
    '?',
    '...',
  };

  static const List<String> _unclearIngredientPhrases = [
    'unknown',
    'unclear',
    'unspecified',
    'unverified',
    'mystery',
    'secret',
    'tbd',
    'n/a',
    'khong_ro',
    'khong ro',
    'không rõ',
    'chua_ro',
    'chua ro',
    'chưa rõ',
    'khong_xac_dinh',
    'khong xac dinh',
    'không xác định',
    'chua_xac_dinh',
    'chua xac dinh',
    'chưa xác định',
    'khong_biet',
    'khong biet',
    'không biết',
    'chua_biet',
    'chua biet',
    'chưa biết',
    'bi_mat',
    'bi mat',
    'bí mật',
    'tong_hop',
    'tong hop',
    'tổng hợp',
    'nguyen_lieu_khac',
    'nguyên liệu khác',
    'thanh_phan_khac',
    'thành phần khác',
  ];

  final String id;
  final String slug;
  final String name;
  final String mealType; // breakfast, lunch, dinner, snack
  final List<String> ingredients; // Danh sách nguyên liệu (bắt buộc rõ ràng)
  final bool ingredientsClear; // Xác nhận thành phần đã được khai báo rõ ràng
  final List<String> allergens; // Mã dị nguyên chuẩn hóa (vd: dairy, egg, peanut, seafood, soy, gluten)
  final List<String> dietTags; // balanced, vegetarian, quick_prep, no_cook...
  final bool requiresCooking; // Có cần bếp để chế biến hay không
  final String budgetTier; // low, medium, high
  final int estimatedCostVnd; // Chi phí ước tính (VND)
  final int prepTimeMinutes; // Thời gian chuẩn bị & nấu (phút)
  final bool isVerified; // Trạng thái kiểm duyệt (approved)
  final CatalogSource source; // Nguồn tham khảo kiểm duyệt
  final String description;
  final String? notes; // Lưu ý chế biến/khẩu phần tham khảo (không mang tính điều trị)

  const MealCatalogItem({
    required this.id,
    required this.slug,
    required this.name,
    required this.mealType,
    required this.ingredients,
    this.ingredientsClear = true,
    required this.allergens,
    required this.dietTags,
    required this.requiresCooking,
    required this.budgetTier,
    required this.estimatedCostVnd,
    required this.prepTimeMinutes,
    required this.isVerified,
    required this.source,
    required this.description,
    this.notes,
  });

  /// Kiểm tra món ăn có rõ thành phần nguyên liệu hay không.
  /// Theo quy tắc đề án: món không rõ thành phần hoặc thiếu xác nhận `ingredients_clear`
  /// thì không được coi là an toàn.
  bool get hasClearIngredients {
    if (!ingredientsClear || ingredients.isEmpty) {
      return false;
    }
    return ingredients.every((item) {
      final normalized = item.trim().toLowerCase();
      if (normalized.isEmpty ||
          _exactUnclearIngredientTokens.contains(normalized)) {
        return false;
      }
      for (final phrase in _unclearIngredientPhrases) {
        if (normalized.contains(phrase)) {
          return false;
        }
      }
      return true;
    });
  }

  /// Kiểm tra món ăn đã được kiểm duyệt và có nguồn đầy đủ hay không.
  bool get hasVerifiedSource => isVerified && source.isComplete;

  /// Tên nguồn rút gọn tương thích ngược.
  String get verifiedSource => '${source.name} (${source.version})';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'slug': slug,
      'name': name,
      'meal_type': mealType,
      'ingredients': ingredients,
      'ingredients_clear': ingredientsClear,
      'allergens': allergens,
      'diet_tags': dietTags,
      'requires_cooking': requiresCooking,
      'budget_tier': budgetTier,
      'estimated_cost': estimatedCostVnd,
      'estimated_cost_vnd': estimatedCostVnd,
      'preparation_minutes': prepTimeMinutes,
      'prep_time_minutes': prepTimeMinutes,
      'approved': isVerified,
      'is_verified': isVerified,
      'source_name': source.name,
      'source_url': source.url,
      'source_version': source.version,
      'reviewed_at': source.reviewedAt,
      'description': description,
      'notes': notes,
    };
  }

  factory MealCatalogItem.fromMap(Map<String, dynamic> map) {
    final rawSource = map['source'] is Map<String, dynamic>
        ? CatalogSource.fromMap(map['source'] as Map<String, dynamic>)
        : CatalogSource.fromMap(map);

    return MealCatalogItem(
      id: (map['id'] ?? map['slug'] ?? '') as String,
      slug: (map['slug'] ?? map['id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      mealType: (map['meal_type'] ?? 'lunch') as String,
      ingredients: List<String>.from(map['ingredients'] as List? ?? const []),
      ingredientsClear: map['ingredients_clear'] == true,
      allergens: List<String>.from(map['allergens'] as List? ?? const []),
      dietTags: List<String>.from(map['diet_tags'] as List? ?? const []),
      requiresCooking: (map['requires_cooking'] ?? true) as bool,
      budgetTier: (map['budget_tier'] ?? 'medium') as String,
      estimatedCostVnd:
          (map['estimated_cost_vnd'] ?? map['estimated_cost'] as num?)
              ?.round() ??
          0,
      prepTimeMinutes:
          (map['prep_time_minutes'] ?? map['preparation_minutes'] as num?)
              ?.toInt() ??
          0,
      isVerified: (map['is_verified'] ?? map['approved'] ?? false) as bool,
      source: rawSource,
      description: (map['description'] ?? '') as String,
      notes: map['notes'] as String?,
    );
  }
}
