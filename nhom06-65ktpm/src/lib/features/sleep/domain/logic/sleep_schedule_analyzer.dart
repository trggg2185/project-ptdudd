import 'dart:math';

import '../../../../core/utils/date_helper.dart';
import '../entities/routine_block.dart';
import '../entities/sleep_log.dart';
import '../entities/sleep_window.dart';

/// Ngoại lệ xác thực nghiệp vụ cho dữ liệu giấc ngủ và khoảng ngủ mong muốn.
class SleepValidationException implements Exception {
  final String message;

  const SleepValidationException(this.message);

  @override
  String toString() => message;
}

/// Trạng thái ghi nhận giấc ngủ của một ngày trong biểu đồ 7 ngày.
///
/// Ngày không có dữ liệu (`hasData == false`) chỉ mang ý nghĩa "Chưa ghi nhận",
/// tuyệt đối không bị đánh dấu là thất bại hay tính là 0 giờ ngủ.
class DailySleepSummary {
  final DateTime date;
  final List<SleepLog> logs;

  const DailySleepSummary({required this.date, required this.logs});

  bool get hasData => logs.isNotEmpty;

  int get totalMinutes =>
      logs.fold<int>(0, (sum, log) => sum + log.durationMinutes);

  Duration get totalDuration => Duration(minutes: totalMinutes);

  double? get averageAlertness {
    if (logs.isEmpty) return null;
    final total = logs.fold<int>(0, (sum, log) => sum + log.alertness.score);
    return total / logs.length;
  }
}

/// Tổng hợp tính đều đặn và mức tỉnh táo theo tuần (7 ngày gần nhất).
class SleepWeeklySummary {
  final List<DailySleepSummary> days;
  final int loggedDaysCount;
  final int totalLogsCount;
  final Duration? averageDuration;
  final double? averageAlertnessScore;

  /// Độ lệch giờ đi ngủ trung bình (phút) theo khoảng cách đồng hồ vòng tròn
  /// so với `SleepWindow` do người dùng tự đặt (null nếu chưa đặt khoảng ngủ).
  final int? averageBedtimeDeviationMinutes;

  /// Điểm đều đặn tương đối (0–100) dựa trên khoảng ngủ người dùng tự chọn hoặc độ ổn định cá nhân.
  final int? regularityScore;

  const SleepWeeklySummary({
    required this.days,
    required this.loggedDaysCount,
    required this.totalLogsCount,
    this.averageDuration,
    this.averageAlertnessScore,
    this.averageBedtimeDeviationMinutes,
    this.regularityScore,
  });

  String get formattedAverageDuration {
    final avg = averageDuration;
    if (avg == null) return 'Chưa có dữ liệu';
    final totalMins = avg.inMinutes;
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    if (m == 0) return '$h giờ';
    return '$h giờ $m phút';
  }
}

/// Bộ xử lý nghiệp vụ cốt lõi cho Nhật ký ngủ & Lịch sinh hoạt (Issue #5).
///
/// Quy tắc cốt lõi:
/// 1. Hỗ trợ nhập giờ qua nửa đêm (tự động chuyển ngày thức sang +1 ngày khi giờ thức <= giờ ngủ)
///    và hỗ trợ ngủ ban ngày cho người làm ca đêm (ví dụ 07:30–15:00).
/// 2. Không suy ra giấc ngủ thật từ việc không dùng điện thoại; không ép mốc 22:00 cố định.
/// 3. Cắt đoạn qua nửa đêm chính xác trên lịch sinh hoạt 24 giờ cho cả ca đêm và giấc ngủ.
/// 4. Tính độ lệch theo đồng hồ vòng tròn (23:45 vs 00:15 = lệch 30 phút).
/// 5. Ngày thiếu dữ liệu được hiển thị trung tính là "Chưa ghi nhận", không coi là thất bại.
class SleepScheduleAnalyzer {
  static const int maxSingleSleepMinutes = 24 * 60;
  static const int minWindowMinutes = 60;
  static const int maxWindowMinutes = 16 * 60;

