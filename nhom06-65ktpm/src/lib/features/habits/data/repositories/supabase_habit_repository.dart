import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/entities/streak_info.dart';
import '../../domain/logic/streak_calculator.dart';
import '../../domain/repositories/habit_repository.dart';
import 'in_memory_habit_repository.dart';

/// Ngoại lệ ném ra khi thao tác đồng bộ với Supabase thất bại.
/// Không nuốt lỗi ngầm để controller và UI xử lý thông báo trung thực cho người dùng.
class HabitSyncException implements Exception {
  final String message;
  final Object? cause;

  HabitSyncException(this.message, {this.cause});

  @override
  String toString() => 'HabitSyncException: $message ${cause != null ? '($cause)' : ''}';
}

/// Triển khai `HabitRepository` kết nối cơ sở dữ liệu Supabase theo đúng schema
/// đã định nghĩa trong file migration `20261121_000001_initial_healthy_life_schema.sql`.
///
/// Báo lỗi rõ ràng qua `HabitSyncException` khi ghi/đồng bộ Supabase thất bại.
class SupabaseHabitRepository implements HabitRepository {
  final SupabaseClient? _client;
  final InMemoryHabitRepository _fallbackRepo = InMemoryHabitRepository(seedWithSamples: false);

  SupabaseHabitRepository({SupabaseClient? client})
      : _client = client ?? (Supabase.instance.isInitialized ? Supabase.instance.client : null);

  bool get _isOnline => _client != null;

  @override
  Future<List<Habit>> getHabits({String? ownerUid, bool? activeOnly}) async {
    if (!_isOnline) {
      return _fallbackRepo.getHabits(ownerUid: ownerUid, activeOnly: activeOnly);
    }

    try {
      var query = _client!.from('habits').select();
      if (ownerUid != null && ownerUid.isNotEmpty) {
        query = query.eq('owner_uid', ownerUid);
      }
      if (activeOnly == true) {
        query = query.eq('is_active', true);
      }

      final response = await query.order('created_at', ascending: false);
      final list = (response as List).map((row) => Habit.fromSupabaseMap(row as Map<String, dynamic>)).toList();

      for (final h in list) {
        await _fallbackRepo.saveHabit(h);
      }
      return list;
    } catch (e) {
      throw HabitSyncException('Không thể tải danh sách thói quen từ Supabase: $e', cause: e);
    }
  }

  @override
  Future<Habit?> getHabitById(String id) async {
    if (!_isOnline) {
      return _fallbackRepo.getHabitById(id);
    }

    try {
      final response = await _client!.from('habits').select().eq('id', id).maybeSingle();
      if (response == null) return null;
      final habit = Habit.fromSupabaseMap(response);
      await _fallbackRepo.saveHabit(habit);
      return habit;
    } catch (e) {
      throw HabitSyncException('Không thể tải thói quen $id từ Supabase: $e', cause: e);
    }
  }

  @override
  Future<void> saveHabit(Habit habit) async {
    if (_isOnline) {
      try {
        await _client!.from('profiles').upsert(
          {'owner_uid': habit.ownerUid},
          onConflict: 'owner_uid',
          ignoreDuplicates: true,
        );
        await _client.from('habits').upsert(habit.toSupabaseMap());
        await _fallbackRepo.saveHabit(habit);
      } catch (e) {
        throw HabitSyncException('Không thể lưu thói quen "${habit.name}" lên Supabase: $e', cause: e);
      }
    } else {
      await _fallbackRepo.saveHabit(habit);
    }
  }

  @override
  Future<void> deleteHabit(String id) async {
    if (_isOnline) {
      try {
        await _client!.from('habits').delete().eq('id', id);
        await _fallbackRepo.deleteHabit(id);
      } catch (e) {
        throw HabitSyncException('Không thể xóa thói quen trên Supabase: $e', cause: e);
      }
    } else {
      await _fallbackRepo.deleteHabit(id);
    }
  }

  @override
  Future<void> toggleHabitActive(String id, bool isActive) async {
    if (_isOnline) {
      try {
        final now = DateTime.now().toUtc();
        await _client!.from('habits').update({
          'is_active': isActive,
          'updated_at': now.toIso8601String(),
        }).eq('id', id);
        await _fallbackRepo.toggleHabitActive(id, isActive);
      } catch (e) {
        throw HabitSyncException('Không thể cập nhật trạng thái thói quen trên Supabase: $e', cause: e);
      }
    } else {
      await _fallbackRepo.toggleHabitActive(id, isActive);
    }
  }

