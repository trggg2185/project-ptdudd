import 'package:sqflite/sqflite.dart';

import '../../../../core/local_database.dart';
import '../../domain/entities/scheduled_reminder.dart';
import '../../domain/repositories/notification_background_state_store.dart';

/// Kho lưu SQLite (dùng chung `LocalDatabase` / `healthylife.db`) giúp UI isolate và
/// FCM background/terminated isolate chia sẻ trạng thái tài khoản, giờ yên lặng và
/// sổ chống trùng Local ↔ FCM an toàn theo `owner_uid`.
class SqliteNotificationBackgroundStateStore
    implements NotificationBackgroundStateStore {
  static const String runtimeStateTable = 'notification_runtime_state';
  static const String dedupeTable = 'notification_dedupe_entries';

  final LocalDatabase _localDatabase;
  Database? _initializedDb;

  SqliteNotificationBackgroundStateStore(this._localDatabase);

  Future<Database> _databaseWithTables() async {
    final db = await _localDatabase.database;
    if (!identical(_initializedDb, db)) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $runtimeStateTable (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          active_owner_uid TEXT,
          reminders_enabled INTEGER NOT NULL,
          quiet_hours_start_minute INTEGER,
          quiet_hours_end_minute INTEGER,
          timezone TEXT NOT NULL,
          updated_at_utc TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $dedupeTable (
          owner_uid TEXT NOT NULL,
          dedupe_key TEXT NOT NULL,
          source TEXT NOT NULL,
          dispatched_at_utc TEXT NOT NULL,
          PRIMARY KEY (owner_uid, dedupe_key)
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS notification_dedupe_owner_time
        ON $dedupeTable (owner_uid, dispatched_at_utc)
      ''');
      _initializedDb = db;
    }
    return db;
  }

  @override
  Future<void> saveRuntimeState(NotificationRuntimeState state) async {
    final db = await _databaseWithTables();
    await db.insert(
      runtimeStateTable,
      {
        'id': 1,
        'active_owner_uid': state.activeOwnerUid,
        'reminders_enabled': state.remindersEnabled ? 1 : 0,
        'quiet_hours_start_minute': state.quietHoursStartMinute,
        'quiet_hours_end_minute': state.quietHoursEndMinute,
        'timezone': state.timezone,
        'updated_at_utc': state.updatedAtUtc.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<NotificationRuntimeState?> readRuntimeState() async {
    final db = await _databaseWithTables();
    final rows = await db.query(
      runtimeStateTable,
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return NotificationRuntimeState(
      activeOwnerUid: row['active_owner_uid'] as String?,
      remindersEnabled: ((row['reminders_enabled']! as num).toInt()) == 1,
      quietHoursStartMinute: (row['quiet_hours_start_minute'] as num?)?.toInt(),
      quietHoursEndMinute: (row['quiet_hours_end_minute'] as num?)?.toInt(),
      timezone: row['timezone']! as String,
      updatedAtUtc: DateTime.parse(row['updated_at_utc']! as String).toUtc(),
    );
  }

  @override
  Future<bool> tryAcquireDedupeKey({
    required String ownerUid,
    required String dedupeKey,
    required NotificationChannelSource source,
    required DateTime nowUtc,
    Duration window = const Duration(minutes: 15),
  }) async {
    final normalizedNow = nowUtc.toUtc();
    final cutoff = normalizedNow.subtract(window).toIso8601String();
    final db = await _databaseWithTables();

    return db.transaction((txn) async {
      await txn.delete(
        dedupeTable,
        where: 'owner_uid = ? AND dispatched_at_utc <= ?',
        whereArgs: [ownerUid, cutoff],
      );

      final existing = await txn.query(
        dedupeTable,
        columns: ['dispatched_at_utc'],
        where: 'owner_uid = ? AND dedupe_key = ?',
        whereArgs: [ownerUid, dedupeKey],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final dispatchedAt = DateTime.parse(
          existing.single['dispatched_at_utc']! as String,
        ).toUtc();
        final elapsed = normalizedNow.difference(dispatchedAt);
        if (!elapsed.isNegative && elapsed < window) {
          return false;
        }
      }

      await txn.insert(
        dedupeTable,
        {
          'owner_uid': ownerUid,
          'dedupe_key': dedupeKey,
          'source': source.name,
          'dispatched_at_utc': normalizedNow.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    });
  }

  @override
  Future<void> recordDispatchedKey({
    required String ownerUid,
    required String dedupeKey,
    required NotificationChannelSource source,
    required DateTime nowUtc,
  }) async {
    final db = await _databaseWithTables();
    await db.insert(
      dedupeTable,
      {
        'owner_uid': ownerUid,
        'dedupe_key': dedupeKey,
        'source': source.name,
        'dispatched_at_utc': nowUtc.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clearForOwner(String ownerUid) async {
    final db = await _databaseWithTables();
    await db.transaction((txn) async {
      await txn.delete(
        dedupeTable,
        where: 'owner_uid = ?',
        whereArgs: [ownerUid],
      );
      await txn.update(
        runtimeStateTable,
        {
          'active_owner_uid': null,
          'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = 1 AND active_owner_uid = ?',
        whereArgs: [ownerUid],
      );
    });
  }
}
