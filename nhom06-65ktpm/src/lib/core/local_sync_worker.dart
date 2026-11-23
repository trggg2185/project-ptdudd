import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'local_database.dart';

class SyncTransportException implements Exception {
  const SyncTransportException(this.code);

  final String code;
}

class SyncConflictException implements Exception {
  const SyncConflictException({
    required this.ownerUid,
    required this.operationId,
    required this.entityType,
    required this.recordId,
    required this.serverVersion,
    required this.serverRecord,
  });

  final String ownerUid;
  final String operationId;
  final String entityType;
  final String recordId;
  final int? serverVersion;
  final Map<String, Object?>? serverRecord;
}

class SyncApplyResult {
  const SyncApplyResult({
    required this.outcome,
    required this.serverVersion,
    required this.serverRecord,
  });

  final String outcome;
  final int? serverVersion;
  final Map<String, Object?>? serverRecord;
}

abstract interface class SyncTransport {
  Future<SyncApplyResult> apply({
    required String operationId,
    required String ownerUid,
    required String entityType,
    required String recordId,
    required String operation,
    required Map<String, Object?>? payload,
    required int? baseVersion,
  });
}

class SupabaseSyncTransport implements SyncTransport {
  SupabaseSyncTransport(this._client, {required this.currentOwnerUid});

  static const _logEntityTypes = {
    'habit_log',
    'activity_session',
    'meal_log',
    'sleep_log',
  };

  final SupabaseClient _client;
  final String? Function() currentOwnerUid;

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
    if (ownerUid.isEmpty || currentOwnerUid() != ownerUid) {
      throw StateError('Sync UID does not match the authenticated user.');
    }
    if (!_logEntityTypes.contains(entityType)) {
      throw UnsupportedError('Unsupported sync entity: $entityType');
    }

    try {
      final response = await _client.rpc(
        'apply_log_sync',
        params: {
          'p_operation_id': operationId,
          'p_entity_type': entityType,
          'p_record_id': recordId,
          'p_operation': operation,
          'p_payload': payload,
          'p_base_version': baseVersion,
          'p_expected_owner_uid': ownerUid,
        },
      );
      if (response is! List || response.length != 1) {
        throw const FormatException('Unexpected log sync response.');
      }
      final row = response.single;
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Unexpected log sync response row.');
      }
      final rawVersion = row['server_version'];
      final rawRecord = row['server_record'];
      if (rawVersion != null && rawVersion is! int) {
        throw const FormatException('Invalid server version in sync response.');
      }
      if (rawRecord != null && rawRecord is! Map<String, dynamic>) {
        throw const FormatException('Invalid server record in sync response.');
      }
      return SyncApplyResult(
        outcome: row['outcome']! as String,
        serverVersion: rawVersion as int?,
        serverRecord: rawRecord == null
            ? null
            : Map<String, Object?>.from(rawRecord),
      );
    } on PostgrestException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SyncTransportException('server_rejected'),
        stackTrace,
      );
    } on SocketException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SyncTransportException('network_unavailable'),
        stackTrace,
      );
    } on TimeoutException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SyncTransportException('network_timeout'),
        stackTrace,
      );
    }
  }
}

class LocalSyncWorker {
  LocalSyncWorker({required this.localDatabase, required this.transport});

  static const _uuid = Uuid();
  static const _targets = {
    'habit_log',
    'activity_session',
    'meal_log',
    'sleep_log',
  };

  final LocalDatabase localDatabase;
  final SyncTransport transport;

  Future<int> flush(String ownerUid) async {
    if (ownerUid.trim().isEmpty) {
      throw ArgumentError.value(ownerUid, 'ownerUid', 'Must not be empty.');
    }

    final pending = await localDatabase.getPendingChanges(ownerUid);
    var syncedCount = 0;
    for (final change in pending) {
      await _syncChange(ownerUid, change);
      syncedCount++;
    }
    return syncedCount;
  }

  Future<void> _syncChange(String ownerUid, Map<String, Object?> change) async {
    if (change['owner_uid'] != ownerUid) {
      throw StateError('Queued change does not belong to the requested user.');
    }
    final entityType = change['entity_type']! as String;
    if (!_targets.contains(entityType)) {
      throw UnsupportedError('Unsupported sync entity: $entityType');
    }

    final operationId = change['operation_id']! as String;
    final recordId = change['record_id']! as String;
    final operation = change['operation']! as String;
    Map<String, Object?>? payload;
    if (operation == 'upsert') {
      final decoded = jsonDecode(change['payload_json']! as String);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Queued record payload must be an object.');
      }
      payload = Map<String, Object?>.from(decoded)
        ..remove('id')
        ..remove('owner_uid')
        ..remove('version')
        ..remove('created_at')
        ..remove('updated_at');
    } else if (operation != 'delete') {
      throw StateError('Unsupported sync operation: $operation');
    }

