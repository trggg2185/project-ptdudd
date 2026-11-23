import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/core/local_database.dart';
import 'package:healthylife/core/local_sync_worker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase localDatabase;
  late _FakeSyncTransport transport;
  late LocalSyncWorker worker;

  setUp(() {
    localDatabase = LocalDatabase(databasePath: inMemoryDatabasePath);
    transport = _FakeSyncTransport();
    worker = LocalSyncWorker(
      localDatabase: localDatabase,
      transport: transport,
    );
  });

  tearDown(() async {
    await localDatabase.close();
  });

  test(
    'retries an applied request idempotently after its response is lost',
    () async {
      await localDatabase.upsertRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'habit_log',
        recordId: _id(1),
        payload: {
          'habit_id': _id(2),
          'local_date': '2026-11-22',
          'result': 'completed',
        },
        operationId: _id(3),
      );
      transport.loseNextResponseAfterApply = true;

      await expectLater(
        worker.flush('firebase-user-a'),
        throwsA(isA<SyncTransportException>()),
      );
      expect(
        await localDatabase.getPendingChanges('firebase-user-a'),
        hasLength(1),
      );
      expect(transport.records, hasLength(1));

      expect(await worker.flush('firebase-user-a'), 1);

      expect(transport.records, hasLength(1));
      expect(await localDatabase.getPendingChanges('firebase-user-a'), isEmpty);
      expect(transport.applyCount, 1);
    },
  );

  test('queues offline changes and syncs them after reconnecting', () async {
    final operationId = await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'meal_log',
      recordId: _id(5),
      payload: {'meal_name': 'offline meal'},
    );
    transport.failNextBeforeApply = true;

    await expectLater(
      worker.flush('firebase-user-a'),
      throwsA(isA<SyncTransportException>()),
    );

    final pendingWhileOffline = await localDatabase.getPendingChanges(
      'firebase-user-a',
    );
    expect(pendingWhileOffline, hasLength(1));
    expect(pendingWhileOffline.single['operation_id'], operationId);
    expect(pendingWhileOffline.single['attempt_count'], 1);
    expect(
      pendingWhileOffline.single['last_error_code'],
      'network_unavailable',
    );
    expect(transport.records, isEmpty);

    expect(await worker.flush('firebase-user-a'), 1);

    expect(transport.operationIds, [operationId, operationId]);
    expect(transport.records.values.single['meal_name'], 'offline meal');
    expect(await localDatabase.getPendingChanges('firebase-user-a'), isEmpty);
  });

  test('does not overwrite a newer change from another device', () async {
    transport.seed(
      ownerUid: 'firebase-user-a',
      entityType: 'meal_log',
      recordId: _id(10),
      version: 1,
      payload: {'meal_name': 'server v1'},
    );
    await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'meal_log',
      recordId: _id(10),
      payload: {'meal_name': 'device A'},
      baseVersion: 1,
      operationId: _id(11),
    );
    await worker.flush('firebase-user-a');

    final deviceBDatabase = LocalDatabase(databasePath: inMemoryDatabasePath);
    final deviceBWorker = LocalSyncWorker(
      localDatabase: deviceBDatabase,
      transport: transport,
    );
    await deviceBDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'meal_log',
      recordId: _id(10),
      payload: {'meal_name': 'device B'},
      baseVersion: 1,
      operationId: _id(12),
    );

    SyncConflictException? conflict;
    try {
      await deviceBWorker.flush('firebase-user-a');
    } on SyncConflictException catch (error) {
      conflict = error;
    }
    final deviceBPending = await deviceBDatabase.getPendingChanges(
      'firebase-user-a',
    );
    await deviceBDatabase.close();

    expect(conflict, isNotNull);
    expect(conflict!.serverVersion, 2);
    expect(conflict.serverRecord?['meal_name'], 'device A');
    expect(transport.records.values.single['meal_name'], 'device A');
    expect(deviceBPending, hasLength(1));
  });

  test(
    'keeps local edits only after rebasing onto the server version',
    () async {
      transport.seed(
        ownerUid: 'firebase-user-a',
        entityType: 'meal_log',
        recordId: _id(20),
        version: 2,
        payload: {'meal_name': 'newer server change'},
      );
      await localDatabase.upsertRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'meal_log',
        recordId: _id(20),
        payload: {'meal_name': 'local change'},
        baseVersion: 1,
        operationId: _id(21),
      );

      SyncConflictException? conflict;
      try {
        await worker.flush('firebase-user-a');
      } on SyncConflictException catch (error) {
        conflict = error;
      }
      expect(conflict, isNotNull);
      expect(
        transport.records.values.single['meal_name'],
        'newer server change',
      );

      final rebasedOperationId = await worker.keepLocalChanges(conflict!);
      expect(rebasedOperationId, isNot(_id(21)));
      expect(
        await localDatabase.getPendingChanges('firebase-user-a'),
        hasLength(1),
      );

      expect(await worker.flush('firebase-user-a'), 1);

      expect(transport.records.values.single['meal_name'], 'local change');
      expect(transport.records.values.single['version'], 3);
      expect(await localDatabase.getPendingChanges('firebase-user-a'), isEmpty);
    },
  );

  test(
    'accepts the server copy when independently-created habit logs collide',
    () async {
      await localDatabase.upsertRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'habit_log',
        recordId: _id(30),
        payload: {
          'habit_id': _id(31),
          'local_date': '2026-11-22',
          'result': 'completed',
        },
        operationId: _id(32),
      );
      await localDatabase.upsertRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'habit_log',
        recordId: _id(33),
        payload: {
          'habit_id': _id(31),
          'local_date': '2026-11-22',
          'result': 'skipped',
        },
        operationId: _id(34),
      );

      SyncConflictException? conflict;
      try {
        await worker.flush('firebase-user-a');
      } on SyncConflictException catch (error) {
        conflict = error;
      }
      expect(conflict, isNotNull);
      expect(transport.records, hasLength(1));

      await worker.acceptServerChange(conflict!);

      expect(await localDatabase.getPendingChanges('firebase-user-a'), isEmpty);
      expect(
        await localDatabase.getRecord(
          ownerUid: 'firebase-user-a',
          entityType: 'habit_log',
          recordId: _id(33),
        ),
        isNull,
      );
      final accepted = await localDatabase.getRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'habit_log',
        recordId: _id(30),
      );
      expect((accepted?['payload'] as Map)['result'], 'completed');
    },
  );

  test('keeps the previous account queue when switching accounts', () async {
    await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'meal_log',
      recordId: _id(40),
      payload: {'meal_name': 'account A meal'},
    );
    await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-b',
      entityType: 'meal_log',
      recordId: _id(41),
      payload: {'meal_name': 'account B meal'},
    );

    expect(await worker.flush('firebase-user-b'), 1);

    expect(transport.records.values.map((record) => record['owner_uid']), [
      'firebase-user-b',
    ]);
    expect(await localDatabase.getPendingChanges('firebase-user-b'), isEmpty);
    expect(
      await localDatabase.getPendingChanges('firebase-user-a'),
      hasLength(1),
    );
    expect(
      await localDatabase.getRecord(
        ownerUid: 'firebase-user-b',
        entityType: 'meal_log',
        recordId: _id(40),
      ),
      isNull,
    );

    expect(await worker.flush('firebase-user-a'), 1);

    expect(
      transport.records.values.map((record) => record['owner_uid']).toSet(),
      {'firebase-user-a', 'firebase-user-b'},
    );
    expect(await localDatabase.getPendingChanges('firebase-user-a'), isEmpty);
  });
}

