import '../../domain/entities/meal_log.dart';
import '../../domain/repositories/meal_log_repository.dart';

/// Repository giả lập trong bộ nhớ (mock/fixture) cho nhật ký bữa ăn.
/// Cô lập dữ liệu hoàn toàn theo `ownerUid` để phát triển và kiểm thử độc lập.
class InMemoryMealLogRepository implements MealLogRepository {
  final Map<String, List<MealLog>> _storageByOwner = {};

  @override
  Future<List<MealLog>> getMealLogs({required String ownerUid}) async {
    final logs = List<MealLog>.from(_storageByOwner[ownerUid] ?? const []);
    logs.sort((a, b) => b.consumedAt.compareTo(a.consumedAt));
    return List<MealLog>.unmodifiable(logs);
  }

  @override
  Future<MealLog> saveMealLog(MealLog log) async {
    final list = _storageByOwner.putIfAbsent(log.ownerUid, () => <MealLog>[]);
    final existingIndex = list.indexWhere((item) => item.id == log.id);
    if (existingIndex >= 0) {
      list[existingIndex] = log;
    } else {
      list.add(log);
    }
    return log;
  }

  @override
  Future<void> deleteMealLog({
    required String ownerUid,
    required String logId,
  }) async {
    _storageByOwner[ownerUid]?.removeWhere((item) => item.id == logId);
  }
}