  /// Tính cặp `(sleptAt, wokeAt)` từ ngày bắt đầu ngủ, giờ đi ngủ và giờ thức dậy.
  ///
  /// - Nếu [explicitWakeDate] được truyền: dùng chính xác ngày đó.
  /// - Nếu [explicitWakeDate] là null:
  ///   - Khi giờ thức < giờ ngủ (ví dụ 23:30 → 07:00): tự động chuyển ngày thức sang ngày kế tiếp (+1 ngày).
  ///   - Khi giờ thức > giờ ngủ (ví dụ ca đêm 08:00 → 15:30): cùng ngày.
  ///   - Khi giờ thức == giờ ngủ: ném [SleepValidationException] để tránh nhầm 0 phút hoặc 24 giờ.
  static ({DateTime sleptAt, DateTime wokeAt, bool crossesMidnight})
  resolveSleepInterval({
    required DateTime startDate,
    required int bedHour,
    required int bedMinute,
    required int wakeHour,
    required int wakeMinute,
    DateTime? explicitWakeDate,
  }) {
    _validateClockParts(bedHour, bedMinute, 'Giờ đi ngủ');
    _validateClockParts(wakeHour, wakeMinute, 'Giờ thức dậy');

    final normStart = DateHelper.normalize(startDate);
    final sleptAt = DateTime(
      normStart.year,
      normStart.month,
      normStart.day,
      bedHour,
      bedMinute,
    );

    final DateTime wokeAt;
    if (explicitWakeDate != null) {
      final normWake = DateHelper.normalize(explicitWakeDate);
      wokeAt = DateTime(
        normWake.year,
        normWake.month,
        normWake.day,
        wakeHour,
        wakeMinute,
      );
    } else {
      final bedTotal = bedHour * 60 + bedMinute;
      final wakeTotal = wakeHour * 60 + wakeMinute;
      if (wakeTotal == bedTotal) {
        throw const SleepValidationException(
          'Giờ thức dậy không được trùng giờ đi ngủ.',
        );
      }
      final targetWakeDate = wakeTotal < bedTotal
          ? DateHelper.shiftDays(normStart, 1)
          : normStart;
      wokeAt = DateTime(
        targetWakeDate.year,
        targetWakeDate.month,
        targetWakeDate.day,
        wakeHour,
        wakeMinute,
      );
    }

    return (
      sleptAt: sleptAt,
      wokeAt: wokeAt,
      crossesMidnight: !DateHelper.isSameDay(sleptAt, wokeAt),
    );
  }

  static void _validateClockParts(int hour, int minute, String fieldName) {
    if (hour < 0 || hour > 23) {
      throw SleepValidationException('$fieldName phải có giờ từ 0 đến 23.');
    }
    if (minute < 0 || minute > 59) {
      throw SleepValidationException('$fieldName phải có phút từ 0 đến 59.');
    }
  }

  /// Xác thực đầy đủ một bản ghi [SleepLog] trước khi lưu.
  static void validateSleepLog(
    SleepLog log, {
    List<SleepLog> existingLogs = const [],
    DateTime? referenceNow,
  }) {
    if (log.ownerUid.trim().isEmpty) {
      throw const SleepValidationException(
        'Thiếu thông tin tài khoản người dùng.',
      );
    }
    if (!log.wokeAt.isAfter(log.sleptAt)) {
      throw const SleepValidationException('Giờ thức dậy phải sau giờ đi ngủ.');
    }
    final durationMins = log.durationMinutes;
    if (durationMins <= 0) {
      throw const SleepValidationException(
        'Thời lượng giấc ngủ phải lớn hơn 0 phút.',
      );
    }
    if (durationMins > maxSingleSleepMinutes) {
      throw const SleepValidationException(
        'Thời lượng một bản ghi ngủ không được vượt quá 24 giờ. Vui lòng kiểm tra lại ngày ngủ/thức.',
      );
    }

    final now = referenceNow ?? DateTime.now();
    // Cho phép sai số nhỏ 1 phút do độ trễ đồng hồ khi vừa chọn giờ hiện tại
    final upperBound = now.add(const Duration(minutes: 1));
    if (log.sleptAt.isAfter(upperBound) || log.wokeAt.isAfter(upperBound)) {
      throw const SleepValidationException(
        'Không thể ghi nhận nhật ký giấc ngủ cho thời điểm trong tương lai.',
      );
    }

    for (final existing in existingLogs) {
      if (existing.id == log.id) continue;
      if (existing.ownerUid != log.ownerUid) continue;
      if (intervalsOverlap(
        log.sleptAt,
        log.wokeAt,
        existing.sleptAt,
        existing.wokeAt,
      )) {
        throw const SleepValidationException(
          'Khoảng thời gian ngủ bị chồng lấn với một bản ghi đã lưu trước đó.',
        );
      }
    }
  }

