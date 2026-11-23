import '../entities/meal_log.dart';

/// Interface lưu trữ nhật ký bữa ăn độc lập với nguồn dữ liệu (Mock/SQLite/Supabase).
abstract interface class MealLogRepository {
  Future<List<MealLog>> getMealLogs({required String ownerUid});

  Future<MealLog> saveMealLog(MealLog log);

  Future<void> deleteMealLog({
    required String ownerUid,
    required String logId,
  });
}
