import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/local_sync_worker.dart';
import '../../../../core/utils/id_generator.dart';
import '../../domain/entities/routine_block.dart';
import '../../domain/entities/sleep_log.dart';
import '../../domain/entities/sleep_window.dart';
import '../../domain/repositories/sleep_repository.dart';

/// Triển khai `SleepRepository` kết nối Supabase theo cơ chế đồng bộ & kiểm tra xung đột của nhóm:
/// - Ghi/xóa nhật ký ngủ (`sleep_logs`): đi qua RPC `apply_log_sync` thông qua [SyncTransport]
///   (`SupabaseSyncTransport`) có UUID `operation_id`, `p_base_version` và `p_expected_owner_uid`,
///   không âm thầm ghi đè khi hai thiết bị chỉnh sửa cùng bản ghi.
/// - Khoảng ngủ mong muốn (`profiles.living_conditions['healthylife_profile']`):
///   ưu tiên gọi RPC nguyên tử `upsert_sleep_window` (merge theo khóa trong PostgreSQL),
///   và có fallback compare-and-swap (`updated_at` + `version`) trong giai đoạn rollout để không
///   làm mất thay đổi đồng thời từ module Profile/Planner.
/// - Khối lịch sinh hoạt: đọc từ `public.availability_blocks`.
class SupabaseSleepRepository implements SleepRepository {
  static const _profilePreferenceKey = 'healthylife_profile';
  static const _maxCasRetries = 2;

  final SupabaseClient? _client;
  final SyncTransport? _injectedTransport;
  final String? Function() _currentOwnerUid;
  final String Function() _operationIdGenerator;

  SupabaseSleepRepository({
    SupabaseClient? client,
    SyncTransport? syncTransport,
    String? Function()? currentOwnerUid,
    String Function()? operationIdGenerator,
  })  : _client = client ?? _tryDefaultClient(),
        _injectedTransport = syncTransport,
        _currentOwnerUid = currentOwnerUid ?? _defaultFirebaseUid,
        _operationIdGenerator = operationIdGenerator ?? IdGenerator.generateUuid;

  static SupabaseClient? _tryDefaultClient() {
    try {
      return Supabase.instance.isInitialized ? Supabase.instance.client : null;
    } catch (_) {
      return null;
    }
  }