  /// Xác thực khoảng ngủ mong muốn [SleepWindow].
  /// Không áp đặt mốc giờ cố định (không ép 22:00); chấp nhận mọi khung giờ hợp lệ kể cả ca đêm.
  static void validateSleepWindow(SleepWindow window) {
    if (!SleepWindow.isValidClockMinute(window.startMinute) ||
        !SleepWindow.isValidClockMinute(window.endMinute)) {
      throw const SleepValidationException(
        'Giờ ngủ/thức mong muốn nằm ngoài khoảng hợp lệ (00:00 – 23:59).',
      );
    }
    if (window.startMinute == window.endMinute) {
      throw const SleepValidationException(
        'Giờ đi ngủ và giờ thức dậy mong muốn phải khác nhau.',
      );
    }
    final mins = window.durationMinutes;
    if (mins < minWindowMinutes || mins > maxWindowMinutes) {
      throw const SleepValidationException(
        'Khoảng ngủ mong muốn nên nằm trong khoảng từ 1 đến 16 giờ.',
      );
    }
  }

  /// Kiểm tra hai khoảng thời gian nửa mở `[startA, endA)` và `[startB, endB)` có chồng lấn không.
  static bool intervalsOverlap(
    DateTime startA,
    DateTime endA,
    DateTime startB,
    DateTime endB,
  ) {
    return startA.isBefore(endB) && startB.isBefore(endA);
  }

  /// Khoảng cách nhỏ nhất giữa hai mốc giờ trong ngày theo đồng hồ vòng tròn 24 giờ (0..720 phút).
  ///
  /// Ví dụ: 23:45 (1425) và 00:15 (15) lệch nhau 30 phút, không phải 1410 phút.
  static int circularClockDistanceMinutes(int minuteA, int minuteB) {
    final normA = ((minuteA % 1440) + 1440) % 1440;
    final normB = ((minuteB % 1440) + 1440) % 1440;
    final diff = (normA - normB).abs();
    return min(diff, 1440 - diff);
  }

  /// Tách một khoảng thời gian bất kỳ `[startsAt, endsAt]` thành từng đoạn theo ngày lịch địa phương.
  static List<DailyTimelineSegment> splitIntervalAcrossDays({
    required String sourceId,
    required String title,
    required RoutineBlockKind kind,
    required DateTime startsAt,
    required DateTime endsAt,
    String? subtitle,
  }) {
    final localStart = startsAt.toLocal();
    final localEnd = endsAt.toLocal();
    if (!localEnd.isAfter(localStart)) return const [];

    final segments = <DailyTimelineSegment>[];
    var cursorDay = DateHelper.normalize(localStart);

    while (cursorDay.isBefore(localEnd)) {
      final nextDay = DateHelper.shiftDays(cursorDay, 1);
      final segStart = localStart.isAfter(cursorDay) ? localStart : cursorDay;
      final segEnd = localEnd.isBefore(nextDay) ? localEnd : nextDay;

      final startMin = segStart == cursorDay
          ? 0
          : segStart.hour * 60 + segStart.minute;
      final endMin = segEnd == nextDay
          ? 1440
          : segEnd.hour * 60 + segEnd.minute;

      if (endMin > startMin) {
        segments.add(
          DailyTimelineSegment(
            sourceId: sourceId,
            title: title,
            kind: kind,
            date: cursorDay,
            startMinute: startMin,
            endMinute: endMin,
            continuedFromPreviousDay:
                segStart == cursorDay && localStart.isBefore(cursorDay),
            continuesToNextDay: segEnd == nextDay && localEnd.isAfter(nextDay),
            subtitle: subtitle,
          ),
        );
      }
      cursorDay = nextDay;
    }

    return segments;
  }

