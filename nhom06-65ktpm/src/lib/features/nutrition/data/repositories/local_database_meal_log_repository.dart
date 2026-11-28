import 'dart:convert';

import '../../../../core/local_database.dart';
import '../../domain/entities/meal_log.dart';
import '../../domain/repositories/meal_log_repository.dart';

/// Repository lưu nhật ký bữa ăn ngoại tuyến trên SQLite dùng chung [LocalDatabase] (Issue #7)
/// với `entity_type = 'meal_log'`, tự động đẩy thay đổi vào `sync_queue` để không mất nhật ký khi mất mạng.
class LocalDatabaseMealLogRepository implements MealLogRepository {
  static const String entityType = 'meal_log';

  final LocalDatabase _localDatabase;

  const LocalDatabaseMealLogRepository(this._localDatabase);

  @override
  Future<List<MealLog>> getMealLogs({required String ownerUid}) async {
    final db = await _localDatabase.database;
    final rows = await db.query(
      'local_records',
      where: 'owner_uid = ? AND entity_type = ?',
      whereArgs: [ownerUid, entityType],
    );

    final logs = rows.map((row) {
      final payload =
          jsonDecode(row['payload_json']! as String) as Map<String, dynamic>;
      final updatedAtRaw = row['updated_at']! as String;
      final serverVersion = row['server_version'] as int?;
      final consumedAt = payload['consumed_at'] as String? ?? updatedAtRaw;
      return MealLog.fromMap({
        ...payload,
        'id': row['record_id'],
        'owner_uid': row['owner_uid'],
        'meal_name': payload['meal_name'] ?? '',
        'consumed_at': consumedAt,
        'created_at': payload['created_at'] ?? consumedAt,
        'updated_at': updatedAtRaw,
        'version': serverVersion ?? 1,
      });
    }).toList();

    logs.sort((a, b) => b.consumedAt.compareTo(a.consumedAt));
    return List<MealLog>.unmodifiable(logs);
  }

  @override
  Future<MealLog> saveMealLog(MealLog log) async {
    await _localDatabase.upsertRecord(
      ownerUid: log.ownerUid,
      entityType: entityType,
      recordId: log.id,
      payload: {...log.toMap(), ...log.toSupabasePayload()},
    );
    return log;
  }

  @override
  Future<void> deleteMealLog({
    required String ownerUid,
    required String logId,
  }) async {
    await _localDatabase.deleteRecord(
      ownerUid: ownerUid,
      entityType: entityType,
      recordId: logId,
    );
  }
}
