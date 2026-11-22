import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/entities/streak_info.dart';
import '../../domain/logic/streak_calculator.dart';
import '../../domain/repositories/habit_repository.dart';
import 'in_memory_habit_repository.dart';

/// Triển khai `HabitRepository` kết nối cơ sở dữ liệu Supabase theo đúng schema
/// đã định nghĩa trong file migration `20261121_000001_initial_healthy_life_schema.sql`.
///
/// Tự động fallback sang cache/in-memory nếu Supabase chưa được khởi tạo hoặc mất mạng.
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
    } catch (_) {
      return _fallbackRepo.getHabits(ownerUid: ownerUid, activeOnly: activeOnly);
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
    } catch (_) {
      return _fallbackRepo.getHabitById(id);
    }
  }

  @override
  Future<void> saveHabit(Habit habit) async {
    await _fallbackRepo.saveHabit(habit);
    if (!_isOnline) return;

    try {
      await _client!.from('habits').upsert(habit.toSupabaseMap());
    } catch (_) {
      // Lưu ở local để đồng bộ sau (sync queue)
    }
  }

  @override
  Future<void> deleteHabit(String id) async {
    await _fallbackRepo.deleteHabit(id);
    if (!_isOnline) return;

    try {
      await _client!.from('habits').delete().eq('id', id);
    } catch (_) {}
  }

  @override
  Future<void> toggleHabitActive(String id, bool isActive) async {
    await _fallbackRepo.toggleHabitActive(id, isActive);
    if (!_isOnline) return;

    try {
      await _client!.from('habits').update({
        'is_active': isActive,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (_) {}
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
    } catch (_) {
      return _fallbackRepo.getHabitLogs(habitId, fromDate: fromDate, toDate: toDate);
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
    } catch (_) {
      return _fallbackRepo.getAllLogsForDate(ownerUid, date);
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
    } catch (_) {
      return _fallbackRepo.getLogForHabitAndDate(habitId, date);
    }
  }

  @override
  Future<void> recordCheckIn(HabitLog log) async {
    await _fallbackRepo.recordCheckIn(log);
    if (!_isOnline) return;

    try {
      // Upsert dựa trên ràng buộc unique: (owner_uid, habit_id, local_date)
      await _client!.from('habit_logs').upsert(
            log.toSupabaseMap(),
            onConflict: 'owner_uid,habit_id,local_date',
          );
    } catch (_) {}
  }

  @override
  Future<void> deleteHabitLog(String logId) async {
    await _fallbackRepo.deleteHabitLog(logId);
    if (!_isOnline) return;

    try {
      await _client!.from('habit_logs').delete().eq('id', logId);
    } catch (_) {}
  }

  @override
  Future<StreakInfo> getStreakInfo(Habit habit, {DateTime? referenceDate}) async {
    final logs = await getHabitLogs(habit.id);
    return StreakCalculator.calculate(habit, logs, referenceDate: referenceDate);
  }
}
