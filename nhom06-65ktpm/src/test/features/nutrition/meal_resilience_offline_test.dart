import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/core/local_database.dart';
import 'package:healthylife/core/local_sync_worker.dart';
import 'package:healthylife/features/nutrition/data/repositories/in_memory_meal_log_repository.dart';
import 'package:healthylife/features/nutrition/data/repositories/in_memory_pending_meal_photo_store.dart';
import 'package:healthylife/features/nutrition/data/repositories/local_database_meal_log_repository.dart';
import 'package:healthylife/features/nutrition/data/repositories/local_database_pending_meal_photo_store.dart';
import 'package:healthylife/features/nutrition/data/repositories/mock_meal_photo_services.dart';
import 'package:healthylife/features/nutrition/data/repositories/supabase_private_meal_photo_storage.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_access_error.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_attachment.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_policy.dart';
import 'package:healthylife/features/nutrition/domain/repositories/meal_photo_storage.dart';
import 'package:healthylife/features/nutrition/domain/usecases/meal_nutrition_usecase.dart';
import 'package:healthylife/features/nutrition/presentation/widgets/meal_log_composer_view.dart';
import 'package:healthylife/features/recommendations/data/fixtures/sample_profile_fixtures.dart';
import 'package:healthylife/features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'package:healthylife/features/recommendations/domain/usecases/get_recommendations_usecase.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

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

class _ToggleableOfflinePhotoStorage implements MealPhotoStorage {
  bool isOffline;
  final InMemoryPrivateMealPhotoStorage delegate =
      InMemoryPrivateMealPhotoStorage();

  _ToggleableOfflinePhotoStorage({this.isOffline = true});

  @override
  Future<StoredMealPhoto> uploadPrivatePhoto({
    required String ownerUid,
    required String logId,
    required PreparedMealPhoto photo,
    bool isRetry = false,
  }) async {
    if (isOffline) {
      throw const SocketException('No internet connection');
    }
    return delegate.uploadPrivatePhoto(
      ownerUid: ownerUid,
      logId: logId,
      photo: photo,
      isRetry: isRetry,
    );
  }

  @override
  Future<String?> createShortLivedSignedUrl({
    required String ownerUid,
    required String storagePath,
    Duration expiresIn = const Duration(minutes: 10),
  }) {
    return delegate.createShortLivedSignedUrl(
      ownerUid: ownerUid,
      storagePath: storagePath,
      expiresIn: expiresIn,
    );
  }