    late final SyncApplyResult result;
    try {
      result = await transport.apply(
        operationId: operationId,
        ownerUid: ownerUid,
        entityType: entityType,
        recordId: recordId,
        operation: operation,
        payload: payload,
        baseVersion: change['base_version'] as int?,
      );
    } on SyncTransportException catch (error, stackTrace) {
      await localDatabase.recordSyncFailure(
        ownerUid: ownerUid,
        operationId: operationId,
        errorCode: error.code,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (result.outcome == 'conflict') {
      throw SyncConflictException(
        ownerUid: ownerUid,
        operationId: operationId,
        entityType: entityType,
        recordId: recordId,
        serverVersion: result.serverVersion,
        serverRecord: result.serverRecord,
      );
    }
    if (result.outcome != 'applied') {
      throw StateError('Unexpected sync outcome: ${result.outcome}');
    }
    await localDatabase.markSynced(
      ownerUid: ownerUid,
      operationId: operationId,
      serverVersion: result.serverVersion,
    );
  }

  Future<String> keepLocalChanges(SyncConflictException conflict) async {
    final db = await localDatabase.database;
    final newOperationId = _uuid.v4();
    final updated = await db.transaction((txn) async {
      final queued = await txn.query(
        'sync_queue',
        where: '''
          owner_uid = ? AND operation_id = ?
            AND entity_type = ? AND record_id = ?
        ''',
        whereArgs: [
          conflict.ownerUid,
          conflict.operationId,
          conflict.entityType,
          conflict.recordId,
        ],
        limit: 1,
      );
      if (queued.isEmpty) {
        throw StateError('Conflicted change is no longer queued.');
      }
      final change = queued.single;
      final serverRecordId =
          conflict.serverRecord?['id'] as String? ?? conflict.recordId;
      final localPayloadJson = change['payload_json'] as String?;

      if (change['operation'] == 'upsert') {
        if (localPayloadJson == null) {
          throw StateError('Conflicted upsert has no local payload.');
        }
        await txn.delete(
          'local_records',
          where: '''
            owner_uid = ? AND entity_type = ? AND record_id = ?
          ''',
          whereArgs: [
            conflict.ownerUid,
            conflict.entityType,
            conflict.recordId,
          ],
        );
        await txn.insert('local_records', {
          'owner_uid': conflict.ownerUid,
          'entity_type': conflict.entityType,
          'record_id': serverRecordId,
          'payload_json': localPayloadJson,
          'server_version': conflict.serverVersion,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final newChangeId = await txn.update(
        'sync_queue',
        {
          'operation_id': newOperationId,
          'record_id': serverRecordId,
          'base_version': conflict.serverVersion,
          'attempt_count': 0,
          'last_error_code': null,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'owner_uid = ? AND operation_id = ?',
        whereArgs: [conflict.ownerUid, conflict.operationId],
      );
      if (newChangeId != 1) return newChangeId;
      if (serverRecordId != conflict.recordId) {
        await txn.update(
          'sync_queue',
          {'record_id': serverRecordId},
          where: '''
            owner_uid = ? AND entity_type = ? AND record_id = ?
          ''',
          whereArgs: [
            conflict.ownerUid,
            conflict.entityType,
            conflict.recordId,
          ],
        );
      }
      return newChangeId;
    });
    if (updated != 1) {
      throw StateError('Could not rebase the conflicted change.');
    }
    return newOperationId;
  }

  Future<void> acceptServerChange(SyncConflictException conflict) async {
    final db = await localDatabase.database;
    await db.transaction((txn) async {
      final queued = await txn.query(
        'sync_queue',
        where: '''
          owner_uid = ? AND operation_id = ?
            AND entity_type = ? AND record_id = ?
        ''',
        whereArgs: [
          conflict.ownerUid,
          conflict.operationId,
          conflict.entityType,
          conflict.recordId,
        ],
        limit: 1,
      );
      if (queued.isEmpty) {
        throw StateError('Conflicted change is no longer queued.');
      }

      if (conflict.serverRecord == null) {
        await txn.delete(
          'local_records',
          where: '''
            owner_uid = ? AND entity_type = ? AND record_id = ?
          ''',
          whereArgs: [
            conflict.ownerUid,
            conflict.entityType,
            conflict.recordId,
          ],
        );
      } else {
        final serverRecordId =
            conflict.serverRecord!['id'] as String? ?? conflict.recordId;
        await txn.delete(
          'local_records',
          where: '''
            owner_uid = ? AND entity_type = ? AND record_id = ?
          ''',
          whereArgs: [
            conflict.ownerUid,
            conflict.entityType,
            conflict.recordId,
          ],
        );
        await txn.insert('local_records', {
          'owner_uid': conflict.ownerUid,
          'entity_type': conflict.entityType,
          'record_id': serverRecordId,
          'payload_json': jsonEncode(conflict.serverRecord),
          'server_version': conflict.serverVersion,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.delete(
        'sync_queue',
        where: '''
          owner_uid = ? AND entity_type = ? AND record_id = ?
        ''',
        whereArgs: [conflict.ownerUid, conflict.entityType, conflict.recordId],
      );
    });
  }
}
