import '../../domain/entities/approved_plan_reminder_item.dart';
import '../../domain/entities/reminder_preferences.dart';
import '../../domain/entities/scheduled_reminder.dart';
import '../../domain/repositories/notification_repository.dart';
import '../fixtures/sample_notification_fixture.dart';

/// Kho dữ liệu In-Memory cô lập hoàn toàn theo `ownerUid` cho module Nhắc lịch (Issue #6).
class InMemoryNotificationRepository implements NotificationRepository {
  final Map<String, ReminderPreferences> _prefsByOwner = {};
  final Map<String, Map<String, ApprovedPlanReminderItem>> _itemsByOwner = {};
  final Map<String, Map<String, DeviceTokenRecord>> _tokensByOwner = {};
  final Set<String> _seededOwners = {};

  final bool seedWithSamples;
  final DateTime? referenceDate;
  Duration simulatedDelay;
  Exception? nextError;

  InMemoryNotificationRepository({
    this.seedWithSamples = false,
    this.referenceDate,
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

  void _ensureSeeded(String ownerUid) {
    if (!seedWithSamples || _seededOwners.contains(ownerUid)) return;
    _seededOwners.add(ownerUid);
    _prefsByOwner.putIfAbsent(
      ownerUid,
      () => SampleNotificationFixture.defaultPreferences(ownerUid),
    );
    final items = SampleNotificationFixture.createSamplePlanItems(
      ownerUid,
      referenceDate: referenceDate,
    );
    final map = _itemsByOwner.putIfAbsent(ownerUid, () => {});
    for (final item in items) {
      map[item.itemId] = item;
    }
  }

  @override
  Future<ReminderPreferences> getPreferences(String ownerUid) async {
    await _maybeDelayOrFail();
    _ensureSeeded(ownerUid);
    return _prefsByOwner[ownerUid] ??
        SampleNotificationFixture.defaultPreferences(ownerUid);
  }

  @override
  Future<ReminderPreferences> savePreferences(
    ReminderPreferences preferences, {
    int? expectedVersion,
  }) async {
    await _maybeDelayOrFail();
    preferences.validate();
    _ensureSeeded(preferences.ownerUid);

    final existing = _prefsByOwner[preferences.ownerUid];
    if (expectedVersion != null &&
        existing != null &&
        existing.version != expectedVersion) {
      throw NotificationConflictException(
        'Cấu hình nhắc lịch đã được cập nhật từ thiết bị khác. Vui lòng tải lại.',
        serverVersion: existing.version,
        serverPreferences: existing,
      );
    }

    final saved = preferences.copyWith(
      version: (existing?.version ?? 0) + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    _prefsByOwner[preferences.ownerUid] = saved;
    return saved;
  }

  @override
  Future<List<ApprovedPlanReminderItem>> getPlanItems(String ownerUid) async {
    await _maybeDelayOrFail();
    _ensureSeeded(ownerUid);
    final items = _itemsByOwner[ownerUid]?.values.toList() ?? [];
    items.sort((a, b) => a.startsAtUtc.compareTo(b.startsAtUtc));
    return items;
  }

  @override
  Future<void> upsertPlanItem(ApprovedPlanReminderItem item) async {
    await _maybeDelayOrFail();
    _ensureSeeded(item.ownerUid);
    _itemsByOwner.putIfAbsent(item.ownerUid, () => {})[item.itemId] = item;
  }

  @override
  Future<void> deletePlanItem({
    required String ownerUid,
    required String itemId,
  }) async {
    await _maybeDelayOrFail();
    _itemsByOwner[ownerUid]?.remove(itemId);
  }

  @override
  Future<List<DeviceTokenRecord>> getDeviceTokens(String ownerUid) async {
    await _maybeDelayOrFail();
    return _tokensByOwner[ownerUid]?.values.toList() ?? const [];
  }

  @override
  Future<void> registerDeviceToken({
    required String ownerUid,
    required String token,
    required String platform,
  }) async {
    await _maybeDelayOrFail();
    final map = _tokensByOwner.putIfAbsent(ownerUid, () => {});
    final existing = map[token];
    map[token] = DeviceTokenRecord(
      id: existing?.id ?? 'token-${ownerUid.hashCode}-$token',
      ownerUid: ownerUid,
      token: token,
      platform: platform,
      isActive: true,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> deactivateDeviceTokens(String ownerUid, {String? token}) async {
    await _maybeDelayOrFail();
    final map = _tokensByOwner[ownerUid];
    if (map == null) return;
    if (token != null) {
      final existing = map[token];
      if (existing != null) {
        map[token] = existing.copyWith(
          isActive: false,
          updatedAt: DateTime.now().toUtc(),
        );
      }
      return;
    }
    for (final key in map.keys.toList()) {
      map[key] = map[key]!.copyWith(
        isActive: false,
        updatedAt: DateTime.now().toUtc(),
      );
    }
  }
}
