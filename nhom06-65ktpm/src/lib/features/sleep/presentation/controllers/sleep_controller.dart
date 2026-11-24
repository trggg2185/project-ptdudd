import 'package:flutter/foundation.dart';

import '../../../../core/utils/date_helper.dart';
import '../../../../core/utils/id_generator.dart';
import '../../domain/entities/routine_block.dart';
import '../../domain/entities/sleep_log.dart';
import '../../domain/entities/sleep_window.dart';
import '../../domain/logic/sleep_schedule_analyzer.dart';
import '../../domain/repositories/sleep_repository.dart';

/// Bộ điều khiển trạng thái (ChangeNotifier) cho module Nhật ký ngủ & Lịch sinh hoạt (Issue #5).
class SleepController extends ChangeNotifier {
  final SleepRepository repository;
  final String currentUserId;
  final DateTime Function() _nowProvider;

  bool _isLoading = false;
  bool _hasLoadedOnce = false;
  bool _isMutating = false;
  String? _loadError;
  String? _actionError;

  List<SleepLog> _sleepLogs = [];
  SleepWindow? _sleepWindow;
  List<RoutineBlock> _routineBlocks = [];
  DateTime _selectedDate;

  SleepController({
    required this.repository,
    required this.currentUserId,
    DateTime Function()? nowProvider,
  })  : _nowProvider = nowProvider ?? DateTime.now,
        _selectedDate = DateHelper.normalize((nowProvider ?? DateTime.now)());

  bool get isLoading => _isLoading;
  bool get hasLoadedOnce => _hasLoadedOnce;
  bool get isMutating => _isMutating;
  String? get loadError => _loadError;
  String? get actionError => _actionError;
  List<SleepLog> get sleepLogs => List.unmodifiable(_sleepLogs);
  SleepWindow? get sleepWindow => _sleepWindow;
  List<RoutineBlock> get routineBlocks => List.unmodifiable(_routineBlocks);
  DateTime get selectedDate => _selectedDate;

  DateTime get now => _nowProvider();

  /// Tổng hợp 7 ngày gần nhất dựa trên `now`.
  SleepWeeklySummary get weeklySummary => SleepScheduleAnalyzer.analyzeWeek(
        _sleepLogs,
        sleepWindow: _sleepWindow,
        referenceDate: _nowProvider(),
      );

  /// Các đoạn lịch sinh hoạt 24 giờ cho ngày đang chọn (`_selectedDate`),
  /// bao gồm tách đoạn qua nửa đêm cho cả ca đêm và giấc ngủ.
  List<DailyTimelineSegment> get segmentsForSelectedDate =>
      SleepScheduleAnalyzer.buildSegmentsForDate(
        targetDate: _selectedDate,
        sleepLogs: _sleepLogs,
        routineBlocks: _routineBlocks,
        sleepWindow: _sleepWindow,
      );

  /// Cảnh báo gợi ý nếu khoảng ngủ mong muốn giao với ca làm/khoảng bận trong ngày đang chọn.
  List<String> get windowConflictsForSelectedDate =>
      SleepScheduleAnalyzer.detectSleepWindowConflicts(
        targetDate: _selectedDate,
        sleepWindow: _sleepWindow,
        routineBlocks: _routineBlocks,
      );

  void clearActionError() {
    if (_actionError != null) {
      _actionError = null;
      notifyListeners();
    }
  }

  /// Tải toàn bộ nhật ký ngủ, khoảng ngủ mong muốn và khối lịch sinh hoạt.
  Future<void> loadAll() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      final results = await Future.wait<Object?>([
        repository.getSleepLogs(ownerUid: currentUserId),
        repository.getSleepWindow(currentUserId),
        repository.getRoutineBlocks(
          ownerUid: currentUserId,
          referenceDate: _selectedDate,
        ),
      ]);

