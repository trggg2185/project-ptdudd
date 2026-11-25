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
  String? _syncWarning;

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

  /// Cảnh báo nhẹ khi thao tác lưu đã thành công nhưng bước tải lại danh sách mới nhất gặp lỗi mạng.
  String? get syncWarning => _syncWarning;

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

  void clearSyncWarning() {
    if (_syncWarning != null) {
      _syncWarning = null;
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
      _syncWarning = null;
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

  void _upsertLocalLog(SleepLog saved) {
    final updated = _sleepLogs.where((l) => l.id != saved.id).toList()
      ..add(saved)
      ..sort((a, b) => b.sleptAt.compareTo(a.sleptAt));
    _sleepLogs = updated;
  }

  /// Lưu mới hoặc cập nhật nhật ký ngủ sau khi xác thực đầy đủ (hỗ trợ qua ngày, ca đêm
  /// và kiểm tra xung đột `baseVersion`).
  ///
  /// Tách biệt rõ bước lưu và bước tải lại: nếu lưu đã thành công nhưng reload gặp lỗi mạng,
  /// vẫn giữ bản đã lưu ở trạng thái local, trả về `true` và hiển thị [syncWarning] thay vì báo lỗi lưu sai.
  Future<bool> saveSleepLog({
    String? existingId,
    required DateTime sleptAt,
    required DateTime wokeAt,
    required AlertnessLevel alertness,
    String? note,
  }) async {
    _actionError = null;
    _syncWarning = null;

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

    late final SleepLog saved;
    try {
      saved = await repository.saveSleepLog(
        candidate,
        baseVersion: existing?.version,
      );
    } on SleepConflictException catch (conflict) {
      if (conflict.serverLog != null) {
        _upsertLocalLog(conflict.serverLog!);
      } else if (existing != null && conflict.serverVersion == null) {
        // Bản ghi không còn tồn tại trên máy chủ (đã bị xóa từ thiết bị khác)
        _sleepLogs = _sleepLogs.where((l) => l.id != existing.id).toList();
      }
      _actionError = conflict.message;
      _isMutating = false;
      notifyListeners();
      return false;
    } catch (error) {
      _actionError = _formatError('Không thể lưu nhật ký giấc ngủ', error);
      _isMutating = false;
      notifyListeners();
      return false;
    }

    // Bước lưu đã thành công: cập nhật ngay bản đã xác nhận từ server
    _upsertLocalLog(saved);
    _actionError = null;

    // Tải lại danh sách là bước đồng bộ bổ sung: lỗi reload không đảo ngược trạng thái đã lưu
    try {
      _sleepLogs = await repository.getSleepLogs(ownerUid: currentUserId);
      _syncWarning = null;
    } catch (_) {
      _syncWarning =
          'Đã lưu nhật ký giấc ngủ thành công, nhưng không thể tải lại danh sách mới nhất từ máy chủ. Bạn có thể bấm Tải lại sau.';
    } finally {
      _isMutating = false;
      notifyListeners();
    }
    return true;
  }

  /// Xóa bản ghi nhật ký ngủ (kèm kiểm tra `baseVersion` để tránh xung đột hai thiết bị).
  Future<bool> deleteSleepLog(String logId) async {
    _actionError = null;
    final existing = _sleepLogs.where((l) => l.id == logId).firstOrNull;
    _isMutating = true;
    notifyListeners();

    try {
      await repository.deleteSleepLog(
        ownerUid: currentUserId,
        logId: logId,
        baseVersion: existing?.version,
      );
      _sleepLogs = _sleepLogs.where((l) => l.id != logId).toList();
      _actionError = null;
      return true;
    } on SleepConflictException catch (conflict) {
      if (conflict.serverLog != null) {
        _upsertLocalLog(conflict.serverLog!);
      } else if (conflict.serverVersion == null) {
        // Bản ghi đã không còn tồn tại trên máy chủ -> loại khỏi danh sách local
        _sleepLogs = _sleepLogs.where((l) => l.id != logId).toList();
      }
      _actionError = conflict.message;
      return false;
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
