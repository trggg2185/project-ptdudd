import 'package:flutter/foundation.dart';

import '../../../../core/utils/date_helper.dart';
import '../../../../core/utils/id_generator.dart';
import '../../data/repositories/supabase_habit_repository.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/entities/streak_info.dart';
import '../../domain/logic/streak_calculator.dart';
import '../../domain/repositories/habit_repository.dart';

/// Bộ điều khiển trạng thái (Controller/Notifier) cho module Thói quen và Kỷ luật.
class HabitController extends ChangeNotifier {
  final HabitRepository repository;
  final String currentUserId;

  bool _isLoading = false;
  String? _errorMessage;
  List<Habit> _habits = [];
  Map<String, HabitLog?> _selectedDateLogs = {};
  Map<String, StreakInfo> _streakInfos = {};
  DateTime _selectedDate = DateHelper.normalize(DateTime.now());
  String _filter = 'active'; // 'all', 'active', 'paused'

  HabitController({
    required this.repository,
    this.currentUserId = '',
  });

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Habit> get habits => _habits;
  DateTime get selectedDate => _selectedDate;
  String get filter => _filter;
  Map<String, HabitLog?> get selectedDateLogs => _selectedDateLogs;
  Map<String, StreakInfo> get streakInfos => _streakInfos;

  /// Danh sách thói quen sau khi áp dụng bộ lọc.
  List<Habit> get filteredHabits {
    switch (_filter) {
      case 'active':
        return _habits.where((h) => h.isActive).toList();
      case 'paused':
        return _habits.where((h) => !h.isActive).toList();
      case 'all':
      default:
        return _habits;
    }
  }

  /// Số thói quen đến hạn trong ngày đang chọn.
  int get dueCountForSelectedDate {
    if (DateHelper.isFutureDay(_selectedDate, DateTime.now())) return 0;
    return _habits.where((h) => h.isActive && h.getFrequencyOn(_selectedDate).isDueOn(_selectedDate)).length;
  }

  /// Số thói quen đã hoàn thành trong ngày đang chọn.
  int get completedCountForSelectedDate {
    int count = 0;
    for (final h in _habits) {
      if (!h.isActive) continue;
      final log = _selectedDateLogs[h.id];
      if (log != null && log.status == CheckInStatus.completed) {
        count++;
      }
    }
    return count;
  }

  /// Tỷ lệ hoàn thành trong ngày đang chọn (0.0 đến 1.0).
  double get progressRatioForSelectedDate {
    final due = dueCountForSelectedDate;
    if (due == 0) return 0.0;
    return (completedCountForSelectedDate / due).clamp(0.0, 1.0);
  }

