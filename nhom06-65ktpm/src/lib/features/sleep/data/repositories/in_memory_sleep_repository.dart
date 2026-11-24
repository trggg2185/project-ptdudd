import '../../domain/entities/routine_block.dart';
import '../../domain/entities/sleep_log.dart';
import '../../domain/entities/sleep_window.dart';
import '../../domain/repositories/sleep_repository.dart';
import '../fixtures/sample_sleep_fixture.dart';

/// Kho dữ liệu In-Memory cho module Giấc ngủ & Lịch sinh hoạt (dùng cho test và demo ngoại tuyến).
///
/// Cô lập dữ liệu hoàn toàn theo `ownerUid`, đồng thời hỗ trợ mô phỏng độ trễ và lỗi
/// để kiểm thử các trạng thái tải / trống / lỗi trên UI.
class InMemorySleepRepository implements SleepRepository {
  final Map<String, Map<String, SleepLog>> _logsByOwner = {};
  final Map<String, SleepWindow?> _windowByOwner = {};
  final Map<String, List<RoutineBlock>> _routineBlocksByOwner = {};

  /// Tùy chọn mô phỏng lỗi cho bài kiểm thử trạng thái lỗi & thử lại (Retry).
  Exception? nextError;

  /// Tùy chọn mô phỏng độ trễ cho bài kiểm thử trạng thái đang tải (Loading).
  Duration simulatedDelay;

  final bool seedWithSamples;
  final bool nightShiftSample;
  final Set<String> _seededOwners = {};

  InMemorySleepRepository({
    this.seedWithSamples = false,
    this.nightShiftSample = false,
    this.simulatedDelay = Duration.zero,
    this.nextError,
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

  void _ensureSeeded(String ownerUid, {DateTime? referenceDate}) {
    if (!seedWithSamples || _seededOwners.contains(ownerUid)) return;
    _seededOwners.add(ownerUid);
    final logs = SampleSleepFixture.createSampleLogs(
      ownerUid,
      referenceDate: referenceDate,
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
      referenceDate: referenceDate,
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
  Future<void> saveSleepLog(SleepLog log) async {
    await _maybeDelayOrFail();
    _ensureSeeded(log.ownerUid);

    final ownerMap = _logsByOwner.putIfAbsent(log.ownerUid, () => {});
    final existing = ownerMap[log.id];
    final toStore = existing == null
        ? log
        : log.copyWith(
            version: existing.version + 1,
            updatedAt: DateTime.now(),
          );
    ownerMap[log.id] = toStore;
  }

  @override
  Future<void> deleteSleepLog({
    required String ownerUid,
    required String logId,
  }) async {
    await _maybeDelayOrFail();
    _logsByOwner[ownerUid]?.remove(logId);
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
    _ensureSeeded(ownerUid, referenceDate: referenceDate);
    return List<RoutineBlock>.from(_routineBlocksByOwner[ownerUid] ?? const []);
  }
}
