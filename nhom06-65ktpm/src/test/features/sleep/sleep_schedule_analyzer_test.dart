import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/sleep/domain/entities/routine_block.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_log.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_window.dart';
import 'package:healthylife/features/sleep/domain/logic/sleep_schedule_analyzer.dart';

void main() {
  group('SleepScheduleAnalyzer — nhập giờ qua ngày & ca đêm', () {
    const uid = 'firebase-uid-sleep-test';

    test('tự động chuyển ngày thức sang +1 ngày khi ngủ qua nửa đêm (23:30 → 07:00)', () {
      final startDay = DateTime(2026, 11, 23);
      final resolved = SleepScheduleAnalyzer.resolveSleepInterval(
        startDate: startDay,
        bedHour: 23,
        bedMinute: 30,
        wakeHour: 7,
        wakeMinute: 0,
      );

      expect(resolved.sleptAt, equals(DateTime(2026, 11, 23, 23, 30)));
      expect(resolved.wokeAt, equals(DateTime(2026, 11, 24, 7, 0)));
      expect(resolved.crossesMidnight, isTrue);
      expect(resolved.wokeAt.difference(resolved.sleptAt), equals(const Duration(hours: 7, minutes: 30)));
    });

    test('hỗ trợ ca đêm ngủ ban ngày trong cùng ngày (07:45 → 15:15)', () {
      final shiftDay = DateTime(2026, 11, 24);
      final resolved = SleepScheduleAnalyzer.resolveSleepInterval(
        startDate: shiftDay,
        bedHour: 7,
        bedMinute: 45,
        wakeHour: 15,
        wakeMinute: 15,
      );

      expect(resolved.sleptAt, equals(DateTime(2026, 11, 24, 7, 45)));
      expect(resolved.wokeAt, equals(DateTime(2026, 11, 24, 15, 15)));
      expect(resolved.crossesMidnight, isFalse);

      final log = SleepLog(
        id: 'log-night-shift',
        ownerUid: uid,
        sleptAt: resolved.sleptAt,
        wokeAt: resolved.wokeAt,
        alertness: AlertnessLevel.refreshed,
      );
      expect(log.isDaytimeSleep, isTrue);
      expect(log.formattedDuration, equals('7 giờ 30 phút'));
    });

    test('từ chối khi giờ đi ngủ trùng giờ thức dậy ở chế độ tự động', () {
      expect(
        () => SleepScheduleAnalyzer.resolveSleepInterval(
          startDate: DateTime(2026, 11, 24),
          bedHour: 23,
          bedMinute: 0,
          wakeHour: 23,
          wakeMinute: 0,
        ),
        throwsA(isA<SleepValidationException>()),
      );
    });

    test('validateSleepLog chặn wokeAt <= sleptAt, tương lai, >24h và chồng lấn', () {
      final now = DateTime(2026, 11, 24, 18, 0);

      // 1. wokeAt <= sleptAt
      expect(
        () => SleepScheduleAnalyzer.validateSleepLog(
          SleepLog(
            id: 'bad-order',
            ownerUid: uid,
            sleptAt: DateTime(2026, 11, 24, 8, 0),
            wokeAt: DateTime(2026, 11, 24, 7, 0),
          ),
          referenceNow: now,
        ),
        throwsA(isA<SleepValidationException>()),
      );

      // 2. Thời điểm tương lai
      expect(
        () => SleepScheduleAnalyzer.validateSleepLog(
          SleepLog(
            id: 'future-log',
            ownerUid: uid,
            sleptAt: DateTime(2026, 11, 24, 17, 0),
            wokeAt: DateTime(2026, 11, 25, 1, 0),
          ),
          referenceNow: now,
        ),
        throwsA(isA<SleepValidationException>()),
      );

      // 3. Quá 24 giờ
      expect(
        () => SleepScheduleAnalyzer.validateSleepLog(
          SleepLog(
            id: 'too-long',
            ownerUid: uid,
            sleptAt: DateTime(2026, 11, 22, 10, 0),
            wokeAt: DateTime(2026, 11, 23, 12, 0),
          ),
          referenceNow: now,
        ),
        throwsA(isA<SleepValidationException>()),
      );

      // 4. Chồng lấn với nhật ký đã tồn tại của cùng user
      final existing = [
        SleepLog(
          id: 'log-1',
          ownerUid: uid,
          sleptAt: DateTime(2026, 11, 23, 23, 0),
          wokeAt: DateTime(2026, 11, 24, 7, 0),
        ),
      ];
      expect(
        () => SleepScheduleAnalyzer.validateSleepLog(
          SleepLog(
            id: 'log-2',
            ownerUid: uid,
            sleptAt: DateTime(2026, 11, 24, 6, 30),
            wokeAt: DateTime(2026, 11, 24, 9, 0),
          ),
          existingLogs: existing,
          referenceNow: now,
        ),
        throwsA(isA<SleepValidationException>()),
      );

      // 5. Chỉnh sửa đúng bản ghi cũ (cùng id) không bị báo chồng lấn với chính nó
      expect(
        () => SleepScheduleAnalyzer.validateSleepLog(
          SleepLog(
            id: 'log-1',
            ownerUid: uid,
            sleptAt: DateTime(2026, 11, 23, 23, 15),
            wokeAt: DateTime(2026, 11, 24, 7, 15),
          ),
          existingLogs: existing,
          referenceNow: now,
        ),
        returnsNormally,
      );
    });
  });

  group('SleepScheduleAnalyzer — tách đoạn lịch 24h & ca đêm', () {
    test('tách chính xác ca đêm 22:00–06:00 và giấc ngủ 23:30–07:00 qua 2 ngày', () {
      final d1 = DateTime(2026, 11, 23);
      final d2 = DateTime(2026, 11, 24);

      final nightShiftSegments = SleepScheduleAnalyzer.splitIntervalAcrossDays(
        sourceId: 'shift-1',
        title: 'Ca trực đêm',
        kind: RoutineBlockKind.workShift,
        startsAt: DateTime(2026, 11, 23, 22, 0),
        endsAt: DateTime(2026, 11, 24, 6, 0),
      );

      expect(nightShiftSegments, hasLength(2));
      expect(nightShiftSegments[0].date, equals(d1));
      expect(nightShiftSegments[0].startMinute, equals(22 * 60));
      expect(nightShiftSegments[0].endMinute, equals(1440));
      expect(nightShiftSegments[0].continuesToNextDay, isTrue);
      expect(nightShiftSegments[0].continuedFromPreviousDay, isFalse);

      expect(nightShiftSegments[1].date, equals(d2));
      expect(nightShiftSegments[1].startMinute, equals(0));
      expect(nightShiftSegments[1].endMinute, equals(6 * 60));
      expect(nightShiftSegments[1].continuedFromPreviousDay, isTrue);
      expect(nightShiftSegments[1].continuesToNextDay, isFalse);
    });

    test('phát hiện xung đột khi khoảng ngủ đêm giao với ca trực đêm 22:00–06:00', () {
      final today = DateTime(2026, 11, 24);
      final nightShift = RoutineBlock(
        id: 'shift-night',
        title: 'Ca trực đêm',
        kind: RoutineBlockKind.workShift,
        startsAt: DateTime(2026, 11, 23, 22, 0),
        endsAt: DateTime(2026, 11, 24, 6, 0),
      );

      // Khoảng ngủ đêm 23:00–07:00 giao với ca đêm -> phải cảnh báo gợi ý
      final nightWindow = SleepWindow.fromHourMinute(
        startHour: 23,
        startMinute: 0,
        endHour: 7,
        endMinute: 0,
      );
      final conflicts = SleepScheduleAnalyzer.detectSleepWindowConflicts(
        targetDate: today,
        sleepWindow: nightWindow,
        routineBlocks: [nightShift],
      );
      expect(conflicts, isNotEmpty);

      // Đổi sang khoảng ngủ ban ngày 07:30–15:00 cho ca đêm -> không xung đột!
      final dayWindow = SleepWindow.fromHourMinute(
        startHour: 7,
        startMinute: 30,
        endHour: 15,
        endMinute: 0,
        label: 'Ca đêm — ngủ ban ngày',
      );
      final noConflicts = SleepScheduleAnalyzer.detectSleepWindowConflicts(
        targetDate: today,
        sleepWindow: dayWindow,
        routineBlocks: [nightShift],
      );
      expect(noConflicts, isEmpty);
    });
  });

  group('SleepScheduleAnalyzer — đồng hồ vòng tròn & thống kê tuần', () {
    const uid = 'firebase-uid-week';

    test('tính đúng khoảng cách đồng hồ vòng tròn qua nửa đêm (23:45 vs 00:15 = 30 phút)', () {
      expect(
        SleepScheduleAnalyzer.circularClockDistanceMinutes(23 * 60 + 45, 15),
        equals(30),
      );
      expect(
        SleepScheduleAnalyzer.circularClockDistanceMinutes(15, 23 * 60 + 45),
        equals(30),
      );
      expect(
        SleepScheduleAnalyzer.circularClockDistanceMinutes(8 * 60, 8 * 60 + 20),
        equals(20),
      );
    });

    test('không ép mốc 22:00: người ngủ đều theo khung ca đêm 08:00–15:30 đạt 100% đều đặn', () {
      final ref = DateTime(2026, 11, 24);
      final dayWindow = SleepWindow.fromHourMinute(
        startHour: 8,
        startMinute: 0,
        endHour: 15,
        endMinute: 30,
        label: 'Ca đêm',
      );
      final logs = [
        SleepLog(
          id: 'l1',
          ownerUid: uid,
          sleptAt: DateTime(2026, 11, 22, 8, 0),
          wokeAt: DateTime(2026, 11, 22, 15, 30),
          alertness: AlertnessLevel.refreshed,
        ),
        SleepLog(
          id: 'l2',
          ownerUid: uid,
          sleptAt: DateTime(2026, 11, 24, 8, 0),
          wokeAt: DateTime(2026, 11, 24, 15, 30),
          alertness: AlertnessLevel.energized,
        ),
      ];

      final summary = SleepScheduleAnalyzer.analyzeWeek(
        logs,
        sleepWindow: dayWindow,
        referenceDate: ref,
      );

      // 5 ngày không có log được giữ là chưa ghi nhận, không kéo giảm trung bình 7h30p
      expect(summary.days, hasLength(7));
      expect(summary.loggedDaysCount, equals(2));
      expect(summary.averageDuration, equals(const Duration(hours: 7, minutes: 30)));
      expect(summary.averageAlertnessScore, equals(4.5));
      expect(summary.averageBedtimeDeviationMinutes, equals(0));
      expect(summary.regularityScore, equals(100));
    });

    test('nhật ký ngủ bắt đầu 23:45 và 00:15 so với mục tiêu 00:00 chỉ lệch 15 phút', () {
      final ref = DateTime(2026, 11, 24);
      const midnightWindow = SleepWindow(startMinute: 0, endMinute: 7 * 60 + 30);
      final logs = [
        SleepLog(
          id: 'm1',
          ownerUid: uid,
          sleptAt: DateTime(2026, 11, 22, 23, 45),
          wokeAt: DateTime(2026, 11, 23, 7, 15),
          alertness: AlertnessLevel.refreshed,
        ),
        SleepLog(
          id: 'm2',
          ownerUid: uid,
          sleptAt: DateTime(2026, 11, 24, 0, 15),
          wokeAt: DateTime(2026, 11, 24, 7, 45),
          alertness: AlertnessLevel.refreshed,
        ),
      ];

      final summary = SleepScheduleAnalyzer.analyzeWeek(
        logs,
        sleepWindow: midnightWindow,
        referenceDate: ref,
      );

      expect(summary.averageBedtimeDeviationMinutes, equals(15));
      expect(summary.regularityScore, equals(95));
    });
  });
}