  /// Tổng hợp toàn bộ các đoạn lịch sinh hoạt 24 giờ trên ngày [targetDate],
  /// bao gồm: ca làm/lịch bận, khoảng ngủ mong muốn và giấc ngủ đã ghi nhận (có tách qua nửa đêm).
  static List<DailyTimelineSegment> buildSegmentsForDate({
    required DateTime targetDate,
    required List<SleepLog> sleepLogs,
    List<RoutineBlock> routineBlocks = const [],
    SleepWindow? sleepWindow,
  }) {
    final normDate = DateHelper.normalize(targetDate);
    final result = <DailyTimelineSegment>[];

    // 1. Chiếu khoảng ngủ mong muốn lên ngày targetDate
    if (sleepWindow != null) {
      final label = (sleepWindow.label != null && sleepWindow.label!.isNotEmpty)
          ? 'Mục tiêu ngủ: ${sleepWindow.label}'
          : 'Khoảng ngủ mong muốn';

      if (sleepWindow.crossesMidnight) {
        // Đoạn sáng từ 00:00 -> endMinute (tiếp nối từ tối hôm trước)
        if (sleepWindow.endMinute > 0) {
          result.add(
            DailyTimelineSegment(
              sourceId: 'sleep-window-morning',
              title: label,
              kind: RoutineBlockKind.sleepTarget,
              date: normDate,
              startMinute: 0,
              endMinute: sleepWindow.endMinute,
              continuedFromPreviousDay: true,
              subtitle: sleepWindow.formattedRange,
            ),
          );
        }
        // Đoạn tối từ startMinute -> 24:00 (kéo sang sáng hôm sau)
        if (sleepWindow.startMinute < 1440) {
          result.add(
            DailyTimelineSegment(
              sourceId: 'sleep-window-evening',
              title: label,
              kind: RoutineBlockKind.sleepTarget,
              date: normDate,
              startMinute: sleepWindow.startMinute,
              endMinute: 1440,
              continuesToNextDay: true,
              subtitle: sleepWindow.formattedRange,
            ),
          );
        }
      } else {
        // Ngủ trọn trong ngày (ví dụ ca đêm 07:30 – 15:00)
        result.add(
          DailyTimelineSegment(
            sourceId: 'sleep-window-daytime',
            title: label,
            kind: RoutineBlockKind.sleepTarget,
            date: normDate,
            startMinute: sleepWindow.startMinute,
            endMinute: sleepWindow.endMinute,
            subtitle:
                '${sleepWindow.formattedRange} (${sleepWindow.formattedDuration})',
          ),
        );
      }
    }

    // 2. Cắt các khối ca làm việc / khoảng bận (hỗ trợ ca đêm 22:00–06:00 qua ngày)
    for (final block in routineBlocks) {
      for (final interval in block.intervalsForDay(normDate)) {
        final segments = splitIntervalAcrossDays(
          sourceId: block.id,
          title: block.title,
          kind: block.kind,
          startsAt: interval.start,
          endsAt: interval.end,
          subtitle: block.travelMinutes > 0
              ? 'Di chuyển ~${block.travelMinutes} phút'
              : null,
        );
        result.addAll(
          segments.where((seg) => DateHelper.isSameDay(seg.date, normDate)),
        );
      }
    }

    // 3. Cắt các nhật ký ngủ thực tế (hỗ trợ ngủ qua nửa đêm)
    for (final log in sleepLogs) {
      final segments = splitIntervalAcrossDays(
        sourceId: log.id,
        title: 'Giấc ngủ (${log.formattedDuration})',
        kind: RoutineBlockKind.sleepLogged,
        startsAt: log.sleptAt,
        endsAt: log.wokeAt,
        subtitle: 'Tỉnh táo: ${log.alertness.label}',
      );
      for (final seg in segments) {
        if (DateHelper.isSameDay(seg.date, normDate)) {
          result.add(seg);
        }
      }
    }

    result.sort((a, b) {
      final cmp = a.startMinute.compareTo(b.startMinute);
      if (cmp != 0) return cmp;
      return a.kind.index.compareTo(b.kind.index);
    });
    return result;
  }

  /// Phát hiện xung đột giữa khoảng ngủ mong muốn và ca làm việc/khoảng bận trong ngày [targetDate].
  ///
  /// Trả về danh sách cảnh báo mang tính gợi ý để người làm ca đêm dễ điều chỉnh khoảng ngủ phù hợp.
  static List<String> detectSleepWindowConflicts({
    required DateTime targetDate,
    required SleepWindow? sleepWindow,
    required List<RoutineBlock> routineBlocks,
  }) {
    if (sleepWindow == null || routineBlocks.isEmpty) return const [];

    final segments = buildSegmentsForDate(
      targetDate: targetDate,
      sleepLogs: const [],
      routineBlocks: routineBlocks,
      sleepWindow: sleepWindow,
    );

    final targetSegs = segments
        .where((s) => s.kind == RoutineBlockKind.sleepTarget)
        .toList();
    final busySegs = segments
        .where(
          (s) =>
              s.kind == RoutineBlockKind.workShift ||
              s.kind == RoutineBlockKind.busy,
        )
        .toList();

    final warnings = <String>{};
    for (final sleepSeg in targetSegs) {
      for (final busySeg in busySegs) {
        final overlaps =
            sleepSeg.startMinute < busySeg.endMinute &&
            busySeg.startMinute < sleepSeg.endMinute;
        if (overlaps) {
          warnings.add(
            'Khoảng ngủ mong muốn (${sleepWindow.formattedRange}) đang giao với "${busySeg.title}" (${busySeg.formattedRange}). Bạn có thể đổi sang khung ngủ phù hợp hơn với ca làm.',
          );
        }
      }
    }

    return warnings.toList();
  }

