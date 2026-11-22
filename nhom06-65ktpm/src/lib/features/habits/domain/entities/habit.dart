import 'dart:convert';
import 'habit_frequency.dart';

/// Thực thể đại diện cho một thói quen rèn luyện kỷ luật cá nhân của người dùng.
class Habit {
  /// Định danh duy nhất (UUID v4).
  final String id;

  /// UID người sở hữu (Firebase Auth UID).
  final String ownerUid;

  /// Tên thói quen (ví dụ: "Uống 2 lít nước", "Đọc sách 20 phút").
  final String name;

  /// Mô tả chi tiết hoặc ghi chú mục tiêu.
  final String? description;

  /// Chu kỳ lặp theo ngày trong tuần.
  final HabitFrequency frequency;

  /// Giờ nhắc nhở trong ngày (định dạng "HH:mm", ví dụ: "07:00").
  final String? reminderTime;

  /// Trạng thái kích hoạt (true = đang thực hiện, false = tạm dừng).
  final bool isActive;

  /// Thời điểm tạo thói quen.
  final DateTime createdAt;

  /// Thời điểm cập nhật gần nhất.
  final DateTime updatedAt;

  /// Phiên bản dữ liệu phục vụ đồng bộ.
  final int version;

  Habit({
    required this.id,
    required this.ownerUid,
    required this.name,
    this.description,
    this.frequency = const HabitFrequency.daily(),
    this.reminderTime,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.version = 1,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Habit copyWith({
    String? id,
    String? ownerUid,
    String? name,
    String? description,
    HabitFrequency? frequency,
    String? reminderTime,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
  }) {
    return Habit(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      name: name ?? this.name,
      description: description ?? this.description,
      frequency: frequency ?? this.frequency,
      reminderTime: reminderTime ?? this.reminderTime,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerUid': ownerUid,
      'name': name,
      'description': description,
      'frequency': frequency.toJson(),
      'reminderTime': reminderTime,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'version': version,
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'] as String,
      ownerUid: json['ownerUid'] as String? ?? '',
      name: json['name'] as String,
      description: json['description'] as String?,
      frequency: json['frequency'] != null
          ? HabitFrequency.fromJson(Map<String, dynamic>.from(json['frequency'] as Map))
          : const HabitFrequency.daily(),
      reminderTime: json['reminderTime'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      version: json['version'] as int? ?? 1,
    );
  }

  /// Ánh xạ tương thích bảng Supabase `public.habits`.
  Map<String, dynamic> toSupabaseMap() {
    final recurrenceMap = {
      'frequency': frequency.toJson(),
      if (reminderTime != null) 'reminderTime': reminderTime,
    };
    return {
      'id': id,
      'owner_uid': ownerUid,
      'name': name,
      'description': description,
      'recurrence_rule': jsonEncode(recurrenceMap),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'version': version,
    };
  }

  /// Khởi tạo thực thể từ bản ghi bảng Supabase `public.habits`.
  factory Habit.fromSupabaseMap(Map<String, dynamic> map) {
    HabitFrequency freq = const HabitFrequency.daily();
    String? reminder;
    final recurrenceRuleStr = map['recurrence_rule'] as String?;
    if (recurrenceRuleStr != null && recurrenceRuleStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(recurrenceRuleStr);
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('frequency')) {
            freq = HabitFrequency.fromJson(Map<String, dynamic>.from(decoded['frequency'] as Map));
          } else if (decoded.containsKey('type')) {
            freq = HabitFrequency.fromJson(decoded);
          }
          reminder = decoded['reminderTime'] as String?;
        }
      } catch (_) {
        // Fallback default
      }
    }

    return Habit(
      id: map['id'] as String,
      ownerUid: map['owner_uid'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      frequency: freq,
      reminderTime: reminder,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      version: map['version'] as int? ?? 1,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Habit &&
        other.id == id &&
        other.ownerUid == ownerUid &&
        other.name == name &&
        other.description == description &&
        other.frequency == frequency &&
        other.reminderTime == reminderTime &&
        other.isActive == isActive;
  }

  @override
  int get hashCode => Object.hash(id, ownerUid, name, frequency, reminderTime, isActive);
}
