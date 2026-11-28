import 'package:flutter/foundation.dart';

import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/weekly_insights_summary.dart';
import '../../domain/services/weekly_insights_aggregator.dart';
import '../../domain/usecases/get_weekly_insights_usecase.dart';

/// Controller quản lý trạng thái tải, chuyển tuần và cô lập tài khoản cho Dashboard tuần (Issue #12).
class WeeklyInsightsController extends ChangeNotifier {
  final GetWeeklyInsightsUseCase useCase;
  final DateTime? fixedReferenceDate;

  String _ownerUid;
  DateTime _selectedWeekStart;
  WeeklyInsightsSummary? _summary;
  bool _loading = false;
  String? _errorMessage;
  int _loadToken = 0;
  bool _disposed = false;

  WeeklyInsightsController({
    required this.useCase,
    required String ownerUid,
    DateTime? initialWeekAnchor,
    this.fixedReferenceDate,
  }) : _ownerUid = ownerUid.trim(),
       _selectedWeekStart = WeeklyInsightsAggregator.startOfWeek(
         initialWeekAnchor ?? fixedReferenceDate ?? DateTime.now(),
       );

  String get ownerUid => _ownerUid;
  DateTime get referenceDate =>
      DateHelper.normalize(fixedReferenceDate ?? DateTime.now());
  DateTime get selectedWeekStart => _selectedWeekStart;
  DateTime get selectedWeekEnd => DateHelper.shiftDays(_selectedWeekStart, 6);
  WeeklyInsightsSummary? get summary => _summary;
  bool get isLoading => _loading;
  String? get errorMessage => _errorMessage;

  bool get canGoToNextWeek {
    final currentWeekStart = WeeklyInsightsAggregator.startOfWeek(
      referenceDate,
    );
    return _selectedWeekStart.isBefore(currentWeekStart);
  }

  bool get isCurrentWeek {
    final currentWeekStart = WeeklyInsightsAggregator.startOfWeek(
      referenceDate,
    );
    return DateHelper.isSameDay(_selectedWeekStart, currentWeekStart);
  }

  /// Tải dữ liệu tổng hợp tuần cho tài khoản hiện tại; bỏ qua phản hồi cũ nếu người dùng
  /// đổi tuần hoặc đổi tài khoản giữa chừng.
  Future<void> load() async {
    final token = ++_loadToken;
    final targetOwner = _ownerUid;
    final targetWeek = _selectedWeekStart;

    _loading = true;
    _errorMessage = null;
    _notifySafely();

    try {
      final result = await useCase(
        ownerUid: targetOwner,
        weekAnchorDate: targetWeek,
        referenceDate: referenceDate,
      );
      if (_disposed || token != _loadToken) return;
      _summary = result;
      _errorMessage = null;
    } catch (_) {
      if (_disposed || token != _loadToken) return;
      _errorMessage =
          'Không thể tải dữ liệu tổng kết tuần. Vui lòng kiểm tra kết nối và thử lại.';
    } finally {
      if (!_disposed && token == _loadToken) {
        _loading = false;
        _notifySafely();
      }
    }
  }

  Future<void> previousWeek() {
    _selectedWeekStart = DateHelper.shiftDays(_selectedWeekStart, -7);
    return load();
  }

  Future<void> nextWeek() async {
    if (!canGoToNextWeek) return;
    _selectedWeekStart = DateHelper.shiftDays(_selectedWeekStart, 7);
    await load();
  }

  Future<void> goToCurrentWeek() {
    _selectedWeekStart = WeeklyInsightsAggregator.startOfWeek(referenceDate);
    return load();
  }

  /// Khi đổi tài khoản (`ownerUid`), xóa ngay dữ liệu cũ của tài khoản trước rồi tải lại.
  Future<void> updateOwner(String nextOwnerUid) {
    final trimmed = nextOwnerUid.trim();
    if (trimmed == _ownerUid) return Future.value();
    _ownerUid = trimmed;
    _summary = null;
    _errorMessage = null;
    return load();
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