  @override
  Future<void> deletePrivatePhoto({
    required String ownerUid,
    required String storagePath,
  }) {
    return delegate.deletePrivatePhoto(
      ownerUid: ownerUid,
      storagePath: storagePath,
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Từ chối quyền, ảnh lỗi và fallback nhập tay (Issue #11 - Tiêu chí 3)', () {
    test('từ chối quyền camera hoặc không có thiết bị trả về hướng dẫn nhập tay và không chặn lưu nhật ký', () async {
      final picker = MockMealPhotoPicker(
        onPick: (source) {
          if (source == MealPhotoSource.camera) {
            throw const MealPhotoAccessException(
              MealPhotoAccessFailureCode.cameraPermissionDenied,
              'Camera permission denied',
            );
          }
          throw const MealPhotoAccessException(
            MealPhotoAccessFailureCode.deviceUnavailable,
            'No gallery available',
          );
        },
      );
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: picker,
        photoStorage: InMemoryPrivateMealPhotoStorage(),
      );

      final cameraOutcome = await useCase.pickAndPreparePhoto(
        MealPhotoSource.camera,
      );
      expect(cameraOutcome.hasPhoto, isFalse);
      expect(cameraOutcome.manualFallbackRequired, isTrue);
      expect(
        cameraOutcome.accessError,
        MealPhotoAccessFailureCode.cameraPermissionDenied,
      );
      expect(cameraOutcome.userMessage, contains('nhập tay'));

      final savedManual = await useCase.saveMealLogResilient(
        ownerUid: 'uid-dai',
        confirmedMealName: 'Bún thịt nướng nhập tay',
      );
      expect(savedManual.log.mealName, 'Bún thịt nướng nhập tay');
      expect(savedManual.log.hasPhoto, isFalse);
      expect(savedManual.savedOfflineWithoutCloudPhoto, isFalse);
      expect(savedManual.userMessage, contains('nhập tay'));
    });

    test('ảnh bị lỗi hoặc hỏng trả manualFallbackRequired và không làm crash ứng dụng', () async {
      final picker = MockMealPhotoPicker(
        onPick: (_) => SelectedMealPhoto(
          source: MealPhotoSource.gallery,
          fileName: 'corrupt.jpg',
          mimeType: 'image/jpeg',
          bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x20, 0x01]),
        ),
      );
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: picker,
        photoStorage: InMemoryPrivateMealPhotoStorage(),
      );

      final outcome = await useCase.pickAndPreparePhoto(MealPhotoSource.gallery);
      expect(outcome.hasPhoto, isFalse);
      expect(outcome.manualFallbackRequired, isTrue);
      expect(outcome.photoError, MealPhotoFailureCode.corruptedImage);
      expect(outcome.userMessage, contains('không mất nhật ký'));
    });
  });

  group('Mất mạng không mất nhật ký với LocalDatabase SQLite và retry ảnh (Issue #11 - Tiêu chí 3)', () {
    late LocalDatabase localDatabase;
    late LocalDatabaseMealLogRepository sqliteRepo;
    late InMemoryPendingMealPhotoStore pendingStore;
    late _ToggleableOfflinePhotoStorage offlineStorage;
    late MealNutritionUseCase useCase;

    setUp(() {
      localDatabase = LocalDatabase(databasePath: inMemoryDatabasePath);
      sqliteRepo = LocalDatabaseMealLogRepository(localDatabase);
      pendingStore = InMemoryPendingMealPhotoStore();
      offlineStorage = _ToggleableOfflinePhotoStorage(isOffline: true);
      useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: sqliteRepo,
        photoPicker: MockMealPhotoPicker(),
        photoStorage: offlineStorage,
        pendingPhotoStore: pendingStore,
      );
    });

    tearDown(() async {
      await localDatabase.close();
    });

    test('mất mạng vẫn lưu nhật ký vào SQLite + sync_queue và đồng bộ ảnh lại khi có mạng mà không tạo trùng', () async {
      final photo = SelectedMealPhoto(
        source: MealPhotoSource.camera,
        fileName: 'offline_lunch.jpg',
        mimeType: 'image/jpeg',
        bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
      );

      final saveResult = await useCase.saveMealLogResilient(
        ownerUid: 'uid-a',
        confirmedMealName: 'Cơm gạo lứt cá hồi',
        selectedPhoto: photo,
        note: 'Ghi lúc mất mạng',
      );

      // Không mất nhật ký dù mất mạng
      expect(saveResult.savedOfflineWithoutCloudPhoto, isTrue);
      expect(saveResult.log.mealName, 'Cơm gạo lứt cá hồi');
      expect(saveResult.log.hasPhoto, isFalse); // Không báo upload cloud giả
      expect(
        saveResult.log.photoUploadStatus,
        MealPhotoUploadStatus.pendingLocal,
      );
      expect(saveResult.userMessage, contains('đã được lưu cục bộ'));

      // Bản ghi đã có trong SQLite local_records & sync_queue của LocalDatabase
      final localLogs = await sqliteRepo.getMealLogs(ownerUid: 'uid-a');
      expect(localLogs.length, 1);
      expect(localLogs.single.id, saveResult.log.id);
      final pendingQueue = await localDatabase.getPendingChanges('uid-a');
      expect(pendingQueue.length, 1);
      expect(pendingQueue.single['entity_type'], 'meal_log');
      expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 1);

      // Cô lập tài khoản: retry cho uid-b không được phép đẩy ảnh chờ của uid-a
      offlineStorage.isOffline = false;
      final uploadedForOther = await useCase.retryPendingPhotoUploads(
        ownerUid: 'uid-b',
      );
      expect(uploadedForOther, 0);
      expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 1);

      // Có mạng trở lại -> retry cho uid-a thành công, cập nhật đúng bản ghi cũ, không trùng
      final uploadedForOwner = await useCase.retryPendingPhotoUploads(
        ownerUid: 'uid-a',
      );
      expect(uploadedForOwner, 1);
      expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 0);

      final updatedLogs = await sqliteRepo.getMealLogs(ownerUid: 'uid-a');
      expect(updatedLogs.length, 1);
      expect(updatedLogs.single.id, saveResult.log.id);
      expect(updatedLogs.single.hasPhoto, isTrue);
      expect(updatedLogs.single.imagePath, startsWith('uid-a/'));

      // Đồng bộ hàng đợi SQLite qua LocalSyncWorker khớp hợp đồng entity_type = 'meal_log'
      final transport = _RecordingSyncTransport();
      final worker = LocalSyncWorker(
        localDatabase: localDatabase,
        transport: transport,
      );
      final syncedCount = await worker.flush('uid-a');
      expect(syncedCount, 1);
      expect(transport.calls.length, 1);
      expect(transport.calls.single['ownerUid'], 'uid-a');
      expect(transport.calls.single['entityType'], 'meal_log');
      final syncedPayload =
          transport.calls.single['payload']! as Map<String, Object?>;
      expect(syncedPayload['meal_name'], 'Cơm gạo lứt cá hồi');
      expect(syncedPayload['image_path'], updatedLogs.single.imagePath);
    });

    test('SupabasePrivateMealPhotoStorage chặn lệch ownerUid và logId có path traversal', () async {
      final storage = SupabasePrivateMealPhotoStorage(
        _FakeSupabaseClient(),
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
          ownerUid: 'uid-b',
          logId: 'log-1',
          photo: prepared,
        ),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.invalidOwnerPath,
          ),
        ),
      );
      await expectLater(
        storage.uploadPrivatePhoto(
          ownerUid: 'uid-a',
          logId: '../uid-b/escape',
          photo: prepared,
        ),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.invalidOwnerPath,
          ),
        ),
      );
      expect(
        await storage.createShortLivedSignedUrl(
          ownerUid: 'uid-a',
          storagePath: 'uid-b/other.jpg',
        ),
        isNull,
      );
    });
  });

  group('Widget test fallback nhập tay và mất mạng trên MealLogComposerView (Issue #11 - Tiêu chí 3)', () {
    testWidgets('bị từ chối quyền camera vẫn nhập tay và lưu nhật ký thành công', (
      tester,
    ) async {
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: MockMealPhotoPicker(
          onPick: (_) => throw const MealPhotoAccessException(
            MealPhotoAccessFailureCode.cameraPermissionDenied,
            'Denied',
          ),
        ),
        photoStorage: InMemoryPrivateMealPhotoStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealLogComposerView(
              ownerUid: 'uid-dai',
              profile: SampleProfileFixtures.officeWorkerWalking,
              useCase: useCase,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chụp ảnh bữa ăn'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Quyền Camera bị từ chối'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).first,
        'Phở gà nhập tay',
      );
      await tester.ensureVisible(find.text('Lưu nhật ký bữa ăn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu nhật ký bữa ăn'));
      await tester.pumpAndSettle();

      expect(
        find.text('Đã lưu nhật ký bữa ăn "Phở gà nhập tay" (nhập tay).'),
        findsOneWidget,
      );
    });

    testWidgets('mất mạng khi lưu kèm ảnh vẫn giữ nhật ký và hiện nút đồng bộ ảnh chờ', (
      tester,
    ) async {
      final offlineStorage = _ToggleableOfflinePhotoStorage(isOffline: true);
      final pendingStore = InMemoryPendingMealPhotoStore();
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: MockMealPhotoPicker(),
        photoStorage: offlineStorage,
        pendingPhotoStore: pendingStore,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealLogComposerView(
              ownerUid: 'uid-dai',
              profile: SampleProfileFixtures.officeWorkerWalking,
              useCase: useCase,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chụp ảnh bữa ăn'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Cơm trưa offline',
      );
      await tester.ensureVisible(find.text('Lưu nhật ký bữa ăn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu nhật ký bữa ăn'));
      await tester.pumpAndSettle();

      expect(find.textContaining('đã được lưu cục bộ'), findsOneWidget);
      expect(find.text('Thử đồng bộ 1 ảnh đang chờ'), findsOneWidget);

      // Có mạng lại và bấm nút đồng bộ
      offlineStorage.isOffline = false;
      await tester.ensureVisible(find.text('Thử đồng bộ 1 ảnh đang chờ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thử đồng bộ 1 ảnh đang chờ'));
      await tester.pumpAndSettle();

      expect(find.text('Đã đồng bộ 1 ảnh bữa ăn đang chờ.'), findsOneWidget);
      expect(find.text('Thử đồng bộ 1 ảnh đang chờ'), findsNothing);
    });

    testWidgets(
      'không truyền PendingMealPhotoStore khi mất mạng chỉ báo ghi nhận nhật ký nhập tay',
      (tester) async {
        final offlineStorage = _ToggleableOfflinePhotoStorage(isOffline: true);
        final useCase = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: InMemoryMealLogRepository(),
          photoPicker: MockMealPhotoPicker(),
          photoStorage: offlineStorage,
          pendingPhotoStore: null,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MealLogComposerView(
                ownerUid: 'uid-dai',
                profile: SampleProfileFixtures.officeWorkerWalking,
                useCase: useCase,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Chụp ảnh bữa ăn'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'Bún chả không có kho ảnh chờ',
        );
        await tester.ensureVisible(find.text('Lưu nhật ký bữa ăn'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lưu nhật ký bữa ăn'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Chỉ ghi được nhật ký nhập tay'),
          findsOneWidget,
        );
        expect(find.textContaining('ảnh sẽ đồng bộ khi có mạng'), findsNothing);
        expect(find.textContaining('Thử đồng bộ'), findsNothing);

        final listScrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Ảnh chưa được lưu'),
          200,
          scrollable: listScrollable,
        );
        expect(
          find.text('Ảnh chưa được lưu'),
          findsOneWidget,
        );
      },
    );
  });

  group('Lưu bền vững ảnh chờ qua đóng/mở lại app và báo đúng khi thiếu store (Review fix)', () {
    test(
      'ảnh đã xóa EXIF lưu bền vững trong SQLite theo UID và logId không mất sau khi đóng rồi mở lại app',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'healthylife_pending_photo_restart_',
        );
        final dbPath = p.join(tempDir.path, 'healthylife.db');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final jpegWithExif = MockMealPhotoPicker.buildMinimalValidJpeg(
          app1ExifPayload: utf8.encode('Exif\u0000\u0000GPS_SECRET_COORD'),
        );
        final photo = SelectedMealPhoto(
          source: MealPhotoSource.camera,
          fileName: 'restart_meal.jpg',
          mimeType: 'image/jpeg',
          bytes: jpegWithExif,
        );

        // Phiên 1: Lưu nhật ký + ảnh chờ lúc mất mạng rồi đóng database (đóng app).
        final dbSession1 = LocalDatabase(databasePath: dbPath);
        final useCaseSession1 = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: LocalDatabaseMealLogRepository(dbSession1),
          photoPicker: MockMealPhotoPicker(),
          photoStorage: _ToggleableOfflinePhotoStorage(isOffline: true),
          pendingPhotoStore: LocalDatabasePendingMealPhotoStore(dbSession1),
        );

        final saveResult = await useCaseSession1.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Cháo yến mạch chuối',
          selectedPhoto: photo,
        );
        expect(saveResult.savedOfflineWithoutCloudPhoto, isTrue);
        expect(saveResult.photoQueuedForRetry, isTrue);
        expect(
          saveResult.log.photoUploadStatus,
          MealPhotoUploadStatus.pendingLocal,
        );
        expect(await useCaseSession1.countPendingPhotos(ownerUid: 'uid-a'), 1);
        await dbSession1.close();

        // Phiên 2: Mở lại app từ cùng file SQLite với toàn bộ instance mới.
        final dbSession2 = LocalDatabase(databasePath: dbPath);
        addTearDown(() async => dbSession2.close());
        final onlineStorage = _ToggleableOfflinePhotoStorage(isOffline: false);
        final pendingStoreSession2 = LocalDatabasePendingMealPhotoStore(
          dbSession2,
        );
        final useCaseSession2 = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: LocalDatabaseMealLogRepository(dbSession2),
          photoPicker: MockMealPhotoPicker(),
          photoStorage: onlineStorage,
          pendingPhotoStore: pendingStoreSession2,
        );

        // Ảnh chờ và trạng thái pendingLocal vẫn còn đúng theo UID & logId, cô lập với uid-b.
        expect(await useCaseSession2.countPendingPhotos(ownerUid: 'uid-a'), 1);
        expect(await useCaseSession2.countPendingPhotos(ownerUid: 'uid-b'), 0);

        final pendingItems = await pendingStoreSession2.getPendingPhotos(
          ownerUid: 'uid-a',
        );
        expect(pendingItems, hasLength(1));
        expect(pendingItems.single.logId, saveResult.log.id);
        expect(pendingItems.single.photo.exifStripped, isTrue);

        final historyBeforeRetry = await useCaseSession2.getMealHistory(
          ownerUid: 'uid-a',
        );
        expect(historyBeforeRetry, hasLength(1));
        expect(historyBeforeRetry.single.id, saveResult.log.id);
        expect(historyBeforeRetry.single.imagePath, isNull);
        expect(
          historyBeforeRetry.single.photoUploadStatus,
          MealPhotoUploadStatus.pendingLocal,
        );

        // Khi có mạng ở phiên mới -> retry tải ảnh đã lưu bền vững và gắn image_path vào đúng log cũ.
        final uploaded = await useCaseSession2.retryPendingPhotoUploads(
          ownerUid: 'uid-a',
        );
        expect(uploaded, 1);
        expect(await useCaseSession2.countPendingPhotos(ownerUid: 'uid-a'), 0);

        final historyAfterRetry = await useCaseSession2.getMealHistory(
          ownerUid: 'uid-a',
        );
        expect(historyAfterRetry, hasLength(1));
        expect(historyAfterRetry.single.id, saveResult.log.id);
        expect(
          historyAfterRetry.single.imagePath,
          'uid-a/${saveResult.log.id}.jpg',
        );
        expect(
          historyAfterRetry.single.photoUploadStatus,
          MealPhotoUploadStatus.uploaded,
        );
        expect(
          onlineStorage.delegate.objects['uid-a/${saveResult.log.id}.jpg'],
          equals(pendingItems.single.photo.bytes),
        );
      },
    );

    test(
      'khi không truyền PendingMealPhotoStore và mất mạng, báo đúng chỉ ghi được nhật ký nhập tay',
      () async {
        final repo = InMemoryMealLogRepository();
        final useCase = MealNutritionUseCase(
          recommendationsUseCase: const GetRecommendationsUseCase(
            repository: FixtureCatalogRepository(),
          ),
          mealLogRepository: repo,
          photoPicker: MockMealPhotoPicker(),
          photoStorage: _ToggleableOfflinePhotoStorage(isOffline: true),
          pendingPhotoStore: null,
        );

        final photo = SelectedMealPhoto(
          source: MealPhotoSource.camera,
          fileName: 'no_store_offline.jpg',
          mimeType: 'image/jpeg',
          bytes: MockMealPhotoPicker.buildMinimalValidJpeg(),
        );

        final result = await useCase.saveMealLogResilient(
          ownerUid: 'uid-a',
          confirmedMealName: 'Phở bò nhập tay khi thiếu store',
          selectedPhoto: photo,
        );

        expect(result.savedOfflineWithoutCloudPhoto, isTrue);
        expect(result.photoQueuedForRetry, isFalse);
        expect(result.log.hasPhoto, isFalse);
        expect(result.log.photoSource, isNull);
        expect(result.log.photoUploadStatus, MealPhotoUploadStatus.failed);
        expect(result.userMessage, contains('Chỉ ghi được nhật ký nhập tay'));
        expect(
          result.userMessage,
          isNot(contains('ảnh sẽ đồng bộ khi có mạng')),
        );
        expect(await useCase.countPendingPhotos(ownerUid: 'uid-a'), 0);

        final savedLogs = await repo.getMealLogs(ownerUid: 'uid-a');
        expect(savedLogs, hasLength(1));
        expect(savedLogs.single.mealName, 'Phở bò nhập tay khi thiếu store');
      },
    );
  });
}