String _id(int suffix) =>
    '00000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}';

class _FakeSyncTransport implements SyncTransport {
  final records = <String, Map<String, Object?>>{};
  final receipts = <String, SyncApplyResult>{};
  final operationIds = <String>[];
  var applyCount = 0;
  bool failNextBeforeApply = false;
  bool loseNextResponseAfterApply = false;

  void seed({
    required String ownerUid,
    required String entityType,
    required String recordId,
    required int version,
    required Map<String, Object?> payload,
  }) {
    final row = {
      ...payload,
      'id': recordId,
      'owner_uid': ownerUid,
      'version': version,
    };
    records[_key(ownerUid, entityType, recordId, row)] = row;
  }

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
    operationIds.add(operationId);
    if (failNextBeforeApply) {
      failNextBeforeApply = false;
      throw const SyncTransportException('network_unavailable');
    }

    final receiptKey = '$ownerUid:$operationId';
    final priorResult = receipts[receiptKey];
    if (priorResult != null) return priorResult;
    applyCount++;

    final tableKey = _key(ownerUid, entityType, recordId, payload ?? {});
    final current = records[tableKey];
    var outcome = 'conflict';
    Map<String, Object?>? serverRecord = current;
    int? serverVersion = current?['version'] as int?;

    if (operation == 'delete') {
      if (current == null && baseVersion == null) {
        outcome = 'applied';
        serverRecord = null;
        serverVersion = null;
      } else if (current != null && current['version'] == baseVersion) {
        records.remove(tableKey);
        outcome = 'applied';
        serverRecord = null;
      }
    } else if (current == null && baseVersion == null) {
      final row = {
        ...?payload,
        'id': recordId,
        'owner_uid': ownerUid,
        'version': 1,
      };
      records[tableKey] = row;
      serverRecord = row;
      serverVersion = 1;
      outcome = 'applied';
    } else if (current != null && current['version'] == baseVersion) {
      final row = {
        ...current,
        ...?payload,
        'id': current['id'],
        'owner_uid': ownerUid,
        'version': (baseVersion ?? 0) + 1,
      };
      records[tableKey] = row;
      serverRecord = row;
      serverVersion = row['version'] as int;
      outcome = 'applied';
    }

    final result = SyncApplyResult(
      outcome: outcome,
      serverVersion: serverVersion,
      serverRecord: serverRecord,
    );
    receipts[receiptKey] = result;
    if (loseNextResponseAfterApply && outcome == 'applied') {
      loseNextResponseAfterApply = false;
      throw const SyncTransportException('network_unavailable');
    }
    return result;
  }

  String _key(
    String ownerUid,
    String entityType,
    String recordId,
    Map<String, Object?> values,
  ) {
    if (entityType == 'habit_log') {
      return '$ownerUid:$entityType:${values['habit_id']}:${values['local_date']}';
    }
    return '$ownerUid:$entityType:$recordId';
  }
}
