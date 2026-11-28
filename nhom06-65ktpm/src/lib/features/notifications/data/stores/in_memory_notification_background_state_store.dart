import '../../domain/entities/scheduled_reminder.dart';
import '../../domain/logic/notification_deduplicator.dart';
import '../../domain/repositories/notification_background_state_store.dart';

/// Kho lưu trạng thái runtime & chống trùng trên RAM (dùng cho Flutter Web và unit/widget test).
class InMemoryNotificationBackgroundStateStore
    implements NotificationBackgroundStateStore {
  NotificationRuntimeState? _state;
  final NotificationDeduplicator _deduplicator;

  InMemoryNotificationBackgroundStateStore({
    NotificationDeduplicator? deduplicator,
  }) : _deduplicator = deduplicator ?? NotificationDeduplicator();

  @override
  Future<void> saveRuntimeState(NotificationRuntimeState state) async {
    _state = state;
  }

  @override
  Future<NotificationRuntimeState?> readRuntimeState() async => _state;

  @override
  Future<bool> tryAcquireDedupeKey({
    required String ownerUid,
    required String dedupeKey,
    required NotificationChannelSource source,
    required DateTime nowUtc,
    Duration window = const Duration(minutes: 15),
  }) async {
    return _deduplicator.tryAcquire(
      ownerUid: ownerUid,
      dedupeKey: dedupeKey,
      source: source,
      nowUtc: nowUtc,
    );
  }

  @override
  Future<void> recordDispatchedKey({
    required String ownerUid,
    required String dedupeKey,
    required NotificationChannelSource source,
    required DateTime nowUtc,
  }) async {
    _deduplicator.tryAcquire(
      ownerUid: ownerUid,
      dedupeKey: dedupeKey,
      source: source,
      nowUtc: nowUtc,
    );
  }

  @override
  Future<void> clearForOwner(String ownerUid) async {
    _deduplicator.clearForOwner(ownerUid);
    if (_state?.activeOwnerUid == ownerUid) {
      _state = NotificationRuntimeState(
        activeOwnerUid: null,
        remindersEnabled: _state!.remindersEnabled,
        quietHoursStartMinute: _state!.quietHoursStartMinute,
        quietHoursEndMinute: _state!.quietHoursEndMinute,
        timezone: _state!.timezone,
        updatedAtUtc: DateTime.now().toUtc(),
      );
    }
  }
}
