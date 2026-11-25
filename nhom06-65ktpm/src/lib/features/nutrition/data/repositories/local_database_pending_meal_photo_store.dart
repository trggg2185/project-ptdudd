import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../../../core/local_database.dart';
import '../../domain/entities/meal_photo_attachment.dart';
import '../../domain/entities/meal_photo_policy.dart';
import '../../domain/repositories/pending_meal_photo_store.dart';
import '../../domain/services/meal_photo_validator.dart';

/// Kho lưu bền vững trên SQLite (dùng chung [LocalDatabase]) cho các ảnh bữa ăn
/// đã nén và xóa sạch EXIF đang chờ đồng bộ khi mất mạng.
/// Cô lập theo cặp khóa chính `(owner_uid, log_id)` để không mất ảnh khi khởi động lại app
/// và không rò rỉ dữ liệu giữa các tài khoản.
class LocalDatabasePendingMealPhotoStore implements PendingMealPhotoStore {
  static const String tableName = 'pending_meal_photos';

  final LocalDatabase _localDatabase;
  final MealPhotoValidator validator;
  Database? _initializedDb;

  LocalDatabasePendingMealPhotoStore(
    this._localDatabase, {
    this.validator = const MealPhotoValidator(),
  });

  Future<Database> _databaseWithTable() async {
    final db = await _localDatabase.database;
    if (!identical(_initializedDb, db)) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableName (
          owner_uid TEXT NOT NULL,
          log_id TEXT NOT NULL,
          source TEXT NOT NULL,
          file_name TEXT NOT NULL,
          mime_type TEXT NOT NULL,
          extension TEXT NOT NULL,
          photo_bytes BLOB NOT NULL,
          original_size_bytes INTEGER NOT NULL,
          compressed INTEGER NOT NULL,
          exif_stripped INTEGER NOT NULL,
          queued_at TEXT NOT NULL,
          PRIMARY KEY (owner_uid, log_id)
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS pending_meal_photos_owner_queued
        ON $tableName (owner_uid, queued_at, log_id)
      ''');
      _initializedDb = db;
    }
    return db;
  }

  @override
  Future<void> savePendingPhoto({
    required String ownerUid,
    required String logId,
    required PreparedMealPhoto photo,
  }) async {
    final trimmedOwner = ownerUid.trim();
    final trimmedLogId = logId.trim();
    if (trimmedOwner.isEmpty || trimmedLogId.isEmpty) {
      throw ArgumentError('ownerUid và logId là bắt buộc khi lưu ảnh chờ.');
    }
    if (!photo.exifStripped) {
      throw const MealPhotoException(
        MealPhotoFailureCode.exifNotRemoved,
        'Chỉ được lưu ảnh chờ đã xóa sạch metadata EXIF/vị trí.',
      );
    }

    final verifiedMime = validator.validateForUpload(
      ownerUid: trimmedOwner,
      bytes: photo.bytes,
      declaredMimeType: photo.mimeType,
    );
    final safeExtension = validator.extensionForMime(verifiedMime);
    final db = await _databaseWithTable();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      tableName,
      {
        'owner_uid': trimmedOwner,
        'log_id': trimmedLogId,
        'source': photo.source.name,
        'file_name': photo.fileName,
        'mime_type': verifiedMime,
        'extension': safeExtension,
        'photo_bytes': Uint8List.fromList(photo.bytes),
        'original_size_bytes': photo.originalSizeBytes,
        'compressed': photo.compressed ? 1 : 0,
        'exif_stripped': 1,
        'queued_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<PendingMealPhoto>> getPendingPhotos({
    required String ownerUid,
  }) async {
    final trimmedOwner = ownerUid.trim();
    if (trimmedOwner.isEmpty) {
      return const [];
    }

    final db = await _databaseWithTable();
    // Truy vấn danh sách log_id trước rồi đọc từng bản ghi BLOB để tránh vượt
    // giới hạn CursorWindow trên Android khi có nhiều ảnh chờ ~1 MB.
    final indexRows = await db.query(
      tableName,
      columns: ['log_id'],
      where: 'owner_uid = ?',
      whereArgs: [trimmedOwner],
      orderBy: 'queued_at ASC, log_id ASC',
    );
    if (indexRows.isEmpty) {
      return const [];
    }

    final items = <PendingMealPhoto>[];
    for (final indexRow in indexRows) {
      final logId = indexRow['log_id']! as String;
      final rows = await db.query(
        tableName,
        where: 'owner_uid = ? AND log_id = ?',
        whereArgs: [trimmedOwner, logId],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      items.add(_fromRow(rows.single));
    }

    return List<PendingMealPhoto>.unmodifiable(items);
  }

  @override
  Future<void> removePendingPhoto({
    required String ownerUid,
    required String logId,
  }) async {
    final trimmedOwner = ownerUid.trim();
    final trimmedLogId = logId.trim();
    if (trimmedOwner.isEmpty || trimmedLogId.isEmpty) return;

    final db = await _databaseWithTable();
    await db.delete(
      tableName,
      where: 'owner_uid = ? AND log_id = ?',
      whereArgs: [trimmedOwner, trimmedLogId],
    );
  }

  @override
  Future<void> clearForOwner(String ownerUid) async {
    final trimmedOwner = ownerUid.trim();
    if (trimmedOwner.isEmpty) return;

    final db = await _databaseWithTable();
    await db.delete(
      tableName,
      where: 'owner_uid = ?',
      whereArgs: [trimmedOwner],
    );
  }

  static PendingMealPhoto _fromRow(Map<String, Object?> row) {
    final rawSource = row['source'] as String? ?? '';
    final source = MealPhotoSource.values.firstWhere(
      (value) => value.name == rawSource,
      orElse: () => MealPhotoSource.gallery,
    );
    final rawBytes = row['photo_bytes'];
    final bytes = rawBytes is Uint8List
        ? Uint8List.fromList(rawBytes)
        : Uint8List.fromList((rawBytes! as List).cast<int>());

    final photo = PreparedMealPhoto(
      source: source,
      fileName: row['file_name']! as String,
      mimeType: row['mime_type']! as String,
      extension: row['extension']! as String,
      bytes: bytes,
      originalSizeBytes: (row['original_size_bytes']! as num).toInt(),
      compressed: ((row['compressed']! as num).toInt()) == 1,
      exifStripped: ((row['exif_stripped']! as num).toInt()) == 1,
    );

    return PendingMealPhoto(
      ownerUid: row['owner_uid']! as String,
      logId: row['log_id']! as String,
      photo: photo,
      queuedAt: DateTime.parse(row['queued_at']! as String).toUtc(),
    );
  }
}
