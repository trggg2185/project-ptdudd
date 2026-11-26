import '../../domain/entities/meal_photo_policy.dart';
import '../../domain/repositories/pending_meal_photo_store.dart';

/// Triển khai trong bộ nhớ của [PendingMealPhotoStore] dùng cho kiểm thử và chế độ mock,
/// cô lập dữ liệu theo từng `ownerUid`.
class InMemoryPendingMealPhotoStore implements PendingMealPhotoStore {
  final Map<String, Map<String, PendingMealPhoto>> _byOwner = {};

  @override
  Future<void> savePendingPhoto({
    required String ownerUid,
    required String logId,
    required PreparedMealPhoto photo,
  }) async {
    final ownerMap = _byOwner.putIfAbsent(
      ownerUid,
      () => <String, PendingMealPhoto>{},
    );
    ownerMap[logId] = PendingMealPhoto(
      ownerUid: ownerUid,
      logId: logId,
      photo: photo,
      queuedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<List<PendingMealPhoto>> getPendingPhotos({
    required String ownerUid,
  }) async {
    final ownerMap = _byOwner[ownerUid];
    if (ownerMap == null || ownerMap.isEmpty) {
      return const [];
    }
    final values = ownerMap.values.toList()
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return List<PendingMealPhoto>.unmodifiable(values);
  }

  @override
  Future<void> removePendingPhoto({
    required String ownerUid,
    required String logId,
  }) async {
    _byOwner[ownerUid]?.remove(logId);
  }

  @override
  Future<void> clearForOwner(String ownerUid) async {
    _byOwner.remove(ownerUid);
  }
}
