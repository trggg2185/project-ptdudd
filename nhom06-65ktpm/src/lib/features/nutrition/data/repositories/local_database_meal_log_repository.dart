import 'dart:convert';

import '../../../../core/local_database.dart';
import '../../domain/entities/meal_log.dart';
import '../../domain/entities/meal_photo_attachment.dart';
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
      final imagePath = payload['image_path'] as String?;
      final consumedAtRaw = payload['consumed_at'] as String? ?? updatedAtRaw;
      return MealLog(
        id: row['record_id']! as String,
        ownerUid: row['owner_uid']! as String,
        mealId: payload['meal_id'] as String?,
        mealName: payload['meal_name'] as String? ?? '',
        userConfirmedName: true,
        consumedAt: DateTime.parse(consumedAtRaw),
        imagePath: imagePath,
        photoUploadStatus: imagePath != null && imagePath.isNotEmpty
            ? MealPhotoUploadStatus.uploaded
            : MealPhotoUploadStatus.none,
        note: payload['note'] as String?,
        createdAt: DateTime.parse(consumedAtRaw),
        updatedAt: DateTime.parse(updatedAtRaw),
        version: serverVersion ?? 1,
      );
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
      payload: log.toSupabasePayload(),
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
