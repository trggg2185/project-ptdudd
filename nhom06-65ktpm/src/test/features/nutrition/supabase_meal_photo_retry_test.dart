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
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_attachment.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_policy.dart';
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
  });
}
