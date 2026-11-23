import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class LocalDatabase {
  LocalDatabase({this.databasePath});

  static const _databaseName = 'healthylife.db';
  static const _databaseVersion = 1;
  static const _uuid = Uuid();

  final String? databasePath;
  Future<Database>? _opening;

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    final path =
        databasePath ?? p.join(await getDatabasesPath(), _databaseName);
    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE local_records (
        owner_uid TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        record_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        server_version INTEGER,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_uid, entity_type, record_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_queue (
        operation_id TEXT PRIMARY KEY,
        owner_uid TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
        payload_json TEXT,
        base_version INTEGER,
        created_at TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
        last_error_code TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX sync_queue_owner_created
      ON sync_queue (owner_uid, created_at)
    ''');
  }

  Future<String> upsertRecord({
    required String ownerUid,
    required String entityType,
    required String recordId,
    required Map<String, Object?> payload,
    int? baseVersion,
    String? operationId,
  }) async {
    _validateIdentity(ownerUid, entityType, recordId);
    final encodedPayload = jsonEncode(payload);
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await database;

    await db.transaction((txn) async {
      final pending = await txn.query(
        'sync_queue',
        where: '''
          owner_uid = ? AND entity_type = ? AND record_id = ?
        ''',
        whereArgs: [ownerUid, entityType, recordId],
        limit: 1,
        orderBy: 'created_at',
      );
      final id = pending.isEmpty
          ? (operationId ?? _uuid.v4())
          : pending.single['operation_id']! as String;

      await txn.insert('local_records', {
        'owner_uid': ownerUid,
        'entity_type': entityType,
        'record_id': recordId,
        'payload_json': encodedPayload,
        'server_version': baseVersion,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (pending.isEmpty) {
        await _enqueue(
          txn,
          operationId: id,
          ownerUid: ownerUid,
          entityType: entityType,
          recordId: recordId,
          operation: 'upsert',
          payloadJson: encodedPayload,
          baseVersion: baseVersion,
          createdAt: now,
        );
      } else {
        final existing = pending.single;
        await txn.update(
          'sync_queue',
          {
            'operation': 'upsert',
            'payload_json': encodedPayload,
            'base_version': existing['base_version'] ?? baseVersion,
            'created_at': existing['created_at'],
            'attempt_count': 0,
            'last_error_code': null,
          },
          where: 'operation_id = ?',
          whereArgs: [id],
        );
      }
    });

    final rows = await db.query(
      'sync_queue',
      columns: ['operation_id'],
      where: 'owner_uid = ? AND entity_type = ? AND record_id = ?',
      whereArgs: [ownerUid, entityType, recordId],
      limit: 1,
    );
    return rows.single['operation_id']! as String;
  }

  Future<String> deleteRecord({
    required String ownerUid,
    required String entityType,
    required String recordId,
    int? baseVersion,
    String? operationId,
  }) async {
    _validateIdentity(ownerUid, entityType, recordId);
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await database;

    await db.transaction((txn) async {
      final pending = await txn.query(
        'sync_queue',
        where: '''
          owner_uid = ? AND entity_type = ? AND record_id = ?
        ''',
        whereArgs: [ownerUid, entityType, recordId],
        limit: 1,
        orderBy: 'created_at',
      );
      final id = pending.isEmpty
          ? (operationId ?? _uuid.v4())
          : pending.single['operation_id']! as String;

      await txn.delete(
        'local_records',
        where: 'owner_uid = ? AND entity_type = ? AND record_id = ?',
        whereArgs: [ownerUid, entityType, recordId],
      );
      if (pending.isNotEmpty &&
          pending.single['operation'] == 'upsert' &&
          pending.single['base_version'] == null) {
        await txn.delete(
          'sync_queue',
          where: 'operation_id = ?',
          whereArgs: [id],
        );
      } else if (pending.isNotEmpty) {
        final existing = pending.single;
        await txn.update(
          'sync_queue',
          {
            'operation': 'delete',
            'payload_json': null,
            'base_version': existing['base_version'] ?? baseVersion,
            'created_at': existing['created_at'],
            'attempt_count': 0,
            'last_error_code': null,
          },
          where: 'operation_id = ?',
          whereArgs: [id],
        );
      } else if (baseVersion != null) {
        await _enqueue(
          txn,
          operationId: id,
          ownerUid: ownerUid,
          entityType: entityType,
          recordId: recordId,
          operation: 'delete',
          payloadJson: null,
          baseVersion: baseVersion,
          createdAt: now,
        );
      }
    });

    final rows = await db.query(
      'sync_queue',
      columns: ['operation_id'],
      where: 'owner_uid = ? AND entity_type = ? AND record_id = ?',
      whereArgs: [ownerUid, entityType, recordId],
      limit: 1,
    );
    return rows.isEmpty
        ? (operationId ?? _uuid.v4())
        : rows.single['operation_id']! as String;
  }

  Future<Map<String, Object?>?> getRecord({
    required String ownerUid,
    required String entityType,
    required String recordId,
  }) async {
    final rows = await (await database).query(
      'local_records',
      where: 'owner_uid = ? AND entity_type = ? AND record_id = ?',
      whereArgs: [ownerUid, entityType, recordId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.single;
    return {...row, 'payload': jsonDecode(row['payload_json']! as String)};
  }

  Future<List<Map<String, Object?>>> getPendingChanges(String ownerUid) {
    return (database).then(
      (db) => db.query(
        'sync_queue',
        where: 'owner_uid = ?',
        whereArgs: [ownerUid],
        orderBy: 'created_at, operation_id',
      ),
    );
  }

  Future<void> recordSyncFailure({
    required String ownerUid,
    required String operationId,
    required String errorCode,
  }) async {
    final updated = await (await database).rawUpdate(
      '''
      UPDATE sync_queue
      SET attempt_count = attempt_count + 1, last_error_code = ?
      WHERE owner_uid = ? AND operation_id = ?
      ''',
      [errorCode, ownerUid, operationId],
    );
    if (updated == 0) {
      throw StateError('Sync operation not found for the signed-in account.');
    }
  }

  Future<void> markSynced({
    required String ownerUid,
    required String operationId,
    int? serverVersion,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sync_queue',
        where: 'owner_uid = ? AND operation_id = ?',
        whereArgs: [ownerUid, operationId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final change = rows.single;
      if (change['operation'] == 'upsert') {
        await txn.update(
          'local_records',
          {'server_version': serverVersion},
          where: '''
            owner_uid = ? AND entity_type = ? AND record_id = ?
          ''',
          whereArgs: [ownerUid, change['entity_type'], change['record_id']],
        );
      }

      await txn.delete(
        'sync_queue',
        where: 'owner_uid = ? AND operation_id = ?',
        whereArgs: [ownerUid, operationId],
      );
    });
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening == null) return;
    final db = await opening;
    await db.close();
    _opening = null;
  }

  Future<void> _enqueue(
    DatabaseExecutor executor, {
    required String operationId,
    required String ownerUid,
    required String entityType,
    required String recordId,
    required String operation,
    required String? payloadJson,
    required int? baseVersion,
    required String createdAt,
  }) async {
    final values = <String, Object?>{
      'operation_id': operationId,
      'owner_uid': ownerUid,
      'entity_type': entityType,
      'record_id': recordId,
      'operation': operation,
      'payload_json': payloadJson,
      'base_version': baseVersion,
      'created_at': createdAt,
    };
    final inserted = await executor.insert(
      'sync_queue',
      values,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;

    final rows = await executor.query(
      'sync_queue',
      where: 'operation_id = ?',
      whereArgs: [operationId],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.single['owner_uid'] != ownerUid ||
        rows.single['entity_type'] != entityType ||
        rows.single['record_id'] != recordId ||
        rows.single['operation'] != operation ||
        rows.single['payload_json'] != payloadJson ||
        rows.single['base_version'] != baseVersion) {
      throw StateError('Operation ID is already used by a different change.');
    }
  }

  void _validateIdentity(String ownerUid, String entityType, String recordId) {
    if (ownerUid.trim().isEmpty ||
        entityType.trim().isEmpty ||
        recordId.trim().isEmpty) {
      throw ArgumentError(
        'Owner UID, entity type, and record ID are required.',
      );
    }
  }
}
