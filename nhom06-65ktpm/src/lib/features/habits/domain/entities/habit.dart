import 'dart:convert';
import '../../../../core/utils/date_helper.dart';
import 'habit_frequency.dart';

/// Bản ghi lịch sử chu kỳ lặp có ngày bắt đầu áp dụng (effective date).
///
/// Phục vụ yêu cầu: Sửa lịch trong tương lai không làm thay đổi lịch sử streak.
class FrequencySchedule {
  final HabitFrequency frequency;
  final DateTime effectiveFrom;

  const FrequencySchedule({
    required this.frequency,
    required this.effectiveFrom,
  });

  Map<String, dynamic> toJson() {
    return {
      'frequency': frequency.toJson(),
      'effectiveFrom': DateHelper.formatIsoDate(effectiveFrom),
    };
  }

  factory FrequencySchedule.fromJson(Map<String, dynamic> json) {
    return FrequencySchedule(
      frequency: HabitFrequency.fromJson(Map<String, dynamic>.from(json['frequency'] as Map)),
      effectiveFrom: DateTime.parse(json['effectiveFrom'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FrequencySchedule &&
        other.frequency == frequency &&
        DateHelper.isSameDay(other.effectiveFrom, effectiveFrom);
  }

  @override
  int get hashCode => Object.hash(frequency, effectiveFrom.year, effectiveFrom.month, effectiveFrom.day);
}

/// Khoảng thời gian thói quen bị tạm dừng (từ [pausedAt] đến [resumedAt]).
///
/// Phục vụ yêu cầu: Tạm dừng rồi tiếp tục lại vẫn bảo toàn lịch sử chuỗi streak (P1 Finding).
/// Các ngày trong khoảng tạm dừng này không sinh ngày đến hạn và không phá vỡ streak.
class PauseInterval {
  final DateTime pausedAt;
  final DateTime? resumedAt;

  const PauseInterval({
    required this.pausedAt,
    this.resumedAt,
  });

  /// Kiểm tra ngày [date] có rơi vào khoảng thời gian tạm dừng này hay không.
  bool contains(DateTime date) {
    final norm = DateHelper.normalize(date);
    final start = DateHelper.normalize(pausedAt);
    if (norm.isBefore(start)) return false;

    if (resumedAt == null) {
      // Đang tạm dừng chưa tiếp tục
      return true;
    }
    final end = DateHelper.normalize(resumedAt!);
    // Ngày trước ngày tiếp tục vẫn thuộc khoảng tạm dừng
    return norm.isBefore(end);
  }

  Map<String, dynamic> toJson() {
    return {
      'pausedAt': DateHelper.formatIsoDate(pausedAt),
      if (resumedAt != null) 'resumedAt': DateHelper.formatIsoDate(resumedAt!),
    };
  }

  factory PauseInterval.fromJson(Map<String, dynamic> json) {
    return PauseInterval(
      pausedAt: DateTime.parse(json['pausedAt'] as String),
      resumedAt: json['resumedAt'] != null
          ? DateTime.parse(json['resumedAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PauseInterval &&
        DateHelper.isSameDay(other.pausedAt, pausedAt) &&
        ((other.resumedAt == null && resumedAt == null) ||
            (other.resumedAt != null &&
                resumedAt != null &&
                DateHelper.isSameDay(other.resumedAt!, resumedAt!)));
  }

  @override
  int get hashCode => Object.hash(
        pausedAt.year,
        pausedAt.month,
        pausedAt.day,
        resumedAt?.year,
        resumedAt?.month,
        resumedAt?.day,
      );
}

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

  /// Chu kỳ lặp hiện tại.
  final HabitFrequency frequency;

  /// Lịch sử các phiên bản chu kỳ lặp kèm ngày áp dụng.
  final List<FrequencySchedule> frequencyHistory;

  /// Lịch sử các khoảng thời gian tạm dừng thói quen (pausedAt -> resumedAt).
  final List<PauseInterval> pauseHistory;

  /// Giờ nhắc nhở trong ngày (định dạng "HH:mm", ví dụ: "07:00").
  final String? reminderTime;

  /// Trạng thái kích hoạt (true = đang thực hiện, false = tạm dừng).
  final bool isActive;

  /// Thời điểm bắt đầu tạm dừng hiện tại (nếu isActive = false).
  final DateTime? pausedAt;

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
    List<FrequencySchedule>? frequencyHistory,
    List<PauseInterval>? pauseHistory,
    this.reminderTime,
    this.isActive = true,
    this.pausedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.version = 1,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        frequencyHistory = frequencyHistory ?? [
          FrequencySchedule(
            frequency: frequency,
            effectiveFrom: createdAt ?? DateTime.now(),
          ),
        ],
        pauseHistory = pauseHistory ?? const [];

  /// Kiểm tra xem thói quen có đang trong trạng thái tạm dừng vào ngày [date] hay không.
  bool isPausedOn(DateTime date) {
    for (final interval in pauseHistory) {
      if (interval.contains(date)) return true;
    }
    // Tương thích ngược: nếu habit đang !isActive và có pausedAt
    if (!isActive && pausedAt != null) {
      final normDate = DateHelper.normalize(date);
      final normPaused = DateHelper.normalize(pausedAt!);
      if (!normDate.isBefore(normPaused)) return true;
    }
    return false;
  }

  /// Lấy chu kỳ lặp có hiệu lực tại ngày [date].
  ///
  /// Đảm bảo rằng việc thay đổi chu kỳ trong tương lai không sửa đổi lịch sử
  /// các ngày trong quá khứ ("sửa lịch tương lai không sửa lịch sử").
  HabitFrequency getFrequencyOn(DateTime date) {
    if (frequencyHistory.isEmpty) {
      return frequency;
    }

    final normDate = DateHelper.normalize(date);
    // Sắp xếp các mốc lịch theo ngày áp dụng giảm dần
    final sorted = List<FrequencySchedule>.from(frequencyHistory)
      ..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom));

    for (final schedule in sorted) {
      final eff = DateHelper.normalize(schedule.effectiveFrom);
      if (!normDate.isBefore(eff)) {
        return schedule.frequency;
      }
    }

    return sorted.last.frequency;
  }

  Habit copyWith({
    String? id,
    String? ownerUid,
    String? name,
    String? description,
    HabitFrequency? frequency,
    List<FrequencySchedule>? frequencyHistory,
    List<PauseInterval>? pauseHistory,
    String? reminderTime,
    bool? isActive,
    DateTime? pausedAt,
    bool clearPausedAt = false,
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
      frequencyHistory: frequencyHistory ?? this.frequencyHistory,
      pauseHistory: pauseHistory ?? this.pauseHistory,
      reminderTime: reminderTime ?? this.reminderTime,
      isActive: isActive ?? this.isActive,
      pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
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
      'frequencyHistory': frequencyHistory.map((e) => e.toJson()).toList(),
      'pauseHistory': pauseHistory.map((e) => e.toJson()).toList(),
      'reminderTime': reminderTime,
      'isActive': isActive,
      'pausedAt': pausedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'version': version,
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    final freq = json['frequency'] != null
        ? HabitFrequency.fromJson(Map<String, dynamic>.from(json['frequency'] as Map))
        : const HabitFrequency.daily();

    List<FrequencySchedule>? history;
    if (json['frequencyHistory'] != null) {
      final rawList = json['frequencyHistory'] as List<dynamic>;
      history = rawList
          .map((e) => FrequencySchedule.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    List<PauseInterval>? pauses;
    if (json['pauseHistory'] != null) {
      final rawList = json['pauseHistory'] as List<dynamic>;
      pauses = rawList
          .map((e) => PauseInterval.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    return Habit(
      id: json['id'] as String,
      ownerUid: json['ownerUid'] as String? ?? '',
      name: json['name'] as String,
      description: json['description'] as String?,
      frequency: freq,
      frequencyHistory: history,
      pauseHistory: pauses,
      reminderTime: json['reminderTime'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      pausedAt: json['pausedAt'] != null ? DateTime.parse(json['pausedAt'] as String) : null,
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
      'frequencyHistory': frequencyHistory.map((e) => e.toJson()).toList(),
      'pauseHistory': pauseHistory.map((e) => e.toJson()).toList(),
      if (reminderTime != null) 'reminderTime': reminderTime,
      if (pausedAt != null) 'pausedAt': pausedAt!.toIso8601String(),
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
    List<FrequencySchedule>? history;
    List<PauseInterval>? pauses;
    String? reminder;
    DateTime? paused;

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
          if (decoded.containsKey('frequencyHistory')) {
            final rawList = decoded['frequencyHistory'] as List<dynamic>;
            history = rawList
                .map((e) => FrequencySchedule.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
          }
          if (decoded.containsKey('pauseHistory')) {
            final rawList = decoded['pauseHistory'] as List<dynamic>;
            pauses = rawList
                .map((e) => PauseInterval.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
          }
          reminder = decoded['reminderTime'] as String?;
          if (decoded['pausedAt'] != null) {
            paused = DateTime.parse(decoded['pausedAt'] as String);
          }
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
      frequencyHistory: history,
      pauseHistory: pauses,
      reminderTime: reminder,
      isActive: map['is_active'] as bool? ?? true,
      pausedAt: paused,
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
