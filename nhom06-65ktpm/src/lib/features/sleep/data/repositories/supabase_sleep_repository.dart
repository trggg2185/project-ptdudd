import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/routine_block.dart';
import '../../domain/entities/sleep_log.dart';
import '../../domain/entities/sleep_window.dart';
import '../../domain/repositories/sleep_repository.dart';

/// Triển khai `SleepRepository` kết nối Supabase theo schema migration của nhóm:
/// - Nhật ký ngủ: bảng `public.sleep_logs` (`slept_at`, `woke_at`, `feeling`, `note`).
/// - Khoảng ngủ mong muốn: lưu vào `public.profiles.living_conditions['healthylife_profile']`
///   (`sleep_start`, `sleep_end`, `sleep_label`) để đồng bộ hai chiều với module Profile (Issue #2).
/// - Khối lịch sinh hoạt: đọc từ `public.availability_blocks` (hỗ trợ cả ca đêm qua nửa đêm).
///
/// Tuyệt đối không nuốt lỗi ngầm; mọi lỗi mạng/quyền/schema được báo qua [SleepSyncException].
class SupabaseSleepRepository implements SleepRepository {
  static const _profilePreferenceKey = 'healthylife_profile';

  final SupabaseClient? _client;

  SupabaseSleepRepository({SupabaseClient? client})
      : _client = client ??
            (Supabase.instance.isInitialized ? Supabase.instance.client : null);

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const SleepSyncException(
        'Chưa khởi tạo kết nối Supabase. Vui lòng kiểm tra phiên đăng nhập hoặc mạng.',
      );
    }
    return client;
  }

  Future<void> _ensureProfileRow(SupabaseClient client, String ownerUid) async {
    await client.from('profiles').upsert(
      {'owner_uid': ownerUid},
      onConflict: 'owner_uid',
      ignoreDuplicates: true,
    );
  }

  @override
  Future<List<SleepLog>> getSleepLogs({
    required String ownerUid,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final client = _requireClient();
    try {
      var query = client.from('sleep_logs').select().eq('owner_uid', ownerUid);
      if (fromDate != null) {
        query = query.gte('woke_at', fromDate.toUtc().toIso8601String());
      }
      if (toDate != null) {
        query = query.lte('slept_at', toDate.toUtc().toIso8601String());
      }

      final response = await query.order('slept_at', ascending: false);
      return (response as List)
          .map((row) => SleepLog.fromSupabaseMap(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (error) {
      throw SleepSyncException(
        'Không thể tải nhật ký giấc ngủ từ Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<void> saveSleepLog(SleepLog log) async {
    final client = _requireClient();
    try {
      await _ensureProfileRow(client, log.ownerUid);
      await client.from('sleep_logs').upsert(
            log.toSupabaseMap(),
            onConflict: 'id',
          );
    } catch (error) {
      throw SleepSyncException(
        'Không thể lưu nhật ký giấc ngủ lên Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<void> deleteSleepLog({
    required String ownerUid,
    required String logId,
  }) async {
    final client = _requireClient();
    try {
      await client
          .from('sleep_logs')
          .delete()
          .eq('owner_uid', ownerUid)
          .eq('id', logId);
    } catch (error) {
      throw SleepSyncException(
        'Không thể xóa nhật ký giấc ngủ trên Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<SleepWindow?> getSleepWindow(String ownerUid) async {
    final client = _requireClient();
    try {
      final row = await client
          .from('profiles')
          .select('living_conditions')
          .eq('owner_uid', ownerUid)
          .maybeSingle();
      if (row == null) return null;

      final living = _asMap(row['living_conditions']);
      final prefs = _asMap(living[_profilePreferenceKey]);
      return SleepWindow.fromProfilePreferences(prefs);
    } catch (error) {
      throw SleepSyncException(
        'Không thể tải khoảng ngủ mong muốn từ hồ sơ Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<void> saveSleepWindow({
    required String ownerUid,
    required SleepWindow window,
  }) async {
    final client = _requireClient();
    try {
      await _ensureProfileRow(client, ownerUid);
      final current = await client
          .from('profiles')
          .select('living_conditions')
          .eq('owner_uid', ownerUid)
          .single();

      final living = Map<String, dynamic>.from(_asMap(current['living_conditions']));
      final prefs = Map<String, dynamic>.from(_asMap(living[_profilePreferenceKey]));
      prefs.addAll(window.toProfilePreferencePatch());
      if (window.label == null || window.label!.trim().isEmpty) {
        prefs.remove('sleep_label');
      }
      living[_profilePreferenceKey] = prefs;

      await client
          .from('profiles')
          .update({'living_conditions': living})
          .eq('owner_uid', ownerUid);
    } catch (error) {
      throw SleepSyncException(
        'Không thể lưu khoảng ngủ mong muốn lên Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<void> clearSleepWindow(String ownerUid) async {
    final client = _requireClient();
    try {
      final current = await client
          .from('profiles')
          .select('living_conditions')
          .eq('owner_uid', ownerUid)
          .maybeSingle();
      if (current == null) return;

      final living = Map<String, dynamic>.from(_asMap(current['living_conditions']));
      final prefs = Map<String, dynamic>.from(_asMap(living[_profilePreferenceKey]));
      prefs
        ..remove('sleep_start')
        ..remove('sleep_end')
        ..remove('sleep_label');
      living[_profilePreferenceKey] = prefs;

      await client
          .from('profiles')
          .update({'living_conditions': living})
          .eq('owner_uid', ownerUid);
    } catch (error) {
      throw SleepSyncException(
        'Không thể xóa khoảng ngủ mong muốn trên Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<List<RoutineBlock>> getRoutineBlocks({
    required String ownerUid,
    DateTime? referenceDate,
  }) async {
    final client = _requireClient();
    try {
      final rows = await client
          .from('availability_blocks')
          .select()
          .eq('owner_uid', ownerUid)
          .order('start_at');

      return (rows as List).map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final kind = _parseRoutineKind(row['recurrence_rule'] as String?);
        return RoutineBlock(
          id: row['id'] as String,
          title: row['title'] as String? ?? 'Khoảng bận',
          kind: kind,
          startsAt: DateTime.parse(row['start_at'] as String).toLocal(),
          endsAt: DateTime.parse(row['end_at'] as String).toLocal(),
          travelMinutes: row['travel_minutes'] as int? ?? 0,
        );
      }).toList();
    } catch (error) {
      throw SleepSyncException(
        'Không thể tải lịch sinh hoạt từ Supabase.',
        cause: error,
      );
    }
  }

  static RoutineBlockKind _parseRoutineKind(String? recurrenceRule) {
    if (recurrenceRule != null && recurrenceRule.trimLeft().startsWith('{')) {
      try {
        final decoded = jsonDecode(recurrenceRule);
        if (decoded is Map && decoded['kind'] == 'shift') {
          return RoutineBlockKind.workShift;
        }
      } catch (_) {
        // Bỏ qua nếu không phải JSON
      }
    }
    return RoutineBlockKind.busy;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }
}
