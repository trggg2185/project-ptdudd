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
