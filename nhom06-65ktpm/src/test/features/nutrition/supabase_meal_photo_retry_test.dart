import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/core/local_database.dart';
import 'package:healthylife/core/local_sync_worker.dart';
import 'package:healthylife/features/nutrition/data/repositories/local_database_meal_log_repository.dart';
import 'package:healthylife/features/nutrition/data/repositories/local_database_pending_meal_photo_store.dart';
import 'package:healthylife/features/nutrition/data/repositories/mock_meal_photo_services.dart';
import 'package:healthylife/features/nutrition/data/repositories/supabase_private_meal_photo_storage.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_log.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_attachment.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_policy.dart';
import 'package:healthylife/features/nutrition/domain/repositories/meal_log_repository.dart';
import 'package:healthylife/features/nutrition/domain/repositories/meal_photo_storage.dart';
import 'package:healthylife/features/nutrition/domain/usecases/meal_nutrition_usecase.dart';
import 'package:healthylife/features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'package:healthylife/features/recommendations/domain/usecases/get_recommendations_usecase.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RecordingSyncTransport implements SyncTransport {
  final List<Map<String, Object?>> calls = [];

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
    calls.add({
      'operationId': operationId,
      'ownerUid': ownerUid,
      'entityType': entityType,
      'recordId': recordId,
      'operation': operation,
      'payload': payload,
      'baseVersion': baseVersion,
    });
    return SyncApplyResult(
      outcome: 'applied',
      serverVersion: (baseVersion ?? 0) + 1,
      serverRecord: payload,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Retry mất phản hồi trên Supabase Storage & HTTP cục bộ (Issue #11)', () {
    test(
      'upload đầu ghi ảnh rồi mất phản hồi, lần retry cùng UID/logId nhận 409 vẫn cập nhật image_path',
      () async {
        final storedObjects = <String, Uint8List>{};
        final upsertHeaders = <String?>[];
        var attempts = 0;

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          final bodyBytes = await request.fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          );
          final objectKey = request.uri.path.replaceFirst(
            '/storage/v1/object/',
            '',
          );
          upsertHeaders.add(request.headers.value('x-upsert'));
          attempts++;

          if (attempts == 1) {
            // Storage đã ghi xong ảnh nhưng kết nối bị ngắt trước khi trả HTTP response.
            storedObjects[objectKey] = bodyBytes.toBytes();
            final socket = await request.response.detachSocket();
            socket.destroy();
            return;
          }

          // Giả lập Storage trả 409 Duplicate khi object đã tồn tại tại đúng path.
          if (storedObjects.containsKey(objectKey)) {
            request.response.statusCode = HttpStatus.conflict;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'statusCode': '409',
                'error': 'Duplicate',
                'message': 'The resource already exists',
              }),
            );
            await request.response.close();
            return;
          }

          storedObjects[objectKey] = bodyBytes.toBytes();
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'Key': objectKey}));
          await request.response.close();
        });

        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'test-publishable-key',
          accessToken: () async => 'test-firebase-jwt',
        );
        final db = LocalDatabase(databasePath: inMemoryDatabasePath);
        addTearDown(() async {
          await db.close();
          await client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        });

        final repo = LocalDatabaseMealLogRepository(db);
        final pendingStore = LocalDatabasePendingMealPhotoStore(db);
        final storage = SupabasePrivateMealPhotoStorage(
          client,
          currentOwnerUid: () => 'uid-a',
        );
        final useCase = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: repo,
          photoPicker: MockMealPhotoPicker(),
          photoStorage: storage,
          pendingPhotoStore: pendingStore,
        );

        final photo = SelectedMealPhoto(
          source: MealPhotoSource.camera,
          fileName: 'lost_response.jpg',
          mimeType: 'image/jpeg',
          bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
        );

        final saveResult = await useCase.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Cơm gà mất phản hồi HTTP',
          selectedPhoto: photo,
        );

        expect(saveResult.savedOfflineWithoutCloudPhoto, isTrue);
        expect(saveResult.photoQueuedForRetry, isTrue);
        expect(saveResult.log.imagePath, isNull);
        expect(
          saveResult.log.photoUploadStatus,
          MealPhotoUploadStatus.pendingLocal,
        );
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 1);

        final expectedKey = 'meal-images/uid-a/${saveResult.log.id}.jpg';
        expect(storedObjects.containsKey(expectedKey), isTrue);

        // Retry cùng UID và logId: gửi x-upsert: true và xử lý được cả phản hồi 409 đã tồn tại.
        final retried = await useCase.retryPendingPhotoUploads(
          ownerUid: 'uid-a',
        );
        expect(retried, 1);
        expect(attempts, 2);
        expect(upsertHeaders, ['false', 'true']);
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 0);

        final logs = await useCase.getMealHistory(ownerUid: 'uid-a');
        expect(logs, hasLength(1));
        expect(logs.single.id, saveResult.log.id);
        expect(logs.single.imagePath, 'uid-a/${saveResult.log.id}.jpg');
        expect(logs.single.photoUploadStatus, MealPhotoUploadStatus.uploaded);

        final transport = _RecordingSyncTransport();
        final worker = LocalSyncWorker(
          localDatabase: db,
          transport: transport,
        );
        expect(await worker.flush('uid-a'), 1);
        final syncedPayload =
            transport.calls.single['payload']! as Map<String, Object?>;
        expect(syncedPayload['image_path'], 'uid-a/${saveResult.log.id}.jpg');
      },
    );

    test(
      'upload đầu mất phản hồi và lần retry dùng x-upsert: true được Storage chấp nhận 200 OK',
      () async {
        final storedObjects = <String, Uint8List>{};
        var attempts = 0;

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          final bodyBytes = await request.fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          );
          final objectKey = request.uri.path.replaceFirst(
            '/storage/v1/object/',
            '',
          );
          final upsert = request.headers.value('x-upsert') == 'true';
          attempts++;

          if (attempts == 1) {
            storedObjects[objectKey] = bodyBytes.toBytes();
            final socket = await request.response.detachSocket();
            socket.destroy();
            return;
          }

          if (storedObjects.containsKey(objectKey) && !upsert) {
            request.response.statusCode = HttpStatus.conflict;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'statusCode': '409',
                'error': 'Duplicate',
                'message': 'The resource already exists',
              }),
            );
            await request.response.close();
            return;
          }

          storedObjects[objectKey] = bodyBytes.toBytes();
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'Key': objectKey}));
          await request.response.close();
        });

        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'test-publishable-key',
          accessToken: () async => 'test-firebase-jwt',
        );
        final db = LocalDatabase(databasePath: inMemoryDatabasePath);
        addTearDown(() async {
          await db.close();
          await client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        });

        final useCase = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: LocalDatabaseMealLogRepository(db),
          photoPicker: MockMealPhotoPicker(),
          photoStorage: SupabasePrivateMealPhotoStorage(
            client,
            currentOwnerUid: () => 'uid-a',
          ),
          pendingPhotoStore: LocalDatabasePendingMealPhotoStore(db),
        );

        final saveResult = await useCase.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Salad ức gà mất phản hồi',
          selectedPhoto: SelectedMealPhoto(
            source: MealPhotoSource.gallery,
            fileName: 'salad.jpg',
            mimeType: 'image/jpeg',
            bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
          ),
        );
        expect(saveResult.photoQueuedForRetry, isTrue);

        final retried = await useCase.retryPendingPhotoUploads(
          ownerUid: 'uid-a',
        );
        expect(retried, 1);
        final logs = await useCase.getMealHistory(ownerUid: 'uid-a');
        expect(logs.single.imagePath, 'uid-a/${saveResult.log.id}.jpg');
        expect(logs.single.photoUploadStatus, MealPhotoUploadStatus.uploaded);
      },
    );

    test(
      'SupabasePrivateMealPhotoStorage không coi lỗi 403/413/415 từ Storage là đã upload',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.forbidden;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'statusCode': '403',
              'error': 'Unauthorized',
              'message': 'new row violates row-level security policy',
            }),
          );
          await request.response.close();
        });

        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'test-publishable-key',
          accessToken: () async => 'test-firebase-jwt',
        );
        addTearDown(() async {
          await client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        });

        final storage = SupabasePrivateMealPhotoStorage(
          client,
          currentOwnerUid: () => 'uid-a',
        );
        final cleanBytes = MockMealPhotoPicker.buildMinimalValidJpeg();
        final prepared = PreparedMealPhoto(
          source: MealPhotoSource.camera,
          fileName: 'meal.jpg',
          mimeType: 'image/jpeg',
          extension: 'jpg',
          bytes: cleanBytes,
          originalSizeBytes: cleanBytes.length,
          compressed: false,
          exifStripped: true,
        );

        await expectLater(
          storage.uploadPrivatePhoto(
            ownerUid: 'uid-a',
            logId: 'log-forbidden',
            photo: prepared,
            isRetry: true,
          ),
          throwsA(
            isA<StorageException>().having(
              (e) => e.statusCode,
              'statusCode',
              '403',
            ),
          ),
        );
      },
    );

    test(
      '409 với mã lỗi khác lỗi trùng object (và cả 409 khi isRetry=false) không được coi là đã upload',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var returnDuplicateError = false;
        final subscription = server.listen((request) async {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.conflict;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              returnDuplicateError
                  ? {
                      'statusCode': '409',
                      'error': 'Duplicate',
                      'message': 'The resource already exists',
                    }
                  : {
                      'statusCode': '409',
                      'error': 'Conflict',
                      'message': 'Resource write conflict before object creation',
                    },
            ),
          );
          await request.response.close();
        });

        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'test-publishable-key',
          accessToken: () async => 'test-firebase-jwt',
        );
        final db = LocalDatabase(databasePath: inMemoryDatabasePath);
        addTearDown(() async {
          await db.close();
          await client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        });

        final storage = SupabasePrivateMealPhotoStorage(
          client,
          currentOwnerUid: () => 'uid-a',
        );
        final cleanBytes = MockMealPhotoPicker.buildMinimalValidJpeg();
        final prepared = PreparedMealPhoto(
          source: MealPhotoSource.camera,
          fileName: 'conflict_meal.jpg',
          mimeType: 'image/jpeg',
          extension: 'jpg',
          bytes: cleanBytes,
          originalSizeBytes: cleanBytes.length,
          compressed: false,
          exifStripped: true,
        );

        // 1. Khi isRetry = false: ngay cả 409 Duplicate cũng không được coi là thành công.
        returnDuplicateError = true;
        await expectLater(
          storage.uploadPrivatePhoto(
            ownerUid: 'uid-a',
            logId: 'log-first-409',
            photo: prepared,
            isRetry: false,
          ),
          throwsA(
            isA<StorageException>().having(
              (e) => e.statusCode,
              'statusCode',
              '409',
            ),
          ),
        );

        // 2. Khi isRetry = true nhưng server trả 409 với error != Duplicate (chưa lưu object):
        // adapter phải ném StorageException, và retry use case tuyệt đối không gắn image_path.
        returnDuplicateError = false;
        await expectLater(
          storage.uploadPrivatePhoto(
            ownerUid: 'uid-a',
            logId: 'log-retry-conflict',
            photo: prepared,
            isRetry: true,
          ),
          throwsA(
            isA<StorageException>().having(
              (e) => e.error,
              'error',
              'Conflict',
            ),
          ),
        );

        final repo = LocalDatabaseMealLogRepository(db);
        final pendingStore = LocalDatabasePendingMealPhotoStore(db);
        final useCase = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: repo,
          photoPicker: MockMealPhotoPicker(),
          photoStorage: storage,
          pendingPhotoStore: pendingStore,
        );

        // Lưu sẵn một nhật ký + ảnh chờ trong SQLite rồi chạy retry gặp 409 Conflict.
        final savedManual = await useCase.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Bữa trưa gặp 409 Conflict',
        );
        await pendingStore.savePendingPhoto(
          ownerUid: 'uid-a',
          logId: savedManual.log.id,
          photo: prepared,
        );

        final report = await useCase.retryPendingPhotoUploadsDetailed(
          ownerUid: 'uid-a',
        );
        expect(report.uploadedCount, 0);
        expect(report.hasRejectedPhotos, isTrue);
        expect(report.rejectedPhotos.single.logId, savedManual.log.id);
        expect(report.rejectedPhotos.single.statusCode, '409');
        expect(report.remainingPendingCount, 0);

        final logs = await useCase.getMealHistory(ownerUid: 'uid-a');
        expect(logs, hasLength(1));
        expect(logs.single.imagePath, isNull);
        expect(logs.single.hasPhoto, isFalse);
      },
    );

    test(
      'hàng đợi SQLite có hai ảnh: Storage trả 413 cho ảnh đầu vẫn tiếp tục tải ảnh thứ hai 200 và báo rõ ảnh cần sửa',
      () async {
        final storedObjects = <String, Uint8List>{};
        final requestedPaths = <String>[];
        String? rejectedLogId;
        var dropConnection = true;

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          final bodyBytes = await request.fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          );
          final objectKey = request.uri.path.replaceFirst(
            '/storage/v1/object/',
            '',
          );
          requestedPaths.add(objectKey);

          if (dropConnection) {
            final socket = await request.response.detachSocket();
            socket.destroy();
            return;
          }

          final blockedId = rejectedLogId;
          if (blockedId != null && objectKey.contains(blockedId)) {
            request.response.statusCode = HttpStatus.requestEntityTooLarge;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'statusCode': '413',
                'error': 'Payload too large',
                'message': 'The object exceeded the maximum allowed size',
              }),
            );
            await request.response.close();
            return;
          }

          storedObjects[objectKey] = bodyBytes.toBytes();
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'Key': objectKey}));
          await request.response.close();
        });

        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'test-publishable-key',
          accessToken: () async => 'test-firebase-jwt',
        );
        final db = LocalDatabase(databasePath: inMemoryDatabasePath);
        addTearDown(() async {
          await db.close();
          await client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        });

        final repo = LocalDatabaseMealLogRepository(db);
        final pendingStore = LocalDatabasePendingMealPhotoStore(db);
        final storage = SupabasePrivateMealPhotoStorage(
          client,
          currentOwnerUid: () => 'uid-a',
        );
        final useCase = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: repo,
          photoPicker: MockMealPhotoPicker(),
          photoStorage: storage,
          pendingPhotoStore: pendingStore,
        );

        // Tạo 2 ảnh chờ trong SQLite khi mất mạng.
        final firstSave = await useCase.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Cơm sườn ảnh quá lớn',
          selectedPhoto: SelectedMealPhoto(
            source: MealPhotoSource.camera,
            fileName: 'oversized_first.jpg',
            mimeType: 'image/jpeg',
            bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final secondSave = await useCase.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Phở gà ảnh hợp lệ',
          selectedPhoto: SelectedMealPhoto(
            source: MealPhotoSource.gallery,
            fileName: 'valid_second.jpg',
            mimeType: 'image/jpeg',
            bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
          ),
        );
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 2);

        // Có mạng lại: Storage từ chối riêng ảnh đầu bằng 413 và chấp nhận ảnh thứ hai bằng 200.
        rejectedLogId = firstSave.log.id;
        dropConnection = false;
        requestedPaths.clear();

        final report = await useCase.retryPendingPhotoUploadsDetailed(
          ownerUid: 'uid-a',
        );

        expect(report.uploadedCount, 1);
        expect(report.stoppedByNetworkError, isFalse);
        expect(report.remainingPendingCount, 0);
        expect(report.rejectedPhotos, hasLength(1));
        expect(report.rejectedPhotos.single.logId, firstSave.log.id);
        expect(report.rejectedPhotos.single.mealName, 'Cơm sườn ảnh quá lớn');
        expect(report.rejectedPhotos.single.fileName, 'oversized_first.jpg');
        expect(report.rejectedPhotos.single.statusCode, '413');
        expect(report.userMessage, contains('Đã đồng bộ 1 ảnh'));
        expect(report.userMessage, contains('Cơm sườn ảnh quá lớn'));
        expect(report.userMessage, contains('1 MB'));

        // Đảm bảo ảnh thứ hai thực sự đã được gửi sau khi ảnh đầu bị 413.
        expect(
          requestedPaths,
          containsAllInOrder([
            'meal-images/uid-a/${firstSave.log.id}.jpg',
            'meal-images/uid-a/${secondSave.log.id}.jpg',
          ]),
        );
        expect(
          storedObjects.containsKey(
            'meal-images/uid-a/${secondSave.log.id}.jpg',
          ),
          isTrue,
        );
        expect(
          storedObjects.containsKey(
            'meal-images/uid-a/${firstSave.log.id}.jpg',
          ),
          isFalse,
        );

        final logsById = {
          for (final log in await useCase.getMealHistory(ownerUid: 'uid-a'))
            log.id: log,
        };
        expect(logsById[firstSave.log.id]!.imagePath, isNull);
        expect(
          logsById[firstSave.log.id]!.photoUploadStatus,
          MealPhotoUploadStatus.failed,
        );
        expect(
          logsById[secondSave.log.id]!.imagePath,
          'uid-a/${secondSave.log.id}.jpg',
        );
        expect(
          logsById[secondSave.log.id]!.photoUploadStatus,
          MealPhotoUploadStatus.uploaded,
        );

        // Lần bấm đồng bộ tiếp theo không còn bị kẹt ở ảnh đầu đã bị từ chối.
        expect(await useCase.retryPendingPhotoUploads(ownerUid: 'uid-a'), 0);
      },
    );

    test(
      'hàng đợi SQLite có hai ảnh: Storage trả 429 hoặc 500 hoặc lỗi chưa phân loại đều giữ nguyên cả hai ảnh để thử lại',
      () async {
        final storedObjects = <String, Uint8List>{};
        var mode = 'drop'; // 'drop' | '429' | '500' | '200'

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          final bodyBytes = await request.fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          );
          final objectKey = request.uri.path.replaceFirst(
            '/storage/v1/object/',
            '',
          );

          if (mode == 'drop') {
            final socket = await request.response.detachSocket();
            socket.destroy();
            return;
          }
          if (mode == '429') {
            request.response.statusCode = HttpStatus.tooManyRequests;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'statusCode': '429',
                'error': 'TooManyRequests',
                'message': 'Too Many Requests',
              }),
            );
            await request.response.close();
            return;
          }
          if (mode == '500') {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'statusCode': '500',
                'error': 'DatabaseError',
                'message': 'DatabaseError',
              }),
            );
            await request.response.close();
            return;
          }

          storedObjects[objectKey] = bodyBytes.toBytes();
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'Key': objectKey}));
          await request.response.close();
        });

        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'test-publishable-key',
          accessToken: () async => 'test-firebase-jwt',
        );
        final db = LocalDatabase(databasePath: inMemoryDatabasePath);
        addTearDown(() async {
          await db.close();
          await client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        });

        final repo = LocalDatabaseMealLogRepository(db);
        final pendingStore = LocalDatabasePendingMealPhotoStore(db);
        var activeOwner = 'uid-a';
        final storage = SupabasePrivateMealPhotoStorage(
          client,
          currentOwnerUid: () => activeOwner,
        );
        final useCase = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: repo,
          photoPicker: MockMealPhotoPicker(),
          photoStorage: storage,
          pendingPhotoStore: pendingStore,
        );

        await useCase.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Bữa sáng chờ retry 1',
          selectedPhoto: SelectedMealPhoto(
            source: MealPhotoSource.camera,
            fileName: 'p1.jpg',
            mimeType: 'image/jpeg',
            bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await useCase.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Bữa trưa chờ retry 2',
          selectedPhoto: SelectedMealPhoto(
            source: MealPhotoSource.gallery,
            fileName: 'p2.jpg',
            mimeType: 'image/jpeg',
            bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
          ),
        );
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 2);

        activeOwner = 'uid-b';
        final reportAfterSwitch = await useCase.retryPendingPhotoUploadsDetailed(
          ownerUid: 'uid-a',
        );
        expect(reportAfterSwitch.rejectedPhotos, isEmpty);
        expect(reportAfterSwitch.remainingPendingCount, 2);
        activeOwner = 'uid-a';

        // Ca 1: Storage trả 429 Too Many Requests -> giữ nguyên cả 2 ảnh, không báo bị từ chối.
        mode = '429';
        final report429 = await useCase.retryPendingPhotoUploadsDetailed(
          ownerUid: 'uid-a',
        );
        expect(report429.uploadedCount, 0);
        expect(report429.rejectedPhotos, isEmpty);
        expect(report429.stoppedByNetworkError, isTrue);
        expect(report429.remainingPendingCount, 2);
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 2);

        // Ca 2: Storage trả 500 DatabaseError -> giữ nguyên cả 2 ảnh, không báo bị từ chối.
        mode = '500';
        final report500 = await useCase.retryPendingPhotoUploadsDetailed(
          ownerUid: 'uid-a',
        );
        expect(report500.uploadedCount, 0);
        expect(report500.rejectedPhotos, isEmpty);
        expect(report500.stoppedByNetworkError, isTrue);
        expect(report500.remainingPendingCount, 2);
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 2);

        // Ca 3: Lỗi chưa phân loại -> vẫn giữ nguyên cả 2 ảnh để thử lại.
        final unclassifiedUseCase = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: repo,
          photoPicker: MockMealPhotoPicker(),
          photoStorage: _ThrowingUnclassifiedStorage(),
          pendingPhotoStore: pendingStore,
        );
        final reportUnknown = await unclassifiedUseCase
            .retryPendingPhotoUploadsDetailed(ownerUid: 'uid-a');
        expect(reportUnknown.uploadedCount, 0);
        expect(reportUnknown.rejectedPhotos, isEmpty);
        expect(reportUnknown.stoppedByNetworkError, isTrue);
        expect(reportUnknown.remainingPendingCount, 2);
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 2);

        // Khi Storage ổn định trở lại (200 OK) -> cả 2 ảnh được tải lên đầy đủ.
        mode = '200';
        final report200 = await useCase.retryPendingPhotoUploadsDetailed(
          ownerUid: 'uid-a',
        );
        expect(report200.uploadedCount, 2);
        expect(report200.rejectedPhotos, isEmpty);
        expect(report200.remainingPendingCount, 0);
        expect(storedObjects.length, 2);
      },
    );

    test(
      'upload trả 200 nhưng lưu image_path vào SQLite lỗi một lần vẫn giữ ảnh chờ và thành công ở lần retry sau',
      () async {
        final storedObjects = <String, Uint8List>{};
        var dropConnection = true;

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          final bodyBytes = await request.fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          );
          final objectKey = request.uri.path.replaceFirst(
            '/storage/v1/object/',
            '',
          );

          if (dropConnection) {
            final socket = await request.response.detachSocket();
            socket.destroy();
            return;
          }

          storedObjects[objectKey] = bodyBytes.toBytes();
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'Key': objectKey}));
          await request.response.close();
        });

        final client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'test-publishable-key',
          accessToken: () async => 'test-firebase-jwt',
        );
        final db = LocalDatabase(databasePath: inMemoryDatabasePath);
        addTearDown(() async {
          await db.close();
          await client.dispose();
          await subscription.cancel();
          await server.close(force: true);
        });

        final sqliteRepo = LocalDatabaseMealLogRepository(db);
        final flakyRepo = _FailOnceWhenSavingImagePathRepository(sqliteRepo);
        final pendingStore = LocalDatabasePendingMealPhotoStore(db);
        final storage = SupabasePrivateMealPhotoStorage(
          client,
          currentOwnerUid: () => 'uid-a',
        );
        final useCase = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: flakyRepo,
          photoPicker: MockMealPhotoPicker(),
          photoStorage: storage,
          pendingPhotoStore: pendingStore,
        );

        final savedOffline = await useCase.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Bún bò lỗi ghi SQLite',
          selectedPhoto: SelectedMealPhoto(
            source: MealPhotoSource.camera,
            fileName: 'sqlite_retry.jpg',
            mimeType: 'image/jpeg',
            bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
          ),
        );
        expect(savedOffline.photoQueuedForRetry, isTrue);
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 1);

        // Lần retry 1: Storage trả 200 OK nhưng saveMealLog(updatedLog) lỗi cục bộ đúng 1 lần.
        dropConnection = false;
        final firstRetry = await useCase.retryPendingPhotoUploadsDetailed(
          ownerUid: 'uid-a',
        );
        expect(flakyRepo.injectedFailures, 1);
        expect(firstRetry.uploadedCount, 0);
        expect(firstRetry.rejectedPhotos, isEmpty);
        expect(firstRetry.stoppedByNetworkError, isTrue);
        expect(firstRetry.remainingPendingCount, 1);
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 1);

        final logsAfterFailure = await useCase.getMealHistory(
          ownerUid: 'uid-a',
        );
        expect(logsAfterFailure.single.imagePath, isNull);
        expect(
          logsAfterFailure.single.photoUploadStatus,
          MealPhotoUploadStatus.pendingLocal,
        );

        // Lần retry 2: ghi SQLite thành công -> cập nhật được image_path và xóa ảnh chờ.
        final secondRetry = await useCase.retryPendingPhotoUploadsDetailed(
          ownerUid: 'uid-a',
        );
        expect(secondRetry.uploadedCount, 1);
        expect(secondRetry.rejectedPhotos, isEmpty);
        expect(secondRetry.remainingPendingCount, 0);
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 0);

        final logsAfterSuccess = await useCase.getMealHistory(
          ownerUid: 'uid-a',
        );
        expect(logsAfterSuccess, hasLength(1));
        expect(
          logsAfterSuccess.single.imagePath,
          'uid-a/${savedOffline.log.id}.jpg',
        );
        expect(
          logsAfterSuccess.single.photoUploadStatus,
          MealPhotoUploadStatus.uploaded,
        );
      },
    );
  });
}

