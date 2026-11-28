import 'package:timezone/timezone.dart' as tz;

import '../../../profile/domain/profile_time.dart';
import '../../domain/entities/approved_plan_reminder_item.dart';
import '../../domain/entities/reminder_preferences.dart';

/// Dữ liệu mẫu cố định cho chế độ demo ngoại tuyến và kiểm thử Issue #6.
///
/// Bao gồm đầy đủ:
/// - Các mục trong **lịch đã duyệt (`approved`)** (trong đó có 1 mục rơi vào giờ yên lặng `22:30`
///   để minh họa tự động lùi sang `07:00` hôm sau).
/// - 1 mục trong **lịch nháp (`draft`)** để chứng minh hệ thống tuyệt đối KHÔNG đặt nhắc cho nháp.
/// - 1 mục **đã hoàn thành (`completed`)** để chứng minh không đặt nhắc thừa.
class SampleNotificationFixture {
  static ReminderPreferences defaultPreferences(String ownerUid) {
    return ReminderPreferences(
      ownerUid: ownerUid,
      remindersEnabled: true,
      quietHoursStartMinute: 22 * 60,
      quietHoursEndMinute: 7 * 60,
      timezone: defaultProfileZone,
      hideHealthDetailsOnLockScreen: true,
      defaultSnoozeMinutes: 10,
      version: 1,
    );
  }

  static List<ApprovedPlanReminderItem> createSamplePlanItems(
    String ownerUid, {
    DateTime? referenceDate,
    String timezone = defaultProfileZone,
  }) {
    final location =
        profileLocation(timezone) ??
        profileLocation(defaultProfileZone) ??
        tz.UTC;
    final anchor = tz.TZDateTime.from(
      (referenceDate ?? DateTime.now()).toUtc(),
      location,
    );
    // Đặt lịch mẫu vào ngày tiếp theo của anchor để mọi mục đều ở tương lai xác định.
    final nextDayYear = anchor.year;
    final nextDayMonth = anchor.month;
    final nextDay = anchor.day + 1;

    DateTime atClock(int hour, int minute) => tz.TZDateTime(
      location,
      nextDayYear,
      nextDayMonth,
      nextDay,
      hour,
      minute,
    ).toUtc();

    return [
      ApprovedPlanReminderItem(
        itemId: 'plan-item-habit-morning',
        planId: 'plan-approved-week-1',
        ownerUid: ownerUid,
        itemType: ReminderItemType.habit,
        title: 'Uống 1 cốc nước ấm sau khi thức dậy',
        startsAt: atClock(7, 30),
        endsAt: atClock(7, 45),
        planStatus: PlanApprovalStatus.approved,
        itemStatus: PlanItemStatus.approved,
        recommendationReason: 'Thói quen sáng nhẹ nhàng phù hợp lịch trình đã duyệt.',
      ),
      ApprovedPlanReminderItem(
        itemId: 'plan-item-exercise-afternoon',
        planId: 'plan-approved-week-1',
        ownerUid: ownerUid,
        itemType: ReminderItemType.exercise,
        title: 'Đi bộ nhanh 20 phút ngoài trời',
        startsAt: atClock(17, 30),
        endsAt: atClock(17, 50),
        planStatus: PlanApprovalStatus.approved,
        itemStatus: PlanItemStatus.approved,
        recommendationReason: 'Phù hợp khoảng trống sau giờ làm, không cần thiết bị.',
      ),
      ApprovedPlanReminderItem(
        itemId: 'plan-item-sleep-quiet-window',
        planId: 'plan-approved-week-1',
        ownerUid: ownerUid,
        itemType: ReminderItemType.sleep,
        title: 'Chuẩn bị thư giãn trước giờ ngủ',
        startsAt: atClock(22, 30),
        endsAt: atClock(23, 0),
        planStatus: PlanApprovalStatus.approved,
        itemStatus: PlanItemStatus.approved,
        recommendationReason: 'Kiểm chứng tự động dời qua khung giờ yên lặng 22:00–07:00.',
      ),
      ApprovedPlanReminderItem(
        itemId: 'plan-item-draft-unapproved',
        planId: 'plan-draft-week-2',
        ownerUid: ownerUid,
        itemType: ReminderItemType.meal,
        title: 'Bữa tối gợi ý (lịch nháp chưa duyệt)',
        startsAt: atClock(19, 0),
        endsAt: atClock(19, 30),
        planStatus: PlanApprovalStatus.draft,
        itemStatus: PlanItemStatus.draft,
        recommendationReason: 'Lịch nháp — không được đặt thông báo nhắc.',
      ),
      ApprovedPlanReminderItem(
        itemId: 'plan-item-completed-sample',
        planId: 'plan-approved-week-1',
        ownerUid: ownerUid,
        itemType: ReminderItemType.habit,
        title: 'Giãn cơ buổi trưa (đã hoàn thành)',
        startsAt: atClock(12, 15),
        endsAt: atClock(12, 30),
        planStatus: PlanApprovalStatus.approved,
        itemStatus: PlanItemStatus.completed,
      ),
    ];
  }
}
