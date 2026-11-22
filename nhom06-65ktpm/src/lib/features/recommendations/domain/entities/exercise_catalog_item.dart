import 'catalog_source.dart';

/// Thực thể đại diện cho một môn tập / hoạt động vận động trong danh mục kiểm duyệt.
/// Phục vụ tiêu chí: thiết bị, thời lượng, mức kinh nghiệm, ngân sách, giới hạn vận động và nguồn kiểm duyệt.
class ExerciseCatalogItem {
  final String id;
  final String slug;
  final String name;
  final String category; // walking, cardio, strength, flexibility, cycling
  final int durationMinutes; // Thời lượng dự kiến (phút)
  final List<String> equipmentNeeded; // Thiết bị cần có ([] nếu không cần)
  final String experienceLevel; // beginner, intermediate, advanced
  final String environment; // indoor, outdoor, both
  final String budgetTier; // free, low, medium, high
  final int estimatedCostVnd; // Chi phí tham khảo mỗi buổi (0 nếu miễn phí)
  final List<String> contraindicatedLimitations; // Giới hạn vận động cần tránh
  final List<String> tags; // Thẻ sở thích/đặc điểm để xếp hạng và giải thích
  final bool isVerified; // Trạng thái kiểm duyệt (approved)
  final CatalogSource source; // Nguồn tham khảo kiểm duyệt
  final String description;

  const ExerciseCatalogItem({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    required this.durationMinutes,
    required this.equipmentNeeded,
    required this.experienceLevel,
    required this.environment,
    required this.budgetTier,
    required this.estimatedCostVnd,
    required this.contraindicatedLimitations,
    required this.tags,
    required this.isVerified,
    required this.source,
    required this.description,
  });

  /// Kiểm tra bài tập có yêu cầu thiết bị hay không.
  bool get requiresEquipment => equipmentNeeded.isNotEmpty;

  /// Kiểm tra bài tập đã được kiểm duyệt và có nguồn đầy đủ hay không.
  bool get hasVerifiedSource => isVerified && source.isComplete;

  /// Tên nguồn rút gọn tương thích ngược.
  String get verifiedSource => '${source.name} (${source.version})';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'slug': slug,
      'name': name,
      'category': category,
      'duration_minutes': durationMinutes,
      'equipment': equipmentNeeded,
      'equipment_needed': equipmentNeeded,
      'experience_level': experienceLevel,
      'environment': environment,
      'budget_tier': budgetTier,
      'estimated_cost_vnd': estimatedCostVnd,
      'contraindicated_limitations': contraindicatedLimitations,
      'tags': tags,
      'approved': isVerified,
      'is_verified': isVerified,
      'source_name': source.name,
      'source_url': source.url,
      'source_version': source.version,
      'reviewed_at': source.reviewedAt,
      'description': description,
    };
  }

  factory ExerciseCatalogItem.fromMap(Map<String, dynamic> map) {
    final rawEquipment = map['equipment_needed'] ?? map['equipment'];
    final rawSource = map['source'] is Map<String, dynamic>
        ? CatalogSource.fromMap(map['source'] as Map<String, dynamic>)
        : CatalogSource.fromMap(map);

    return ExerciseCatalogItem(
      id: (map['id'] ?? map['slug'] ?? '') as String,
      slug: (map['slug'] ?? map['id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      category: (map['category'] ?? 'general') as String,
      durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 0,
      equipmentNeeded: List<String>.from(rawEquipment as List? ?? const []),
      experienceLevel: (map['experience_level'] ?? 'beginner') as String,
      environment: (map['environment'] ?? 'both') as String,
      budgetTier: (map['budget_tier'] ?? 'free') as String,
      estimatedCostVnd:
          (map['estimated_cost_vnd'] ?? map['estimated_cost'] as num?)
              ?.round() ??
          0,
      contraindicatedLimitations: List<String>.from(
        map['contraindicated_limitations'] as List? ?? const [],
      ),
      tags: List<String>.from(map['tags'] as List? ?? const []),
      isVerified: (map['is_verified'] ?? map['approved'] ?? false) as bool,
      source: rawSource,
      description: (map['description'] ?? '') as String,
    );
  }
}