      _sleepLogs = results[0]! as List<SleepLog>;
      _sleepWindow = results[1] as SleepWindow?;
      _routineBlocks = results[2]! as List<RoutineBlock>;
      _hasLoadedOnce = true;
      _loadError = null;
    } catch (error) {
      _loadError = _formatError('Không thể tải dữ liệu giấc ngủ', error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Chuyển ngày đang xem trên lịch sinh hoạt 24 giờ.
  void setSelectedDate(DateTime date) {
    final normalized = DateHelper.normalize(date);
    if (DateHelper.isSameDay(normalized, _selectedDate)) return;
    _selectedDate = normalized;
    notifyListeners();
  }

  /// Dịch chuyển ngày đang xem lùi/tiến [deltaDays] ngày.
  void shiftSelectedDate(int deltaDays) {
    setSelectedDate(DateHelper.shiftDays(_selectedDate, deltaDays));
  }

  /// Lưu mới hoặc cập nhật nhật ký ngủ sau khi xác thực đầy đủ (hỗ trợ qua ngày & ca đêm).
  /// Trả về `true` nếu lưu thành công, `false` nếu có lỗi xác thực hoặc lỗi lưu trữ.
  Future<bool> saveSleepLog({
    String? existingId,
    required DateTime sleptAt,
    required DateTime wokeAt,
    required AlertnessLevel alertness,
    String? note,
  }) async {
    _actionError = null;

    final existing = existingId == null
        ? null
        : _sleepLogs.where((l) => l.id == existingId).firstOrNull;

    final candidate = SleepLog(
      id: existing?.id ?? IdGenerator.generateUuid(),
      ownerUid: currentUserId,
      sleptAt: sleptAt,
      wokeAt: wokeAt,
      alertness: alertness,
      note: (note != null && note.trim().isNotEmpty) ? note.trim() : null,
      createdAt: existing?.createdAt ?? _nowProvider(),
      updatedAt: _nowProvider(),
      version: existing?.version ?? 1,
    );

    try {
      SleepScheduleAnalyzer.validateSleepLog(
        candidate,
        existingLogs: _sleepLogs,
        referenceNow: _nowProvider(),
      );
    } on SleepValidationException catch (validationError) {
      _actionError = validationError.message;
      notifyListeners();
      return false;
    }

    _isMutating = true;
    notifyListeners();

    try {
      await repository.saveSleepLog(candidate);
      _sleepLogs = await repository.getSleepLogs(ownerUid: currentUserId);
      _actionError = null;
      return true;
    } catch (error) {
      _actionError = _formatError('Không thể lưu nhật ký giấc ngủ', error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Xóa bản ghi nhật ký ngủ.
  Future<bool> deleteSleepLog(String logId) async {
    _actionError = null;
    _isMutating = true;
    notifyListeners();

    try {
      await repository.deleteSleepLog(ownerUid: currentUserId, logId: logId);
      _sleepLogs = _sleepLogs.where((l) => l.id != logId).toList();
      _actionError = null;
      return true;
    } catch (error) {
      _actionError = _formatError('Không thể xóa nhật ký giấc ngủ', error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Lưu khoảng ngủ mong muốn mới (hỗ trợ cả ngủ đêm và ca đêm ngủ ban ngày).
  Future<bool> saveSleepWindow(SleepWindow window) async {
    _actionError = null;
    try {
      SleepScheduleAnalyzer.validateSleepWindow(window);
    } on SleepValidationException catch (validationError) {
      _actionError = validationError.message;
      notifyListeners();
      return false;
    }

    _isMutating = true;
    notifyListeners();

    try {
      await repository.saveSleepWindow(ownerUid: currentUserId, window: window);
      _sleepWindow = window;
      _actionError = null;
      return true;
    } catch (error) {
      _actionError = _formatError('Không thể lưu khoảng ngủ mong muốn', error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Xóa khoảng ngủ mong muốn.
  Future<bool> clearSleepWindow() async {
    _actionError = null;
    _isMutating = true;
    notifyListeners();

    try {
      await repository.clearSleepWindow(currentUserId);
      _sleepWindow = null;
      _actionError = null;
      return true;
    } catch (error) {
      _actionError = _formatError('Không thể xóa khoảng ngủ mong muốn', error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  String _formatError(String prefix, Object error) {
    if (error is SleepSyncException) {
      return error.message;
    }
    if (error is SleepValidationException) {
      return error.message;
    }
    return '$prefix. Vui lòng thử lại.';
  }
}
