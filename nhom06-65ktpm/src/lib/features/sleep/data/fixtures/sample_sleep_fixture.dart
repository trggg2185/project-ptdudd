import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/routine_block.dart';
import '../../domain/entities/sleep_log.dart';
import '../../domain/entities/sleep_window.dart';

/// Bộ dữ liệu mẫu (fixture) cho module Giấc ngủ & Lịch sinh hoạt (Issue #5).
///
/// Bao gồm cả kịch bản ngủ qua nửa đêm thông thường lẫn kịch bản ca đêm (22:00–06:00)
/// ngủ ban ngày (07:30–15:00) để minh họa rõ việc không ép mốc 22:00 cố định.
class SampleSleepFixture {
  /// Khoảng ngủ mong muốn mặc định cho bản demo (23:30 – 07:00, qua nửa đêm).
  static const SleepWindow defaultSleepWindow = SleepWindow(
    startMinute: 23 * 60 + 30,
    endMinute: 7 * 60,
    label: 'Lịch sinh viên linh hoạt',
  );

  /// Khoảng ngủ mong muốn cho kịch bản làm ca đêm (ngủ ban ngày 07:30 – 15:00).
  static const SleepWindow nightShiftSleepWindow = SleepWindow(
    startMinute: 7 * 60 + 30,
    endMinute: 15 * 60,
    label: 'Ca đêm — ngủ ban ngày',
  );

  /// Tạo danh sách nhật ký ngủ mẫu trong 7 ngày gần nhất cho [ownerUid].
  /// Chủ đích để trống 2 ngày để minh họa rõ ngày chưa ghi nhận không bị xem là thất bại.
  static List<SleepLog> createSampleLogs(
    String ownerUid, {
    DateTime? referenceDate,
  }) {
    final today = DateHelper.normalize(referenceDate ?? DateTime.now());
    final d1 = DateHelper.shiftDays(today, -1);
    final d2 = DateHelper.shiftDays(today, -2);
    final d3 = DateHelper.shiftDays(today, -3);
    final d5 = DateHelper.shiftDays(today, -5);
    final d6 = DateHelper.shiftDays(today, -6);

    return [
      // Đêm gần nhất: ngủ 23:40 hôm qua -> dậy 07:05 hôm nay (qua nửa đêm)
      SleepLog(
        id: 'sleep-sample-0001-0000-0000-000000000001',
        ownerUid: ownerUid,
        sleptAt: DateTime(d1.year, d1.month, d1.day, 23, 40),
        wokeAt: DateTime(today.year, today.month, today.day, 7, 5),
        alertness: AlertnessLevel.refreshed,
        note: 'Ngủ sâu, sáng dậy đúng giờ học.',
      ),
      // Đêm trước đó: bắt đầu sau nửa đêm 00:15 -> 07:15 (cùng ngày d1)
      SleepLog(
        id: 'sleep-sample-0001-0000-0000-000000000002',
        ownerUid: ownerUid,
        sleptAt: DateTime(d1.year, d1.month, d1.day, 0, 15),
        wokeAt: DateTime(d1.year, d1.month, d1.day, 7, 15),
        alertness: AlertnessLevel.neutral,
        note: 'Ôn bài muộn một chút nên ngủ sau 0 giờ.',
      ),
      // Ca đêm mẫu: ngủ ban ngày 07:45 -> 14:45 (hỗ trợ ca trực đêm 22:00–06:00)
      SleepLog(
        id: 'sleep-sample-0001-0000-0000-000000000003',
        ownerUid: ownerUid,
        sleptAt: DateTime(d2.year, d2.month, d2.day, 7, 45),
        wokeAt: DateTime(d2.year, d2.month, d2.day, 14, 45),
        alertness: AlertnessLevel.refreshed,
        note: 'Ngủ bù ban ngày sau ca trực đêm 22:00–06:00.',
      ),
      // 3 ngày trước: 23:15 -> 06:45 (qua nửa đêm)
      SleepLog(
        id: 'sleep-sample-0001-0000-0000-000000000004',
        ownerUid: ownerUid,
        sleptAt: DateTime(d3.year, d3.month, d3.day, 23, 15),
        wokeAt: DateTime(d2.year, d2.month, d2.day, 6, 45),
        alertness: AlertnessLevel.energized,
        note: 'Thư giãn trước khi ngủ, dậy rất tỉnh táo.',
      ),
      // 5 ngày trước: 23:50 -> 06:10 (qua nửa đêm, ngủ hơi ngắn)
      SleepLog(
        id: 'sleep-sample-0001-0000-0000-000000000005',
        ownerUid: ownerUid,
        sleptAt: DateTime(d6.year, d6.month, d6.day, 23, 50),
        wokeAt: DateTime(d5.year, d5.month, d5.day, 6, 10),
        alertness: AlertnessLevel.groggy,
        note: 'Dậy sớm đi thực tập nên hơi buồn ngủ.',
      ),
    ];
  }

  /// Tạo các khối lịch sinh hoạt mẫu (gồm cả lịch học ban ngày và ca đêm qua nửa đêm)
  /// xoay quanh [referenceDate] để minh họa giao diện lịch sinh hoạt 24 giờ responsive.
  static List<RoutineBlock> createSampleRoutineBlocks({
    DateTime? referenceDate,
    bool nightShiftMode = false,
  }) {
    final today = DateHelper.normalize(referenceDate ?? DateTime.now());
    final yesterday = DateHelper.shiftDays(today, -1);
    final tomorrow = DateHelper.shiftDays(today, 1);

    if (nightShiftMode) {
      return [
        // Ca trực đêm vắt qua nửa đêm: 22:00 hôm qua -> 06:00 hôm nay
        RoutineBlock(
          id: 'shift-night-prev',
          title: 'Ca trực đêm (22:00 – 06:00)',
          kind: RoutineBlockKind.workShift,
          startsAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 22, 0),
          endsAt: DateTime(today.year, today.month, today.day, 6, 0),
          travelMinutes: 20,
        ),
        // Ca trực đêm tiếp theo: 22:00 hôm nay -> 06:00 ngày mai
        RoutineBlock(
          id: 'shift-night-curr',
          title: 'Ca trực đêm (22:00 – 06:00)',
          kind: RoutineBlockKind.workShift,
          startsAt: DateTime(today.year, today.month, today.day, 22, 0),
          endsAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 6, 0),
          travelMinutes: 20,
        ),
        // Việc cá nhân buổi chiều sau khi ngủ dậy
        RoutineBlock(
          id: 'busy-afternoon',
          title: 'Chuẩn bị bữa ăn & giãn cơ',
          kind: RoutineBlockKind.busy,
          startsAt: DateTime(today.year, today.month, today.day, 16, 30),
          endsAt: DateTime(today.year, today.month, today.day, 18, 0),
        ),
      ];
    }

    return [
      RoutineBlock(
        id: 'busy-morning-class',
        title: 'Lớp học sáng',
        kind: RoutineBlockKind.busy,
        startsAt: DateTime(today.year, today.month, today.day, 8, 30),
        endsAt: DateTime(today.year, today.month, today.day, 11, 30),
        travelMinutes: 15,
      ),
      RoutineBlock(
        id: 'shift-afternoon-parttime',
        title: 'Ca làm bán thời gian',
        kind: RoutineBlockKind.workShift,
        startsAt: DateTime(today.year, today.month, today.day, 14, 0),
        endsAt: DateTime(today.year, today.month, today.day, 18, 30),
        travelMinutes: 20,
      ),
    ];
  }
}
