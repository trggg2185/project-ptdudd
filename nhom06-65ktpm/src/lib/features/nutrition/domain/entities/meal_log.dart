import 'meal_photo_attachment.dart';

/// Thực thể nhật ký bữa ăn tương thích bảng `public.meal_logs` trên Supabase
/// và cấu trúc lưu cục bộ của `LocalDatabase` (`entity_type = 'meal_log'`).
class MealLog {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final String id;
  final String ownerUid;
  final String? mealId;
  final String? catalogSlug;
  final String mealName;
  final bool userConfirmedName;
  final String mealType; // breakfast, lunch, dinner, snack
  final DateTime consumedAt;
  final String? imagePath;
  final MealPhotoSource? photoSource;
  final MealPhotoUploadStatus photoUploadStatus;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  const MealLog({
    required this.id,
    required this.ownerUid,
    this.mealId,
    this.catalogSlug,
    required this.mealName,
    this.userConfirmedName = true,
    this.mealType = 'lunch',
    required this.consumedAt,
    this.imagePath,
    this.photoSource,
    this.photoUploadStatus = MealPhotoUploadStatus.none,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
  });

  bool get hasPhoto => imagePath != null && imagePath!.trim().isNotEmpty;

  MealLog copyWith({
    String? mealId,
    String? catalogSlug,
    String? mealName,
    bool? userConfirmedName,
    String? mealType,
    DateTime? consumedAt,
    String? imagePath,
    bool clearImagePath = false,
    MealPhotoSource? photoSource,
    MealPhotoUploadStatus? photoUploadStatus,
    String? note,
    DateTime? updatedAt,
    int? version,
  }) {
    return MealLog(
      id: id,
      ownerUid: ownerUid,
      mealId: mealId ?? this.mealId,
      catalogSlug: catalogSlug ?? this.catalogSlug,
      mealName: mealName ?? this.mealName,
      userConfirmedName: userConfirmedName ?? this.userConfirmedName,
      mealType: mealType ?? this.mealType,
      consumedAt: consumedAt ?? this.consumedAt,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      photoSource: clearImagePath ? null : (photoSource ?? this.photoSource),
      photoUploadStatus: photoUploadStatus ?? this.photoUploadStatus,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  /// Payload đúng các cột bảng `public.meal_logs` để đồng bộ qua `apply_log_sync`.
  Map<String, Object?> toSupabasePayload() {
    final validUuidMealId =
        mealId != null && _uuidPattern.hasMatch(mealId!.trim())
        ? mealId!.trim()
        : null;
    return {
      'meal_id': validUuidMealId,
      'meal_name': mealName.trim(),
      'image_path': imagePath,
      'consumed_at': consumedAt.toUtc().toIso8601String(),
      'note': note,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_uid': ownerUid,
      'meal_id': mealId,
      'catalog_slug': catalogSlug,
      'meal_name': mealName,
      'user_confirmed_name': userConfirmedName,
      'meal_type': mealType,
      'consumed_at': consumedAt.toUtc().toIso8601String(),
      'image_path': imagePath,
      'photo_source': photoSource?.name,
      'photo_upload_status': photoUploadStatus.name,
      'note': note,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'version': version,
    };
  }

  factory MealLog.fromMap(Map<String, dynamic> map) {
    final rawSource = map['photo_source'] as String?;
    final rawStatus = map['photo_upload_status'] as String?;
    return MealLog(
      id: map['id'] as String,
      ownerUid: map['owner_uid'] as String,
      mealId: map['meal_id'] as String?,
      catalogSlug: map['catalog_slug'] as String?,
      mealName: map['meal_name'] as String,
      userConfirmedName: (map['user_confirmed_name'] ?? true) as bool,
      mealType: (map['meal_type'] ?? 'lunch') as String,
      consumedAt: DateTime.parse(map['consumed_at'] as String),
      imagePath: map['image_path'] as String?,
      photoSource: rawSource == null
          ? null
          : MealPhotoSource.values.firstWhere(
              (v) => v.name == rawSource,
              orElse: () => MealPhotoSource.gallery,
            ),
      photoUploadStatus: rawStatus == null
          ? (map['image_path'] != null
                ? MealPhotoUploadStatus.uploaded
                : MealPhotoUploadStatus.none)
          : MealPhotoUploadStatus.values.firstWhere(
              (v) => v.name == rawStatus,
              orElse: () => MealPhotoUploadStatus.none,
            ),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }
}
