/// Trạng thái phê duyệt của bảng `public.plans`.
enum PlanApprovalStatus {
  draft,
  approved,
  completed,
  cancelled;

  static PlanApprovalStatus fromDb(String? value) {
    switch (value) {
      case 'approved':
        return PlanApprovalStatus.approved;
      case 'completed':
        return PlanApprovalStatus.completed;
      case 'cancelled':
        return PlanApprovalStatus.cancelled;
      case 'draft':
      default:
        return PlanApprovalStatus.draft;
    }
  }
}

/// Trạng thái của từng mục lịch trong `public.plan_items`.
enum PlanItemStatus {
  draft,
  approved,
  completed,
  skipped;

  static PlanItemStatus fromDb(String? value) {
    switch (value) {
      case 'approved':
        return PlanItemStatus.approved;
      case 'completed':
        return PlanItemStatus.completed;
      case 'skipped':
        return PlanItemStatus.skipped;
      case 'draft':
      default:
        return PlanItemStatus.draft;
    }
  }
}

/// Loại hoạt động trong `public.plan_items.item_type`.
enum ReminderItemType {
  exercise,
  meal,
  sleep,
  habit;

  String get displayLabel {
    switch (this) {
      case ReminderItemType.exercise:
        return 'Vận động';
      case ReminderItemType.meal:
        return 'Bữa ăn';
      case ReminderItemType.sleep:
        return 'Giấc ngủ';
      case ReminderItemType.habit:
        return 'Thói quen';
    }
  }

  static ReminderItemType fromDb(String? value) {
    switch (value) {
      case 'exercise':
        return ReminderItemType.exercise;
      case 'meal':
        return ReminderItemType.meal;
      case 'sleep':
        return ReminderItemType.sleep;
      case 'habit':
      default:
        return ReminderItemType.habit;
    }
  }
}

/// Mục lịch sinh hoạt dùng làm nguồn đặt nhắc cục bộ.
///
/// Quy tắc nghiệp vụ cốt lõi (Issue #6):
/// **Chỉ tạo nhắc khi cả `planStatus == approved` VÀ `itemStatus == approved`.**
/// Lịch nháp (`draft`), đã hoàn thành (`completed`), đã bỏ qua (`skipped`) hoặc đã hủy (`cancelled`)
/// tuyệt đối không được tạo thông báo nhắc.
class ApprovedPlanReminderItem {
  final String itemId;
  final String planId;
  final String ownerUid;
  final ReminderItemType itemType;

  /// Tiêu đề hiển thị bên trong ứng dụng (đã mở khóa). Không dùng trực tiếp trên màn hình khóa.
  final String title;

  /// Thời điểm bắt đầu dự kiến (lưu theo UTC).
  final DateTime startsAtUtc;

  /// Thời điểm kết thúc dự kiến (tùy chọn, UTC).
  final DateTime? endsAtUtc;

  final PlanApprovalStatus planStatus;
  final PlanItemStatus itemStatus;
  final String? recommendationReason;
  final int version;

  ApprovedPlanReminderItem({
    required this.itemId,
    required this.planId,
    required this.ownerUid,
    required this.itemType,
    required this.title,
    required DateTime startsAt,
    DateTime? endsAt,
    required this.planStatus,
    required this.itemStatus,
    this.recommendationReason,
    this.version = 1,
  }) : startsAtUtc = startsAt.toUtc(),
       endsAtUtc = endsAt?.toUtc();

  /// Chỉ hợp lệ để tạo nhắc khi cả lịch tuần lẫn mục lịch đều đã được người dùng duyệt.
  bool get isEligibleForReminder =>
      planStatus == PlanApprovalStatus.approved &&
      itemStatus == PlanItemStatus.approved;

  /// Khóa chống trùng kết hợp giữa Local Notification và FCM cho đúng tài khoản và khung giờ.
  String get dedupeKey =>
      '$ownerUid:${itemType.name}:$itemId:${startsAtUtc.toIso8601String()}';

  ApprovedPlanReminderItem copyWith({
    String? itemId,
    String? planId,
    String? ownerUid,
    ReminderItemType? itemType,
    String? title,
    DateTime? startsAt,
    DateTime? endsAt,
    PlanApprovalStatus? planStatus,
    PlanItemStatus? itemStatus,
    String? recommendationReason,
    int? version,
  }) {
    return ApprovedPlanReminderItem(
      itemId: itemId ?? this.itemId,
      planId: planId ?? this.planId,
      ownerUid: ownerUid ?? this.ownerUid,
      itemType: itemType ?? this.itemType,
      title: title ?? this.title,
      startsAt: startsAt ?? startsAtUtc,
      endsAt: endsAt ?? endsAtUtc,
      planStatus: planStatus ?? this.planStatus,
      itemStatus: itemStatus ?? this.itemStatus,
      recommendationReason: recommendationReason ?? this.recommendationReason,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ApprovedPlanReminderItem &&
            other.itemId == itemId &&
            other.planId == planId &&
            other.ownerUid == ownerUid &&
            other.itemType == itemType &&
            other.title == title &&
            other.startsAtUtc == startsAtUtc &&
            other.endsAtUtc == endsAtUtc &&
            other.planStatus == planStatus &&
            other.itemStatus == itemStatus &&
            other.version == version);
  }

  @override
  int get hashCode => Object.hash(
    itemId,
    planId,
    ownerUid,
    itemType,
    title,
    startsAtUtc,
    endsAtUtc,
    planStatus,
    itemStatus,
    version,
  );
}
