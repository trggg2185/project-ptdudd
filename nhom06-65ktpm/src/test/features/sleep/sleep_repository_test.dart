import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/sleep/data/repositories/in_memory_sleep_repository.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_log.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_window.dart';

void main() {
  group('SleepRepository & Serialization Tests', () {
    test('InMemorySleepRepository cô lập hoàn toàn dữ liệu giữa hai tài khoản', () async {
      final repo = InMemorySleepRepository(seedWithSamples: false);

      final logA = SleepLog(
        id: 'log-a',
        ownerUid: 'firebase-user-a',
        sleptAt: DateTime(2026, 11, 23, 23, 0),
        wokeAt: DateTime(2026, 11, 24, 6, 30),
        alertness: AlertnessLevel.refreshed,
        note: 'Ngủ ngon',
      );
      await repo.saveSleepLog(logA);
      await repo.saveSleepWindow(
        ownerUid: 'firebase-user-a',
        window: SleepWindow.fromHourMinute(
          startHour: 23,
          startMinute: 0,
          endHour: 6,
          endMinute: 30,
        ),
      );

      expect(await repo.getSleepLogs(ownerUid: 'firebase-user-a'), hasLength(1));
      expect(await repo.getSleepLogs(ownerUid: 'firebase-user-b'), isEmpty);
      expect(await repo.getSleepWindow('firebase-user-a'), isNotNull);
      expect(await repo.getSleepWindow('firebase-user-b'), isNull);

      // User B xóa log-a không ảnh hưởng tới User A
      await repo.deleteSleepLog(ownerUid: 'firebase-user-b', logId: 'log-a');
      expect(await repo.getSleepLogs(ownerUid: 'firebase-user-a'), hasLength(1));

      // User A xóa log-a thành công
      await repo.deleteSleepLog(ownerUid: 'firebase-user-a', logId: 'log-a');
      expect(await repo.getSleepLogs(ownerUid: 'firebase-user-a'), isEmpty);
    });

    test('SleepLog toSupabaseMap / fromSupabaseMap giữ nguyên UTC và trường bảng sleep_logs', () {
      final original = SleepLog(
        id: '00000000-0000-4000-8000-000000000101',
        ownerUid: 'firebase-user-duc',
        sleptAt: DateTime(2026, 11, 23, 23, 30),
        wokeAt: DateTime(2026, 11, 24, 7, 15),
        alertness: AlertnessLevel.energized,
        note: 'Sáng dậy rất tỉnh táo',
        version: 2,
      );

      final map = original.toSupabaseMap();
      expect(map['id'], equals(original.id));
      expect(map['owner_uid'], equals('firebase-user-duc'));
      expect(map['feeling'], equals('energized'));
      expect(map['note'], equals('Sáng dậy rất tỉnh táo'));
      expect(map['version'], equals(2));
      expect((map['slept_at'] as String).endsWith('Z'), isTrue);
      expect((map['woke_at'] as String).endsWith('Z'), isTrue);

      final restored = SleepLog.fromSupabaseMap(map);
      expect(restored, equals(original));
      expect(restored.crossesMidnight, isTrue);
      expect(restored.durationMinutes, equals(465));
    });

    test('SleepWindow tương thích cấu trúc sleep_start/sleep_end trong profiles.living_conditions', () {
      final nightShiftWindow = SleepWindow.fromHourMinute(
        startHour: 7,
        startMinute: 30,
        endHour: 15,
        endMinute: 0,
        label: 'Ca đêm',
      );

      final patch = nightShiftWindow.toProfilePreferencePatch();
      expect(patch['sleep_start'], equals(450));
      expect(patch['sleep_end'], equals(900));
      expect(patch['sleep_label'], equals('Ca đêm'));

      final restored = SleepWindow.fromProfilePreferences(patch);
      expect(restored, equals(nightShiftWindow));
      expect(restored?.isDaytimeWindow, isTrue);
      expect(restored?.durationMinutes, equals(450));
    });
  });
}
