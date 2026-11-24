import '../../../../core/utils/date_helper.dart';

/// Mức tỉnh táo tự đánh giá sau khi thức dậy (thang 1–5).
///
/// Lưu ý: Đây là cảm nhận chủ quan do người dùng tự khai báo, không phải
/// kết quả đo giấc ngủ từ cảm biến hay thời gian tắt màn hình điện thoại.
enum AlertnessLevel {
  veryGroggy('very_groggy', 1, 'Rất mệt / uể oải'),
  groggy('groggy', 2, 'Còn buồn ngủ'),
  neutral('neutral', 3, 'Bình thường'),
  refreshed('refreshed', 4, 'Tỉnh táo'),
  energized('energized', 5, 'Rất sảng khoái');

  const AlertnessLevel(this.code, this.score, this.label);

  final String code;
  final int score;
  final String label;

  static AlertnessLevel fromCode(String? code) {
    if (code == null || code.isEmpty) return AlertnessLevel.neutral;
    for (final level in values) {
      if (level.code == code || level.name == code) {
        return level;
      }
    }
    return AlertnessLevel.neutral;
  }
}

/// Thực thể đại diện cho một bản ghi nhật ký giấc ngủ tự khai báo.
///
/// Tương thích trực tiếp bảng Supabase `public.sleep_logs`:
/// (`id`, `owner_uid`, `slept_at`, `woke_at`, `feeling`, `note`, `created_at`, `updated_at`, `version`).
class SleepLog {
  final String id;
  final String ownerUid;

  /// Thời điểm bắt đầu ngủ (lưu chuẩn DateTime địa phương trên UI, chuyển UTC khi lưu cloud).
  final DateTime sleptAt;

  /// Thời điểm thức dậy (phải lớn hơn `sleptAt`).
  final DateTime wokeAt;

  /// Mức tỉnh táo tự đánh giá (ánh xạ cột `feeling` trên Supabase).
  final AlertnessLevel alertness;

  /// Ghi chú tùy chọn của người dùng (ví dụ: "Ngủ bù sau ca trực đêm").
  final String? note;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  SleepLog({
    required this.id,
    required this.ownerUid,
    required this.sleptAt,
    required this.wokeAt,
    this.alertness = AlertnessLevel.neutral,
    this.note,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.version = 1,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Tổng thời lượng giấc ngủ.
  Duration get duration => wokeAt.difference(sleptAt);

  /// Thời lượng tính bằng phút.
  int get durationMinutes => duration.inMinutes;

  /// Giấc ngủ có vắt qua mốc nửa đêm (00:00) theo giờ địa phương hay không.
  bool get crossesMidnight {
    final startLocal = sleptAt.toLocal();
    final endLocal = wokeAt.toLocal();
    return !DateHelper.isSameDay(startLocal, endLocal);
  }

  /// Giấc ngủ ban ngày (phổ biến với người làm ca đêm, ví dụ ngủ từ 06:00–17:59 trong ngày).
  bool get isDaytimeSleep {
    final startLocal = sleptAt.toLocal();
    final endLocal = wokeAt.toLocal();
    return DateHelper.isSameDay(startLocal, endLocal) &&
        startLocal.hour >= 5 &&
        startLocal.hour < 18;
  }

  /// Ngày lịch đại diện cho bản ghi ngủ (theo ngày địa phương bắt đầu ngủ).
  DateTime get startDate => DateHelper.normalize(sleptAt.toLocal());

  /// Ngày lịch thức dậy theo giờ địa phương.
  DateTime get wakeDate => DateHelper.normalize(wokeAt.toLocal());

  /// Chuỗi thời lượng dễ đọc (ví dụ "7 giờ 30 phút").
  String get formattedDuration {
    final totalMinutes = durationMinutes;
    if (totalMinutes <= 0) return '0 phút';
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours == 0) return '$mins phút';
    if (mins == 0) return '$hours giờ';
    return '$hours giờ $mins phút';
  }

  SleepLog copyWith({
    String? id,
    String? ownerUid,
    DateTime? sleptAt,
    DateTime? wokeAt,
    AlertnessLevel? alertness,
    String? note,
    bool clearNote = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
  }) {
    return SleepLog(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      sleptAt: sleptAt ?? this.sleptAt,
      wokeAt: wokeAt ?? this.wokeAt,
      alertness: alertness ?? this.alertness,
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  /// Ánh xạ tương thích bảng Supabase `public.sleep_logs`.
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'owner_uid': ownerUid,
      'slept_at': sleptAt.toUtc().toIso8601String(),
      'woke_at': wokeAt.toUtc().toIso8601String(),
      'feeling': alertness.code,
      'note': (note != null && note!.trim().isNotEmpty) ? note!.trim() : null,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'version': version,
    };
  }

  /// Khởi tạo từ bản ghi bảng Supabase `public.sleep_logs`.
  factory SleepLog.fromSupabaseMap(Map<String, dynamic> map) {
    return SleepLog(
      id: map['id'] as String,
      ownerUid: map['owner_uid'] as String? ?? '',
      sleptAt: DateTime.parse(map['slept_at'] as String).toLocal(),
      wokeAt: DateTime.parse(map['woke_at'] as String).toLocal(),
      alertness: AlertnessLevel.fromCode(map['feeling'] as String?),
      note: map['note'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String).toLocal()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String).toLocal()
          : null,
      version: map['version'] as int? ?? 1,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SleepLog &&
        other.id == id &&
        other.ownerUid == ownerUid &&
        other.sleptAt.toUtc() == sleptAt.toUtc() &&
        other.wokeAt.toUtc() == wokeAt.toUtc() &&
        other.alertness == alertness &&
        other.note == note &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(
        id,
        ownerUid,
        sleptAt.toUtc(),
        wokeAt.toUtc(),
        alertness,
        note,
        version,
      );
}
