/// Thực thể đại diện cho một môn tập / bài tập trong danh mục đã kiểm duyệt.
/// Phục vụ tiêu chí: có thiết bị, thời lượng, mức độ và nguồn kiểm duyệt.
class ExerciseCatalogItem {
  final String id;
  final String name;
  final String category; // vd: cardio, strength, flexibility, walking
  final int durationMinutes; // Thời lượng dự kiến (phút)
  final List<String> equipmentNeeded; // Thiết bị cần có (vd: ['tham_tap'], ['ta_don'], [] nếu không cần)
  final String experienceLevel; // 'beginner', 'intermediate', 'advanced'
  final bool isVerified; // Trạng thái kiểm duyệt
  final String verifiedSource; // Nguồn tài liệu (vd: WHO Guidelines 2020)
  final String? description;

  const ExerciseCatalogItem({
    required this.id,
    required this.name,
    required this.category,
    required this.durationMinutes,
    required this.equipmentNeeded,
    required this.experienceLevel,
    required this.isVerified,
    required this.verifiedSource,
    this.description,
  });

  /// Kiểm tra bài tập có yêu cầu thiết bị nào không
  bool get requiresEquipment => equipmentNeeded.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'duration_minutes': durationMinutes,
      'equipment_needed': equipmentNeeded,
      'experience_level': experienceLevel,
      'is_verified': isVerified,
      'verified_source': verifiedSource,
      'description': description,
    };
  }

  factory ExerciseCatalogItem.fromMap(Map<String, dynamic> map) {
    return ExerciseCatalogItem(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      durationMinutes: map['duration_minutes'] as int,
      equipmentNeeded: List<String>.from(map['equipment_needed'] as List? ?? []),
      experienceLevel: map['experience_level'] as String? ?? 'beginner',
      isVerified: map['is_verified'] as bool? ?? false,
      verifiedSource: map['verified_source'] as String? ?? '',
      description: map['description'] as String?,
    );
  }
}
