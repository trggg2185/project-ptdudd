/// Thực thể đại diện cho một món ăn trong danh mục đã kiểm duyệt.
/// Phục vụ tiêu chí: có nguyên liệu, dị nguyên, ngân sách, thời gian chuẩn bị và nguồn kiểm duyệt.
class MealCatalogItem {
  final String id;
  final String name;
  final List<String> ingredients; // Danh sách nguyên liệu (bắt buộc rõ ràng)
  final List<String> allergens; // Danh sách dị nguyên (vd: ['hai_san', 'lac_dau_phong', 'trung', 'sua'])
  final String budgetTier; // 'low', 'medium', 'high'
  final int? estimatedCostVnd; // Chi phí ước tính (VND)
  final int prepTimeMinutes; // Thời gian chuẩn bị & nấu (phút)
  final bool isVerified; // Đã qua kiểm duyệt nguồn dinh dưỡng
  final String verifiedSource; // Nguồn kiểm duyệt (vd: WHO Healthy Diet, Vien Dinh Duong)
  final String? notes; // Lưu ý dinh dưỡng hoặc cách chế biến an toàn

  const MealCatalogItem({
    required this.id,
    required this.name,
    required this.ingredients,
    required this.allergens,
    required this.budgetTier,
    this.estimatedCostVnd,
    required this.prepTimeMinutes,
    required this.isVerified,
    required this.verifiedSource,
    this.notes,
  });

  /// Kiểm tra món ăn có rõ thành phần nguyên liệu hay không.
  /// Theo quy tắc đề án: Không rõ thành phần thì không được coi là an toàn.
  bool get hasClearIngredients => ingredients.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'ingredients': ingredients,
      'allergens': allergens,
      'budget_tier': budgetTier,
      'estimated_cost_vnd': estimatedCostVnd,
      'prep_time_minutes': prepTimeMinutes,
      'is_verified': isVerified,
      'verified_source': verifiedSource,
      'notes': notes,
    };
  }

  factory MealCatalogItem.fromMap(Map<String, dynamic> map) {
    return MealCatalogItem(
      id: map['id'] as String,
      name: map['name'] as String,
      ingredients: List<String>.from(map['ingredients'] as List? ?? []),
      allergens: List<String>.from(map['allergens'] as List? ?? []),
      budgetTier: map['budget_tier'] as String? ?? 'medium',
      estimatedCostVnd: map['estimated_cost_vnd'] as int?,
      prepTimeMinutes: map['prep_time_minutes'] as int? ?? 15,
      isVerified: map['is_verified'] as bool? ?? false,
      verifiedSource: map['verified_source'] as String? ?? '',
      notes: map['notes'] as String?,
    );
  }
}