  static String? _defaultFirebaseUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const SleepSyncException(
        'Chưa khởi tạo kết nối Supabase. Vui lòng kiểm tra phiên đăng nhập hoặc mạng.',
      );
    }
    return client;
  }

  SyncTransport _requireTransport() {
    if (_injectedTransport != null) return _injectedTransport;
    final client = _requireClient();
    return SupabaseSyncTransport(client, currentOwnerUid: _currentOwnerUid);
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
          .map(
            (row) => SleepLog.fromSupabaseMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (error) {
      throw SleepSyncException(
        'Không thể tải nhật ký giấc ngủ từ Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<SleepLog> saveSleepLog(SleepLog log, {int? baseVersion}) async {
    final transport = _requireTransport();
    try {
      final result = await transport.apply(
        operationId: _operationIdGenerator(),
        ownerUid: log.ownerUid,
        entityType: 'sleep_log',
        recordId: log.id,
        operation: 'upsert',
        payload: log.toSyncPayload(),
        baseVersion: baseVersion,
      );

      if (result.outcome == 'conflict') {
        final serverLog = result.serverRecord == null
            ? null
            : SleepLog.fromSupabaseMap(
                Map<String, dynamic>.from(result.serverRecord!),
              );
        final deletedOnServer =
            serverLog == null && result.serverVersion == null;
        throw SleepConflictException(
          deletedOnServer
              ? 'Bản ghi giấc ngủ đã bị xóa trên thiết bị khác. Danh sách đã được cập nhật.'
              : 'Bản ghi giấc ngủ đã bị thay đổi trên thiết bị khác. '
                  'Vui lòng tải lại dữ liệu trước khi chỉnh sửa để tránh ghi đè.',
          serverVersion: result.serverVersion,
          serverLog: serverLog,
        );
      }
      if (result.outcome != 'applied') {
        throw SleepSyncException(
          'Phản hồi đồng bộ giấc ngủ không hợp lệ (${result.outcome}).',
        );
      }

      if (result.serverRecord != null) {
        return SleepLog.fromSupabaseMap(
          Map<String, dynamic>.from(result.serverRecord!),
        );
      }
      return log.copyWith(version: result.serverVersion ?? (baseVersion ?? 0) + 1);
    } on SleepSyncException {
      rethrow;
    } on SyncTransportException catch (error) {
      throw SleepSyncException(
        _transportErrorMessage('Không thể lưu nhật ký giấc ngủ', error.code),
        cause: error,
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
    int? baseVersion,
  }) async {
    final transport = _requireTransport();
    try {
      final result = await transport.apply(
        operationId: _operationIdGenerator(),
        ownerUid: ownerUid,
        entityType: 'sleep_log',
        recordId: logId,
        operation: 'delete',
        payload: null,
        baseVersion: baseVersion,
      );

      if (result.outcome == 'conflict') {
        final serverLog = result.serverRecord == null
            ? null
            : SleepLog.fromSupabaseMap(
                Map<String, dynamic>.from(result.serverRecord!),
              );
        final deletedOnServer =
            serverLog == null && result.serverVersion == null;
        throw SleepConflictException(
          deletedOnServer
              ? 'Bản ghi giấc ngủ đã bị xóa ở thiết bị khác trước đó.'
              : 'Bản ghi giấc ngủ đã thay đổi ở thiết bị khác trước khi xóa. '
                  'Vui lòng tải lại dữ liệu.',
          serverVersion: result.serverVersion,
          serverLog: serverLog,
        );
      }
      if (result.outcome != 'applied') {
        throw SleepSyncException(
          'Phản hồi xóa nhật ký giấc ngủ không hợp lệ (${result.outcome}).',
        );
      }
    } on SleepSyncException {
      rethrow;
    } on SyncTransportException catch (error) {
      throw SleepSyncException(
        _transportErrorMessage('Không thể xóa nhật ký giấc ngủ', error.code),
        cause: error,
      );
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
    await _updateSleepWindowAtomic(ownerUid: ownerUid, window: window);
  }

  @override
  Future<void> clearSleepWindow(String ownerUid) async {
    await _updateSleepWindowAtomic(ownerUid: ownerUid, window: null);
  }

  /// Ưu tiên gọi RPC nguyên tử `upsert_sleep_window` (merge chỉ các khóa giấc ngủ trong JSONB).
  /// Nếu RPC chưa được triển khai trên cloud (`PGRST202`), tự động dùng fallback compare-and-swap
  /// kiểm tra `updated_at` và `version` để không ghi đè thay đổi đồng thời từ module khác.
  Future<void> _updateSleepWindowAtomic({
    required String ownerUid,
    required SleepWindow? window,
  }) async {
    final client = _requireClient();
    try {
      await client.rpc(
        'upsert_sleep_window',
        params: {
          'p_sleep_start': window?.startMinute,
          'p_sleep_end': window?.endMinute,
          'p_sleep_label': window?.label,
          'p_expected_owner_uid': ownerUid,
        },
      );
      return;
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202') {
        throw SleepSyncException(
          'Không thể cập nhật khoảng ngủ mong muốn trên Supabase.',
          cause: error,
        );
      }
    } catch (error) {
      throw SleepSyncException(
        'Không thể cập nhật khoảng ngủ mong muốn trên Supabase.',
        cause: error,
      );
    }

    // Fallback compare-and-swap an toàn khi migration 000004 chưa được áp dụng lên cloud
    try {
      if (window != null) {
        await _ensureProfileRow(client, ownerUid);
      }
      for (var attempt = 0; attempt <= _maxCasRetries; attempt++) {
        final current = await client
            .from('profiles')
            .select('living_conditions, updated_at, version')
            .eq('owner_uid', ownerUid)
            .maybeSingle();
        if (current == null) {
          if (window == null) return;
          throw const SleepSyncException('Không tìm thấy hồ sơ để cập nhật khoảng ngủ.');
        }

        final living = Map<String, dynamic>.from(_asMap(current['living_conditions']));
        final prefs = Map<String, dynamic>.from(_asMap(living[_profilePreferenceKey]));
        if (window == null) {
          prefs
            ..remove('sleep_start')
            ..remove('sleep_end')
            ..remove('sleep_label');
        } else {
          prefs.addAll(window.toProfilePreferencePatch());
          if (window.label == null || window.label!.trim().isEmpty) {
            prefs.remove('sleep_label');
          }
        }
        living[_profilePreferenceKey] = prefs;

        final currentVersion = current['version'] as int? ?? 1;
        final written = await client
            .from('profiles')
            .update({
              'living_conditions': living,
              'version': currentVersion + 1,
            })
            .eq('owner_uid', ownerUid)
            .eq('updated_at', current['updated_at'] as String)
            .eq('version', currentVersion)
            .select('owner_uid')
            .maybeSingle();

        if (written != null) return;
      }

      throw const SleepConflictException(
        'Hồ sơ đang được cập nhật đồng thời ở thiết bị hoặc màn hình khác. '
        'Vui lòng thử lưu lại khoảng ngủ mong muốn.',
      );
    } on SleepSyncException {
      rethrow;
    } catch (error) {
      throw SleepSyncException(
        'Không thể cập nhật khoảng ngủ mong muốn trên Supabase.',
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

  static String _transportErrorMessage(String prefix, String code) {
    switch (code) {
      case 'network_unavailable':
        return '$prefix: không có kết nối mạng.';
      case 'network_timeout':
        return '$prefix: kết nối tới máy chủ quá thời gian chờ.';
      case 'server_rejected':
        return '$prefix: máy chủ từ chối dữ liệu (kiểm tra ràng buộc hoặc quyền truy cập).';
      default:
        return '$prefix ($code).';
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
