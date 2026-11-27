import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/meal_log.dart';
import '../../domain/repositories/meal_log_repository.dart';

class SupabaseMealLogRepository implements MealLogRepository {
  const SupabaseMealLogRepository(
    this._client, {
    required this.currentOwnerUid,
  });

  final SupabaseClient _client;
  final String? Function() currentOwnerUid;

  void _requireOwner(String ownerUid) {
    if (ownerUid.isEmpty || currentOwnerUid() != ownerUid) {
      throw StateError('Phiên đăng nhập không khớp nhật ký bữa ăn.');
    }
  }

  Future<void> _ensureProfile(String ownerUid) async {
    _requireOwner(ownerUid);
    await _client
        .from('profiles')
        .upsert(
          {'owner_uid': ownerUid},
          onConflict: 'owner_uid',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<List<MealLog>> getMealLogs({required String ownerUid}) async {
    _requireOwner(ownerUid);
    final rows = await _client
        .from('meal_logs')
        .select()
        .eq('owner_uid', ownerUid)
        .order('consumed_at', ascending: false);
    return rows.map(MealLog.fromMap).toList(growable: false);
  }

  @override
  Future<MealLog> saveMealLog(MealLog log) async {
    await _ensureProfile(log.ownerUid);
    _requireOwner(log.ownerUid);
    await _client.from('meal_logs').upsert({
      'id': log.id,
      'owner_uid': log.ownerUid,
      ...log.toSupabasePayload(),
    }, onConflict: 'id');
    return log;
  }

  @override
  Future<void> deleteMealLog({
    required String ownerUid,
    required String logId,
  }) async {
    _requireOwner(ownerUid);
    await _client
        .from('meal_logs')
        .delete()
        .eq('owner_uid', ownerUid)
        .eq('id', logId);
  }
}
