import '../../domain/entities/routine_block.dart';
import '../../domain/entities/sleep_log.dart';
import '../../domain/entities/sleep_window.dart';
import '../../domain/repositories/sleep_repository.dart';
import '../fixtures/sample_sleep_fixture.dart';

/// Kho dữ liệu In-Memory cho module Giấc ngủ & Lịch sinh hoạt (dùng cho test và demo ngoại tuyến).
///
/// Cô lập dữ liệu hoàn toàn theo `ownerUid`, hỗ trợ kiểm tra xung đột phiên bản (`baseVersion`),
/// ngày tham chiếu nhất quán (`referenceDate`) cho fixture, và mô phỏng độ trễ/lỗi
/// để kiểm thử các trạng thái tải / trống / lỗi / lỗi reload sau khi lưu.
class InMemorySleepRepository implements SleepRepository {
  final Map<String, Map<String, SleepLog>> _logsByOwner = {};
  final Map<String, SleepWindow?> _windowByOwner = {};
  final Map<String, List<RoutineBlock>> _routineBlocksByOwner = {};

  /// Ngày tham chiếu cố định cho fixture mẫu (nếu null dùng `DateTime.now()`).
  final DateTime? referenceDate;

  /// Tùy chọn mô phỏng lỗi cho lời gọi bất kỳ tiếp theo (dùng cho test trạng thái lỗi & Retry).
  Exception? nextError;

  /// Tùy chọn mô phỏng lỗi riêng cho lời gọi `getSleepLogs` tiếp theo
  /// (dùng để kiểm thử kịch bản lưu thành công nhưng reload thất bại).
  Exception? nextReadLogsError;

  /// Tùy chọn mô phỏng độ trễ cho bài kiểm thử trạng thái đang tải (Loading).
  Duration simulatedDelay;

  final bool seedWithSamples;
  final bool nightShiftSample;
  final Set<String> _seededOwners = {};

  InMemorySleepRepository({
    this.seedWithSamples = false,
    this.nightShiftSample = false,
    this.referenceDate,
    this.simulatedDelay = Duration.zero,
    this.nextError,
    this.nextReadLogsError,
  });

  Future<void> _maybeDelayOrFail() async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    if (nextError != null) {
      final err = nextError!;
      nextError = null;
      throw err;
    }
  }

  void _ensureSeeded(String ownerUid, {DateTime? anchorDate}) {
    if (!seedWithSamples || _seededOwners.contains(ownerUid)) return;
    _seededOwners.add(ownerUid);
    final effectiveAnchor = anchorDate ?? referenceDate;
    final logs = SampleSleepFixture.createSampleLogs(
      ownerUid,
      referenceDate: effectiveAnchor,
    );
    final ownerMap = _logsByOwner.putIfAbsent(ownerUid, () => {});
    for (final log in logs) {
      ownerMap[log.id] = log;
    }
    _windowByOwner[ownerUid] = nightShiftSample
        ? SampleSleepFixture.nightShiftSleepWindow
        : SampleSleepFixture.defaultSleepWindow;
    _routineBlocksByOwner[ownerUid] =
        SampleSleepFixture.createSampleRoutineBlocks(
      referenceDate: effectiveAnchor,
      nightShiftMode: nightShiftSample,
    );
  }

  void setRoutineBlocks(String ownerUid, List<RoutineBlock> blocks) {
    _routineBlocksByOwner[ownerUid] = List<RoutineBlock>.from(blocks);
  }

  @override
  Future<List<SleepLog>> getSleepLogs({
    required String ownerUid,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    await _maybeDelayOrFail();
    if (nextReadLogsError != null) {
      final err = nextReadLogsError!;
      nextReadLogsError = null;
      throw err;
    }
    _ensureSeeded(ownerUid);

    final ownerLogs = _logsByOwner[ownerUid]?.values.toList() ?? [];
    final filtered = ownerLogs.where((log) {
      if (fromDate != null && log.wokeAt.isBefore(fromDate)) return false;
      if (toDate != null && log.sleptAt.isAfter(toDate)) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.sleptAt.compareTo(a.sleptAt));
    return filtered;
  }

  @override
  Future<SleepLog> saveSleepLog(SleepLog log, {int? baseVersion}) async {
    await _maybeDelayOrFail();
    _ensureSeeded(log.ownerUid);

    final ownerMap = _logsByOwner.putIfAbsent(log.ownerUid, () => {});
    final existing = ownerMap[log.id];

    if (baseVersion == null) {
      if (existing != null) {
        throw SleepConflictException(
          'Bản ghi giấc ngủ đã tồn tại trên máy chủ (phiên bản ${existing.version}). Vui lòng tải lại dữ liệu.',
          serverVersion: existing.version,
          serverLog: existing,
        );
      }
      final created = log.copyWith(version: 1);
      ownerMap[log.id] = created;
      return created;
    }

    if (existing == null || existing.version != baseVersion) {
      throw SleepConflictException(
        existing == null
            ? 'Bản ghi giấc ngủ đã bị xóa trên thiết bị khác. Danh sách đã được cập nhật.'
            : 'Bản ghi giấc ngủ đã bị thay đổi trên thiết bị khác. Vui lòng tải lại dữ liệu trước khi chỉnh sửa.',
        serverVersion: existing?.version,
        serverLog: existing,
      );
    }

    final updated = log.copyWith(
      version: existing.version + 1,
      updatedAt: DateTime.now(),
    );
    ownerMap[log.id] = updated;
    return updated;
  }

  @override
  Future<void> deleteSleepLog({
    required String ownerUid,
    required String logId,
    int? baseVersion,
  }) async {
    await _maybeDelayOrFail();
    final ownerMap = _logsByOwner[ownerUid];
    final existing = ownerMap?[logId];
    if (baseVersion != null &&
        (existing == null || existing.version != baseVersion)) {
      throw SleepConflictException(
        existing == null
            ? 'Bản ghi giấc ngủ đã bị xóa ở thiết bị khác trước đó.'
            : 'Bản ghi giấc ngủ đã được cập nhật ở thiết bị khác trước khi xóa. Vui lòng tải lại dữ liệu.',
        serverVersion: existing?.version,
        serverLog: existing,
      );
    }
    ownerMap?.remove(logId);
  }

  @override
  Future<SleepWindow?> getSleepWindow(String ownerUid) async {
    await _maybeDelayOrFail();
    _ensureSeeded(ownerUid);
    return _windowByOwner[ownerUid];
  }

  @override
  Future<void> saveSleepWindow({
    required String ownerUid,
    required SleepWindow window,
  }) async {
    await _maybeDelayOrFail();
    _ensureSeeded(ownerUid);
    _windowByOwner[ownerUid] = window;
  }

  @override
  Future<void> clearSleepWindow(String ownerUid) async {
    await _maybeDelayOrFail();
    _windowByOwner.remove(ownerUid);
  }

  @override
  Future<List<RoutineBlock>> getRoutineBlocks({
    required String ownerUid,
    DateTime? referenceDate,
  }) async {
    await _maybeDelayOrFail();
    _ensureSeeded(ownerUid, anchorDate: referenceDate);
    return List<RoutineBlock>.from(_routineBlocksByOwner[ownerUid] ?? const []);
  }
}