  /// Tải lại danh sách thói quen và trạng thái check-in.
  Future<void> loadHabits() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _habits = await repository.getHabits(ownerUid: currentUserId);
      await _refreshDayLogsAndStreaks();
    } catch (e) {
      _errorMessage = _formatErrorMessage('Không thể tải danh sách thói quen', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Đổi ngày đang xem (hôm nay, hôm qua, hoặc một ngày bất kỳ).
  Future<void> setSelectedDate(DateTime newDate) async {
    _selectedDate = DateHelper.normalize(newDate);
    await _refreshDayLogsAndStreaks();
    notifyListeners();
  }

  /// Đổi bộ lọc danh sách thói quen ('all', 'active', 'paused').
  void setFilter(String newFilter) {
    _filter = newFilter;
    notifyListeners();
  }

  /// Ghi nhận Check-in cho thói quen.
  /// Chặn tuyệt đối hành vi ghi nhận check-in vào ngày tương lai (P1 Finding).
  Future<void> checkInHabit({
    required String habitId,
    CheckInStatus status = CheckInStatus.completed,
    String? reason,
  }) async {
    // 1. Chặn tương lai:
    if (DateHelper.isFutureDay(_selectedDate, DateTime.now())) {
      _errorMessage = 'Không thể ghi nhận check-in cho ngày trong tương lai.';
      notifyListeners();
      return;
    }

    try {
      final log = HabitLog(
        id: IdGenerator.generateUuid(),
        habitId: habitId,
        userId: currentUserId,
        date: _selectedDate,
        status: status,
        reason: reason,
        loggedAt: DateTime.now(),
      );

      await repository.recordCheckIn(log);
      _selectedDateLogs[habitId] = log;

      // Cập nhật lại streak cho thói quen này
      final habit = _habits.firstWhere((h) => h.id == habitId);
      _streakInfos[habitId] = await repository.getStreakInfo(habit, referenceDate: _selectedDate);

      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = _formatErrorMessage('Lỗi khi ghi nhận check-in', e);
      notifyListeners();
    }
  }

  /// Hủy check-in trong ngày đang chọn (hoàn tác).
  Future<void> undoCheckIn(String habitId) async {
    final existingLog = _selectedDateLogs[habitId];
    if (existingLog == null) return;

    try {
      await repository.deleteHabitLog(existingLog.id);
      _selectedDateLogs.remove(habitId);

      final habit = _habits.firstWhere((h) => h.id == habitId);
      _streakInfos[habitId] = await repository.getStreakInfo(habit, referenceDate: _selectedDate);

      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = _formatErrorMessage('Lỗi khi hủy check-in', e);
      notifyListeners();
    }
  }

  /// Tạo thói quen mới.
  Future<void> createHabit(Habit habit) async {
    _isLoading = true;
    notifyListeners();

    try {
      await repository.saveHabit(habit);
      _habits.insert(0, habit);
      _streakInfos[habit.id] = await repository.getStreakInfo(habit, referenceDate: _selectedDate);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = _formatErrorMessage('Không thể tạo thói quen', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Cập nhật thông tin thói quen đã có.
  /// Lưu lại lịch sử chu kỳ nếu có thay đổi chu kỳ để bảo toàn streak quá khứ (P1 Finding).
  Future<void> updateHabit(Habit updatedHabit) async {
    _isLoading = true;
    notifyListeners();

    try {
      final index = _habits.indexWhere((h) => h.id == updatedHabit.id);
      Habit habitToSave = updatedHabit;

      if (index != -1) {
        final existing = _habits[index];
        // Nếu chu kỳ lặp thay đổi: ghi nhận mốc lịch mới có hiệu lực từ hôm nay
        if (existing.frequency != updatedHabit.frequency) {
          final newHistory = List<FrequencySchedule>.from(existing.frequencyHistory);
          newHistory.add(
            FrequencySchedule(
              frequency: updatedHabit.frequency,
              effectiveFrom: DateHelper.normalize(DateTime.now()),
            ),
          );
          habitToSave = updatedHabit.copyWith(frequencyHistory: newHistory);
        }
      }

      await repository.saveHabit(habitToSave);

      if (index != -1) {
        _habits[index] = habitToSave;
      }
      _streakInfos[habitToSave.id] = await repository.getStreakInfo(habitToSave, referenceDate: _selectedDate);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = _formatErrorMessage('Không thể cập nhật thói quen', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Bật/tắt kích hoạt thói quen (tạm dừng / tiếp tục).
  /// Lưu danh sách các khoảng tạm dừng (`pauseHistory`) để bảo toàn chuỗi streak khi tiếp tục lại (P1 Finding).
  Future<void> toggleActive(String habitId) async {
    try {
      final habit = _habits.firstWhere((h) => h.id == habitId);
      final newActiveState = !habit.isActive;
      final now = DateTime.now();

      final newHistory = List<PauseInterval>.from(habit.pauseHistory);
      DateTime? newPausedAt;

      if (!newActiveState) {
        // Chuyển sang tạm dừng: mở khoảng tạm dừng mới
        newPausedAt = now;
        newHistory.add(PauseInterval(pausedAt: now));
      } else {
        // Tiếp tục thói quen: đóng khoảng tạm dừng gần nhất với resumedAt = now
        newPausedAt = null;
        if (newHistory.isNotEmpty && newHistory.last.resumedAt == null) {
          final last = newHistory.removeLast();
          newHistory.add(PauseInterval(
            pausedAt: last.pausedAt,
            resumedAt: now,
          ));
        } else if (habit.pausedAt != null) {
          newHistory.add(PauseInterval(
            pausedAt: habit.pausedAt!,
            resumedAt: now,
          ));
        }
      }

      final updated = habit.copyWith(
        isActive: newActiveState,
        pausedAt: newPausedAt,
        clearPausedAt: newActiveState,
        pauseHistory: newHistory,
      );

      await repository.saveHabit(updated);
      await repository.toggleHabitActive(habitId, newActiveState);

      final index = _habits.indexWhere((h) => h.id == habitId);
      if (index != -1) {
        _habits[index] = updated;
      }
      _streakInfos[habitId] = await repository.getStreakInfo(updated, referenceDate: _selectedDate);

      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = _formatErrorMessage('Không thể chuyển trạng thái thói quen', e);
      notifyListeners();
    }
  }

  /// Xóa thói quen.
  Future<void> deleteHabit(String habitId) async {
    try {
      await repository.deleteHabit(habitId);
      _habits.removeWhere((h) => h.id == habitId);
      _selectedDateLogs.remove(habitId);
      _streakInfos.remove(habitId);
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = _formatErrorMessage('Không thể xóa thói quen', e);
      notifyListeners();
    }
  }

  /// Lấy trạng thái tổng hợp của một thói quen trong ngày đang chọn.
  HabitDayStatus getDayStatusForHabit(Habit habit) {
    final log = _selectedDateLogs[habit.id];
    final logs = log != null ? [log] : <HabitLog>[];
    return StreakCalculator.getDayStatus(
      habit,
      logs,
      _selectedDate,
      referenceDate: DateHelper.normalize(DateTime.now()),
    );
  }

  /// Tải lại nhật ký check-in của ngày được chọn và tính lại toàn bộ streak.
  Future<void> _refreshDayLogsAndStreaks() async {
    final Map<String, HabitLog?> logsMap = {};
    final Map<String, StreakInfo> streakMap = {};

    for (final habit in _habits) {
      final log = await repository.getLogForHabitAndDate(habit.id, _selectedDate);
      logsMap[habit.id] = log;

      final streak = await repository.getStreakInfo(habit, referenceDate: _selectedDate);
      streakMap[habit.id] = streak;
    }

    _selectedDateLogs = logsMap;
    _streakInfos = streakMap;
  }

  String _formatErrorMessage(String prefix, Object error) {
    if (error is HabitSyncException) {
      return '$prefix: ${error.message}';
    }
    return '$prefix: $error';
  }
}