  /// Phân tích tính đều đặn và thống kê giấc ngủ trong 7 ngày gần nhất kết thúc ở [referenceDate].
  ///
  /// - Gắn mỗi nhật ký ngủ vào ngày thức dậy (`wakeDate`) để giấc ngủ bắt đầu lúc 23:30
  ///   và giấc ngủ bắt đầu lúc 00:30 đều thuộc cùng chu kỳ ngày sáng hôm sau.
  /// - Bỏ qua mọi bản ghi ở tương lai so với [referenceDate].
  /// - Ngày chưa có dữ liệu không bị xem là thất bại và không kéo giảm trung bình.
  static SleepWeeklySummary analyzeWeek(
    List<SleepLog> logs, {
    SleepWindow? sleepWindow,
    DateTime? referenceDate,
  }) {
    final ref = DateHelper.normalize(referenceDate ?? DateTime.now());
    final weekStart = DateHelper.shiftDays(ref, -6);

    // Lọc các bản ghi nằm trong khoảng 7 ngày [weekStart..ref] theo wakeDate
    final validLogs = <SleepLog>[];
    final byDate = <String, List<SleepLog>>{};

    for (final log in logs) {
      final wakeDay = log.wakeDate;
      if (wakeDay.isAfter(ref) || wakeDay.isBefore(weekStart)) continue;
      validLogs.add(log);
      final key = DateHelper.formatIsoDate(wakeDay);
      byDate.putIfAbsent(key, () => []).add(log);
    }

    final days = List<DailySleepSummary>.generate(7, (index) {
      final day = DateHelper.shiftDays(weekStart, index);
      final key = DateHelper.formatIsoDate(day);
      final dayLogs = List<SleepLog>.from(byDate[key] ?? const [])
        ..sort((a, b) => a.sleptAt.compareTo(b.sleptAt));
      return DailySleepSummary(date: day, logs: dayLogs);
    });

    final loggedDays = days.where((d) => d.hasData).toList();
    if (validLogs.isEmpty) {
      return SleepWeeklySummary(
        days: days,
        loggedDaysCount: 0,
        totalLogsCount: 0,
      );
    }

    // Trung bình tổng thời lượng ngủ theo từng ngày có ghi nhận
    final totalMinutesAllLoggedDays = loggedDays.fold<int>(
      0,
      (sum, d) => sum + d.totalMinutes,
    );
    final avgMinutes = (totalMinutesAllLoggedDays / loggedDays.length).round();

    // Trung bình mức tỉnh táo tự đánh giá
    final totalAlertness = validLogs.fold<int>(
      0,
      (sum, log) => sum + log.alertness.score,
    );
    final avgAlertness = totalAlertness / validLogs.length;

    // Tính độ lệch giờ đi ngủ theo đồng hồ vòng tròn
    int? avgBedtimeDeviation;
    int? regularityScore;

    if (sleepWindow != null) {
      var totalDev = 0;
      for (final log in validLogs) {
        final localStart = log.sleptAt.toLocal();
        final startMin = localStart.hour * 60 + localStart.minute;
        totalDev += circularClockDistanceMinutes(
          startMin,
          sleepWindow.startMinute,
        );
      }
      avgBedtimeDeviation = (totalDev / validLogs.length).round();
      // Lệch 0 phút => 100 điểm; mỗi 3 phút lệch trung bình trừ 1 điểm (tối thiểu 0)
      regularityScore = max(
        0,
        min(100, 100 - (avgBedtimeDeviation / 3).round()),
      );
    } else if (validLogs.length >= 2) {
      // Không có khoảng ngủ mục tiêu: tính độ ổn định dựa trên chênh lệch cặp giờ đi ngủ liền kề
      final sorted = List<SleepLog>.from(validLogs)
        ..sort((a, b) => a.sleptAt.compareTo(b.sleptAt));
      var pairwiseDiffSum = 0;
      for (var i = 1; i < sorted.length; i++) {
        final prevStart = sorted[i - 1].sleptAt.toLocal();
        final currStart = sorted[i].sleptAt.toLocal();
        pairwiseDiffSum += circularClockDistanceMinutes(
          prevStart.hour * 60 + prevStart.minute,
          currStart.hour * 60 + currStart.minute,
        );
      }
      final avgSpread = (pairwiseDiffSum / (sorted.length - 1)).round();
      regularityScore = max(0, min(100, 100 - (avgSpread / 3).round()));
    }

    return SleepWeeklySummary(
      days: days,
      loggedDaysCount: loggedDays.length,
      totalLogsCount: validLogs.length,
      averageDuration: Duration(minutes: avgMinutes),
      averageAlertnessScore: avgAlertness,
      averageBedtimeDeviationMinutes: avgBedtimeDeviation,
      regularityScore: regularityScore,
    );
  }
}