class _ThrowingUnclassifiedStorage implements MealPhotoStorage {
  @override
  Future<StoredMealPhoto> uploadPrivatePhoto({
    required String ownerUid,
    required String logId,
    required PreparedMealPhoto photo,
    bool isRetry = false,
  }) async {
    throw StateError('Unclassified unexpected storage error');
  }

  @override
  Future<String?> createShortLivedSignedUrl({
    required String ownerUid,
    required String storagePath,
    Duration expiresIn = const Duration(minutes: 10),
  }) async => null;

  @override
  Future<void> deletePrivatePhoto({
    required String ownerUid,
    required String storagePath,
  }) async {}
}

class _FailOnceWhenSavingImagePathRepository implements MealLogRepository {
  final MealLogRepository _delegate;
  int injectedFailures = 0;

  _FailOnceWhenSavingImagePathRepository(this._delegate);

  @override
  Future<List<MealLog>> getMealLogs({required String ownerUid}) {
    return _delegate.getMealLogs(ownerUid: ownerUid);
  }

  @override
  Future<MealLog> saveMealLog(MealLog log) async {
    if (log.hasPhoto && injectedFailures == 0) {
      injectedFailures++;
      throw StateError('Simulated transient SQLite write error');
    }
    return _delegate.saveMealLog(log);
  }

  @override
  Future<void> deleteMealLog({
    required String ownerUid,
    required String logId,
  }) {
    return _delegate.deleteMealLog(ownerUid: ownerUid, logId: logId);
  }
}
