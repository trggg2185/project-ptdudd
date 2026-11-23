import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/core/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase localDatabase;

  setUp(() {
    localDatabase = LocalDatabase(databasePath: inMemoryDatabasePath);
  });

  tearDown(() async {
    await localDatabase.close();
  });

  test('creates records and sync queue tables', () async {
    final tables = await (await localDatabase.database).rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();

    expect(names, containsAll(['local_records', 'sync_queue']));
  });

  test('keeps records and queued changes scoped to their account', () async {
    await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'habit_log',
      recordId: 'log-1',
      payload: {'result': 'completed'},
    );

    expect(
      await localDatabase.getRecord(
        ownerUid: 'firebase-user-b',
        entityType: 'habit_log',
        recordId: 'log-1',
      ),
      isNull,
    );
    expect(await localDatabase.getPendingChanges('firebase-user-b'), isEmpty);
    expect(
      await localDatabase.getPendingChanges('firebase-user-a'),
      hasLength(1),
    );
  });

  test(
    'replaying the same operation ID does not duplicate the queue entry',
    () async {
      const operationId = 'c0d8c12d-3a4f-4de5-8b5c-1bbdf1f7f2ef';

      await localDatabase.upsertRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'habit_log',
        recordId: 'log-1',
        payload: {'result': 'completed'},
        operationId: operationId,
      );
      await localDatabase.upsertRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'habit_log',
        recordId: 'log-1',
        payload: {'result': 'completed'},
        operationId: operationId,
      );

      expect(
        await localDatabase.getPendingChanges('firebase-user-a'),
        hasLength(1),
      );
    },
  );

  test('coalesces repeated offline edits into one pending operation', () async {
    await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'habit_log',
      recordId: 'log-1',
      payload: {'result': 'started'},
    );
    await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'habit_log',
      recordId: 'log-1',
      payload: {'result': 'completed'},
    );

    final pending = await localDatabase.getPendingChanges('firebase-user-a');
    expect(pending, hasLength(1));
    expect(pending.single['payload_json'], jsonEncode({'result': 'completed'}));
  });

  test(
    'removes an unsynced create from the queue when deleted offline',
    () async {
      await localDatabase.upsertRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'habit_log',
        recordId: 'log-1',
        payload: {'result': 'completed'},
      );

      await localDatabase.deleteRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'habit_log',
        recordId: 'log-1',
      );

      expect(await localDatabase.getPendingChanges('firebase-user-a'), isEmpty);
      expect(
        await localDatabase.getRecord(
          ownerUid: 'firebase-user-a',
          entityType: 'habit_log',
          recordId: 'log-1',
        ),
        isNull,
      );
    },
  );

  test('creates a new operation id when a pending payload changes', () async {
    await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'habit_log',
      recordId: 'log-1',
      payload: {'result': 'started'},
      operationId: 'c0d8c12d-3a4f-4de5-8b5c-1bbdf1f7f2ef',
    );

    final changedId = await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'habit_log',
      recordId: 'log-1',
      payload: {'result': 'completed'},
    );

    final pending = await localDatabase.getPendingChanges('firebase-user-a');
    expect(pending, hasLength(1));
    expect(pending.single['operation_id'], changedId);
    expect(
      pending.single['operation_id'],
      isNot('c0d8c12d-3a4f-4de5-8b5c-1bbdf1f7f2ef'),
    );
  });

  test(
    'uses the stored server version when deleting without baseVersion',
    () async {
      await localDatabase.upsertRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'meal_log',
        recordId: 'meal-1',
        payload: {'meal_name': 'Lunch'},
        baseVersion: 4,
      );

      await localDatabase.deleteRecord(
        ownerUid: 'firebase-user-a',
        entityType: 'meal_log',
        recordId: 'meal-1',
      );

      final pending = await localDatabase.getPendingChanges('firebase-user-a');
      expect(pending, hasLength(1));
      expect(pending.single['operation'], 'delete');
      expect(pending.single['base_version'], 4);
    },
  );

  test('marks synced changes and removes them from the queue', () async {
    final operationId = await localDatabase.upsertRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'habit_log',
      recordId: 'log-1',
      payload: {'result': 'completed'},
    );

    await localDatabase.markSynced(
      ownerUid: 'firebase-user-a',
      operationId: operationId,
      serverVersion: 4,
    );

    expect(await localDatabase.getPendingChanges('firebase-user-a'), isEmpty);
    final record = await localDatabase.getRecord(
      ownerUid: 'firebase-user-a',
      entityType: 'habit_log',
      recordId: 'log-1',
    );
    expect(record?['server_version'], 4);
  });
}