  @override
  Future<List<HabitLog>> getHabitLogs(
    String habitId, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    if (!_isOnline) {
      return _fallbackRepo.getHabitLogs(habitId, fromDate: fromDate, toDate: toDate);
    }

    try {
      var query = _client!.from('habit_logs').select().eq('habit_id', habitId);
      if (fromDate != null) {
        query = query.gte('local_date', DateHelper.formatIsoDate(fromDate));
      }
      if (toDate != null) {
        query = query.lte('local_date', DateHelper.formatIsoDate(toDate));
      }

      final response = await query.order('local_date', ascending: false);
      final list = (response as List).map((row) => HabitLog.fromSupabaseMap(row as Map<String, dynamic>)).toList();
      for (final log in list) {
        await _fallbackRepo.recordCheckIn(log);
      }
      return list;
    } catch (e) {
      throw HabitSyncException('Không thể tải nhật ký thói quen từ Supabase: $e', cause: e);
    }
  }

  @override
  Future<List<HabitLog>> getAllLogsForDate(String ownerUid, DateTime date) async {
    if (!_isOnline) {
      return _fallbackRepo.getAllLogsForDate(ownerUid, date);
    }

    try {
      final isoDate = DateHelper.formatIsoDate(date);
      var query = _client!.from('habit_logs').select().eq('local_date', isoDate);
      if (ownerUid.isNotEmpty) {
        query = query.eq('owner_uid', ownerUid);
      }
      final response = await query;
      final list = (response as List).map((row) => HabitLog.fromSupabaseMap(row as Map<String, dynamic>)).toList();
      for (final log in list) {
        await _fallbackRepo.recordCheckIn(log);
      }
      return list;
    } catch (e) {
      throw HabitSyncException('Không thể tải nhật ký ngày $date từ Supabase: $e', cause: e);
    }
  }

  @override
  Future<HabitLog?> getLogForHabitAndDate(String habitId, DateTime date) async {
    if (!_isOnline) {
      return _fallbackRepo.getLogForHabitAndDate(habitId, date);
    }

    try {
      final isoDate = DateHelper.formatIsoDate(date);
      final response = await _client!
          .from('habit_logs')
          .select()
          .eq('habit_id', habitId)
          .eq('local_date', isoDate)
          .maybeSingle();

      if (response == null) return null;
      final log = HabitLog.fromSupabaseMap(response);
      await _fallbackRepo.recordCheckIn(log);
      return log;
    } catch (e) {
      throw HabitSyncException('Không thể kiểm tra nhật ký check-in từ Supabase: $e', cause: e);
    }
  }

  @override
  Future<void> recordCheckIn(HabitLog log) async {
    if (_isOnline) {
      try {
        await _client!.from('habit_logs').insert(log.toSupabaseMap());
        await _fallbackRepo.recordCheckIn(log);
      } on PostgrestException catch (error) {
        if (error.code == '23505') {
          throw HabitSyncException(
            'Ngày này đã được ghi nhận. Tải lại dữ liệu để xem kết quả.',
          );
        }
        throw HabitSyncException('Lỗi ghi nhận check-in lên Supabase.', cause: error);
      } catch (e) {
        throw HabitSyncException('Lỗi ghi nhận check-in lên Supabase: $e', cause: e);
      }
    } else {
      await _fallbackRepo.recordCheckIn(log);
    }
  }

  @override
  Future<void> deleteHabitLog(String logId) async {
    if (_isOnline) {
      try {
        await _client!.from('habit_logs').delete().eq('id', logId);
        await _fallbackRepo.deleteHabitLog(logId);
      } catch (e) {
        throw HabitSyncException('Lỗi hủy check-in trên Supabase: $e', cause: e);
      }
    } else {
      await _fallbackRepo.deleteHabitLog(logId);
    }
  }

  @override
  Future<StreakInfo> getStreakInfo(Habit habit, {DateTime? referenceDate}) async {
    final logs = await getHabitLogs(habit.id);
    return StreakCalculator.calculate(habit, logs, referenceDate: referenceDate);
  }
}
