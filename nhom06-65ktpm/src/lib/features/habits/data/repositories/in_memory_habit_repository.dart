import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/entities/streak_info.dart';
import '../../domain/logic/streak_calculator.dart';
import '../../domain/repositories/habit_repository.dart';
import '../fixtures/sample_habits_fixture.dart';

/// Triển khai `HabitRepository` lưu trữ trong bộ nhớ tạm (In-Memory).
///
/// Phục vụ kiểm thử unit/widget và chạy độc lập cho thành viên phát triển module
/// theo đúng quy định phân công và kiến trúc không phụ thuộc backend trực tiếp.
class InMemoryHabitRepository implements HabitRepository {
  final Map<String, Habit> _habits = {};
  final List<HabitLog> _logs = [];

  InMemoryHabitRepository({bool seedWithSamples = false}) {
    if (seedWithSamples) {
      for (final h in SampleHabitsFixture.getSampleHabits()) {
        _habits[h.id] = h;
      }
      _logs.addAll(SampleHabitsFixture.getSampleLogs());
    }
  }

  @override
  Future<List<Habit>> getHabits({String? ownerUid, bool? activeOnly}) async {
    var result = _habits.values.toList();
    if (ownerUid != null && ownerUid.isNotEmpty) {
      result = result.where((h) => h.ownerUid == ownerUid).toList();
    }
    if (activeOnly == true) {
      result = result.where((h) => h.isActive).toList();
    }
    // Sắp xếp theo ngày tạo mới nhất
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<Habit?> getHabitById(String id) async {
    return _habits[id];
  }

  @override
  Future<void> saveHabit(Habit habit) async {
    _habits[habit.id] = habit.copyWith(updatedAt: DateTime.now());
  }

  @override
  Future<void> deleteHabit(String id) async {
    _habits.remove(id);
    _logs.removeWhere((log) => log.habitId == id);
  }

  @override
  Future<void> toggleHabitActive(String id, bool isActive) async {
    final existing = _habits[id];
    if (existing != null) {
      _habits[id] = existing.copyWith(isActive: isActive, updatedAt: DateTime.now());
    }
  }

  @override
  Future<List<HabitLog>> getHabitLogs(
    String habitId, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    return _logs.where((log) {
      if (log.habitId != habitId) return false;
      if (fromDate != null && log.date.isBefore(DateHelper.normalize(fromDate))) return false;
      if (toDate != null && log.date.isAfter(DateHelper.normalize(toDate))) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<List<HabitLog>> getAllLogsForDate(String ownerUid, DateTime date) async {
    final norm = DateHelper.normalize(date);
    return _logs.where((log) {
      if (ownerUid.isNotEmpty && log.userId != ownerUid) return false;
      return DateHelper.isSameDay(log.date, norm);
    }).toList();
  }

  @override
  Future<HabitLog?> getLogForHabitAndDate(String habitId, DateTime date) async {
    final norm = DateHelper.normalize(date);
    for (final log in _logs) {
      if (log.habitId == habitId && DateHelper.isSameDay(log.date, norm)) {
        return log;
      }
    }
    return null;
  }

  @override
  Future<void> recordCheckIn(HabitLog log) async {
    // Đảm bảo chỉ có một bản ghi nhật ký cho một thói quen trong một ngày địa phương
    final normDate = DateHelper.normalize(log.date);
    _logs.removeWhere(
      (existing) => existing.habitId == log.habitId && DateHelper.isSameDay(existing.date, normDate),
    );
    _logs.add(log.copyWith(date: normDate));
  }

  @override
  Future<void> deleteHabitLog(String logId) async {
    _logs.removeWhere((log) => log.id == logId);
  }

  @override
  Future<StreakInfo> getStreakInfo(Habit habit, {DateTime? referenceDate}) async {
    final habitLogs = await getHabitLogs(habit.id);
    return StreakCalculator.calculate(habit, habitLogs, referenceDate: referenceDate);
  }
}
