import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/local_database.dart';
import '../../../../core/local_sync_worker.dart';
import '../../../profile/data/supabase_profile_repository.dart';
import '../../../profile/domain/health_profile.dart';
import '../../../recommendations/data/repositories/fixture_catalog_repository.dart';
import '../../../recommendations/domain/usecases/get_recommendations_usecase.dart';
import '../../data/repositories/image_picker_meal_photo_picker.dart';
import '../../data/repositories/jpeg_meal_photo_compressor.dart';
import '../../data/repositories/local_database_meal_log_repository.dart';
import '../../data/repositories/local_database_pending_meal_photo_store.dart';
import '../../data/repositories/supabase_meal_log_repository.dart';
import '../../data/repositories/supabase_private_meal_photo_storage.dart';
import '../../domain/services/meal_photo_processor.dart';
import '../../domain/usecases/meal_nutrition_usecase.dart';
import '../widgets/meal_log_composer_view.dart';

class MealJournalPage extends StatefulWidget {
  const MealJournalPage({
    super.key,
    required this.client,
    required this.ownerUid,
    required this.currentOwnerUid,
    this.localDatabase,
  });

  final SupabaseClient client;
  final String ownerUid;
  final String? Function() currentOwnerUid;
  final LocalDatabase? localDatabase;

  @override
  State<MealJournalPage> createState() => _MealJournalPageState();
}

class _MealJournalPageState extends State<MealJournalPage> {
  late final _profile = _loadProfile();
  late final _remoteLogs = SupabaseMealLogRepository(
    widget.client,
    currentOwnerUid: widget.currentOwnerUid,
  );
  late final _useCase = _buildUseCase();

  MealNutritionUseCase _buildUseCase() {
    final db = widget.localDatabase;
    return MealNutritionUseCase(
      recommendationsUseCase: const GetRecommendationsUseCase(
        repository: FixtureCatalogRepository(),
      ),
      mealLogRepository: db == null
          ? _remoteLogs
          : LocalDatabaseMealLogRepository(db),
      pendingPhotoStore: db == null
          ? null
          : LocalDatabasePendingMealPhotoStore(db),
      photoStorage: SupabasePrivateMealPhotoStorage(
        widget.client,
        currentOwnerUid: widget.currentOwnerUid,
      ),
      photoPicker: ImagePickerMealPhotoPicker(),
      photoProcessor: const DefaultMealPhotoProcessor(
        compressor: JpegMealPhotoCompressor(),
      ),
    );
  }

  Future<HealthProfile> _loadProfile() async {
    try {
      return await SupabaseProfileRepository(
        widget.client,
        widget.ownerUid,
      ).loadProfile().timeout(const Duration(seconds: 8));
    } catch (_) {
      // An unconfirmed allergy profile keeps automatic meal suggestions disabled.
      return HealthProfile();
    }
  }

  Future<bool> _syncLogs() async {
    final db = widget.localDatabase!;
    final owner = widget.ownerUid;
    try {
      if (widget.currentOwnerUid() != owner) return false;
      final pending = await db.getPendingChanges(owner);
      if (!pending.any(
        (item) =>
            item['entity_type'] == LocalDatabaseMealLogRepository.entityType,
      )) {
        return true;
      }
      final worker = LocalSyncWorker(
        localDatabase: db,
        transport: SupabaseSyncTransport(
          widget.client,
          currentOwnerUid: widget.currentOwnerUid,
        ),
      );
      await worker.flush(
        owner,
        entityType: LocalDatabaseMealLogRepository.entityType,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nhật ký bữa ăn')),
      body: FutureBuilder<HealthProfile>(
        future: _profile,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return MealLogComposerView(
            ownerUid: widget.ownerUid,
            profile: profile.toRecommendationProfile(),
            useCase: _useCase,
            syncLogs: widget.localDatabase == null ? null : _syncLogs,
          );
        },
      ),
    );
  }
}
