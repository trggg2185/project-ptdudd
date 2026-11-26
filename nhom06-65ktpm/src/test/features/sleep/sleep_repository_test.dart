import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/core/local_sync_worker.dart';
import 'package:healthylife/features/sleep/data/repositories/in_memory_sleep_repository.dart';
import 'package:healthylife/features/sleep/data/repositories/supabase_sleep_repository.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_log.dart';
import 'package:healthylife/features/sleep/domain/entities/sleep_window.dart';
import 'package:healthylife/features/sleep/domain/repositories/sleep_repository.dart';

class _RecordedSyncCall {
  final String operationId;
  final String ownerUid;
  final String entityType;
  final String recordId;
  final String operation;
  final Map<String, Object?>? payload;
  final int? baseVersion;

  const _RecordedSyncCall({
    required this.operationId,
    required this.ownerUid,
    required this.entityType,
    required this.recordId,
    required this.operation,
    required this.payload,
    required this.baseVersion,
  });
}

class _FakeSyncTransport implements SyncTransport {
  final List<_RecordedSyncCall> calls = [];
  SyncApplyResult Function(_RecordedSyncCall call)? handler;

  @override
  Future<SyncApplyResult> apply({
    required String operationId,
    required String ownerUid,
    required String entityType,
    required String recordId,
    required String operation,
    required Map<String, Object?>? payload,
    required int? baseVersion,
  }) async {
    final call = _RecordedSyncCall(
      operationId: operationId,
      ownerUid: ownerUid,
      entityType: entityType,
      recordId: recordId,
      operation: operation,
      payload: payload,
      baseVersion: baseVersion,
    );
    calls.add(call);
    if (handler != null) {
      return handler!(call);
    }
    return const SyncApplyResult(
      outcome: 'applied',
      serverVersion: 1,
      serverRecord: null,
    );
  }
}

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

    test('InMemorySleepRepository phát hiện xung đột baseVersion và seed nhất quán theo referenceDate', () async {
      final fixedRef = DateTime(2026, 11, 24, 18, 0);
      final seededRepo = InMemorySleepRepository(
        seedWithSamples: true,
        referenceDate: fixedRef,
      );

      // Gọi getSleepLogs trước -> vẫn dùng referenceDate nhất quán với getRoutineBlocks
      final seededLogs = await seededRepo.getSleepLogs(ownerUid: 'user-ref');
      final seededBlocks = await seededRepo.getRoutineBlocks(
        ownerUid: 'user-ref',
        referenceDate: fixedRef,
      );
      expect(seededLogs, isNotEmpty);
      expect(seededBlocks, isNotEmpty);
      expect(seededLogs.first.wokeAt.year, equals(2026));
      expect(seededLogs.first.wokeAt.month, equals(11));
      expect(seededLogs.first.wokeAt.day, equals(24));

      // Kiểm tra tăng version và chặn ghi đè khi baseVersion cũ
      final repo = InMemorySleepRepository(seedWithSamples: false);
      final created = await repo.saveSleepLog(
        SleepLog(
          id: 'log-ver-1',
          ownerUid: 'user-v',
          sleptAt: DateTime(2026, 11, 23, 23, 0),
          wokeAt: DateTime(2026, 11, 24, 7, 0),
          alertness: AlertnessLevel.refreshed,
        ),
      );
      expect(created.version, equals(1));

      final updated = await repo.saveSleepLog(
        created.copyWith(note: 'Cập nhật v2'),
        baseVersion: 1,
      );
      expect(updated.version, equals(2));

      await expectLater(
        () => repo.saveSleepLog(
          created.copyWith(note: 'Ghi đè bản cũ'),
          baseVersion: 1,
        ),
        throwsA(
          isA<SleepConflictException>()
              .having((e) => e.serverVersion, 'serverVersion', 2)
              .having((e) => e.serverLog?.note, 'serverLog.note', 'Cập nhật v2'),
        ),
      );

      await expectLater(
        () => repo.deleteSleepLog(
          ownerUid: 'user-v',
          logId: 'log-ver-1',
          baseVersion: 1,
        ),
        throwsA(isA<SleepConflictException>()),
      );
    });

    test('SupabaseSleepRepository ghi và xóa nhật ký qua SyncTransport (apply_log_sync) kèm xử lý xung đột', () async {
      final fakeTransport = _FakeSyncTransport();
      var opSeq = 0;
      final repo = SupabaseSleepRepository(
        syncTransport: fakeTransport,
        currentOwnerUid: () => 'firebase-user-duc',
        operationIdGenerator: () =>
            '00000000-0000-4000-8000-00000000000${++opSeq}',
      );

      final draft = SleepLog(
        id: '00000000-0000-4000-8000-000000000201',
        ownerUid: 'firebase-user-duc',
        sleptAt: DateTime(2026, 11, 23, 23, 30),
        wokeAt: DateTime(2026, 11, 24, 7, 0),
        alertness: AlertnessLevel.refreshed,
        note: 'Bản tạo mới',
      );

      // 1. Tạo mới -> operation='upsert', baseVersion=null, payload chỉ chứa các cột nghiệp vụ
      fakeTransport.handler = (call) => SyncApplyResult(
            outcome: 'applied',
            serverVersion: 1,
            serverRecord: {
              ...draft.toSupabaseMap(),
              'version': 1,
            },
          );

      final savedV1 = await repo.saveSleepLog(draft);
      expect(savedV1.version, equals(1));
      expect(fakeTransport.calls, hasLength(1));
      final createCall = fakeTransport.calls.single;
      expect(createCall.entityType, equals('sleep_log'));
      expect(createCall.operation, equals('upsert'));
      expect(createCall.baseVersion, isNull);
      expect(createCall.ownerUid, equals('firebase-user-duc'));
      expect(createCall.recordId, equals(draft.id));
      expect(createCall.payload?.containsKey('id'), isFalse);
      expect(createCall.payload?.containsKey('owner_uid'), isFalse);
      expect(createCall.payload?.containsKey('version'), isFalse);
      expect(createCall.payload?['feeling'], equals('refreshed'));

      // 2. Cập nhật gặp xung đột -> ném SleepConflictException kèm serverVersion & serverLog
      final remoteV2 = draft.copyWith(note: 'Sửa từ điện thoại khác', version: 2);
      fakeTransport.handler = (_) => SyncApplyResult(
            outcome: 'conflict',
            serverVersion: 2,
            serverRecord: remoteV2.toSupabaseMap(),
          );

      await expectLater(
        () => repo.saveSleepLog(savedV1.copyWith(note: 'Sửa cũ'), baseVersion: 1),
        throwsA(
          isA<SleepConflictException>()
              .having((e) => e.serverVersion, 'serverVersion', 2)
              .having((e) => e.serverLog?.note, 'serverLog.note', 'Sửa từ điện thoại khác'),
        ),
      );
      expect(fakeTransport.calls.last.baseVersion, equals(1));

      // 3. Xóa -> operation='delete', payload=null, baseVersion=2
      fakeTransport.handler = (_) => const SyncApplyResult(
            outcome: 'applied',
            serverVersion: 2,
            serverRecord: null,
          );
      await repo.deleteSleepLog(
        ownerUid: 'firebase-user-duc',
        logId: draft.id,
        baseVersion: 2,
      );
      final deleteCall = fakeTransport.calls.last;
      expect(deleteCall.entityType, equals('sleep_log'));
      expect(deleteCall.operation, equals('delete'));
      expect(deleteCall.payload, isNull);
      expect(deleteCall.baseVersion, equals(2));

      // 4. Xóa khi bản ghi đã đổi version -> SleepConflictException
      fakeTransport.handler = (_) => SyncApplyResult(
            outcome: 'conflict',
            serverVersion: 3,
            serverRecord: remoteV2.copyWith(version: 3).toSupabaseMap(),
          );
      await expectLater(
        () => repo.deleteSleepLog(
          ownerUid: 'firebase-user-duc',
          logId: draft.id,
          baseVersion: 2,
        ),
        throwsA(
          isA<SleepConflictException>()
              .having((e) => e.serverVersion, 'serverVersion', 3),
        ),
      );

      // 5. Conflict khi bản ghi đã bị xóa hẳn trên server (serverVersion == null, serverRecord == null)
      fakeTransport.handler = (_) => const SyncApplyResult(
            outcome: 'conflict',
            serverVersion: null,
            serverRecord: null,
          );
      await expectLater(
        () => repo.saveSleepLog(savedV1, baseVersion: 1),
        throwsA(
          isA<SleepConflictException>()
              .having((e) => e.serverVersion, 'serverVersion', isNull)
              .having((e) => e.serverLog, 'serverLog', isNull)
              .having((e) => e.message, 'message', contains('đã bị xóa')),
        ),
      );
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
