import 'dart:async';

import '../../data/stores/in_memory_notification_background_state_store.dart';
import '../entities/reminder_preferences.dart';
import '../entities/scheduled_reminder.dart';
import '../logic/notification_deduplicator.dart';
import '../logic/reminder_scheduler_engine.dart';
import '../repositories/fcm_messaging_gateway.dart';
import '../repositories/local_notification_gateway.dart';
import '../repositories/notification_background_state_store.dart';
import '../repositories/notification_repository.dart';
import 'fcm_background_message_processor.dart';

/// Tác vụ vô hiệu hóa `device_tokens` bị lỗi mạng khi đăng xuất/đổi tài khoản, được giữ lại để retry.
class PendingTokenDeactivation {
  final String ownerUid;
  final String? token;
  final DateTime queuedAtUtc;

  const PendingTokenDeactivation({
    required this.ownerUid,
    this.token,
    required this.queuedAtUtc,
  });

  String get key => '$ownerUid::${token ?? "*"}';
}

/// Điều phối toàn app cho vòng đời nhắc lịch, FCM và đổi tài khoản Firebase (Issue #6).
///
/// Chịu trách nhiệm xuyên suốt ứng dụng (không phụ thuộc việc người dùng có đang mở `NotificationsPage`):
/// 1. **Đăng ký & lắng nghe FCM:** khi phiên được cấp quyền dữ liệu (`activateAuthorizedSession`),
///    tự động lấy token FCM gọi `registerDeviceToken()`, lắng nghe `onTokenRefresh` và cầu nối
///    `onForegroundMessage` qua `NotificationDeduplicator` để chống trùng Local ↔ FCM.
/// 2. **Đăng xuất / đổi tài khoản:** hủy toàn bộ nhắc cục bộ đang chờ, xóa cache/snooze và vô hiệu hóa
///    `device_tokens` của tài khoản cũ trong mọi trường hợp (bấm đăng xuất, đổi `A → B`, hoặc
///    đăng xuất Firebase từ bên ngoài `A → null`).
/// 3. **Retry khi offline:** nếu vô hiệu hóa `device_tokens` gặp lỗi mạng, tác vụ được xếp vào
///    [pendingDeactivations] và tự động thử lại khi app resume hoặc khi mạng/phiên phục hồi.
/// 4. **Khôi phục toàn app sau boot / đổi quyền / đổi múi giờ:** `handleAppResumed()` tự đối chiếu
///    và đặt lại toàn bộ nhắc lịch đã duyệt nếu hàng đợi OS bị xóa sau khi khởi động lại máy hoặc
///    khi quyền thông báo / múi giờ thay đổi.
class NotificationAccountCoordinator {
  final LocalNotificationGateway gateway;
  final FcmMessagingGateway? fcmGateway;
  final NotificationDeduplicator deduplicator;
  final NotificationBackgroundStateStore backgroundStateStore;
  final bool _sharesInMemoryDeduplicator;
  final NotificationRepository? Function()? repositoryResolver;
  final DateTime Function() _nowProvider;

  String? _activeOwnerUid;
  String? _authorizedOwnerUid;
  String? _lastSyncedTimezone;
  String? _lastDeviceTimezone;
  NotificationPermissionStatus _lastPermissionStatus =
      NotificationPermissionStatus.unknown;
  int _suppressedFcmDuplicateCount = 0;

  final Map<String, Map<String, DateTime>> _snoozesByOwner = {};
  final Map<String, String> _lastRegisteredTokenByOwner = {};
  final Set<String> _recentlyDeactivatedOnSignOut = {};
  final Map<String, PendingTokenDeactivation> _pendingDeactivations = {};

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<IncomingFcmMessage>? _foregroundMessageSub;
  bool _listenersAttached = false;

  factory NotificationAccountCoordinator({
    required LocalNotificationGateway gateway,
    FcmMessagingGateway? fcmGateway,
    NotificationDeduplicator? deduplicator,
    NotificationBackgroundStateStore? backgroundStateStore,
    NotificationRepository? Function()? repositoryResolver,
    DateTime Function()? nowProvider,
  }) {
    final resolvedDeduplicator = deduplicator ?? NotificationDeduplicator();
    final sharesInMemory = backgroundStateStore == null;
    final resolvedStore =
        backgroundStateStore ??
        InMemoryNotificationBackgroundStateStore(
          deduplicator: resolvedDeduplicator,
        );
    return NotificationAccountCoordinator._internal(
      sharesInMemory,
      nowProvider ?? DateTime.now,
      gateway: gateway,
      fcmGateway: fcmGateway,
      deduplicator: resolvedDeduplicator,
      backgroundStateStore: resolvedStore,
      repositoryResolver: repositoryResolver,
    );
  }

  NotificationAccountCoordinator._internal(
    this._sharesInMemoryDeduplicator,
    this._nowProvider, {
    required this.gateway,
    required this.fcmGateway,
    required this.deduplicator,
    required this.backgroundStateStore,
    required this.repositoryResolver,
  });

  /// Đồng bộ ảnh chụp cấu hình runtime không nhạy cảm xuống kho bền vững cho isolate nền FCM.
  Future<void> syncRuntimePreferences(ReminderPreferences preferences) async {
    try {
      await backgroundStateStore.saveRuntimeState(
        NotificationRuntimeState.fromPreferences(
          preferences,
          updatedAtUtc: _nowProvider().toUtc(),
        ),
      );
    } catch (_) {
      // Không chặn luồng chính nếu kho bền vững tạm thời không khả dụng.
    }
  }

  /// Kiểm tra & chiếm khóa chống trùng Local ↔ FCM trên cả RAM lẫn kho bền vững xuyên isolate.
  Future<bool> tryAcquireDedupeKey({
    required String ownerUid,
    required String dedupeKey,
    required NotificationChannelSource source,
    required DateTime nowUtc,
  }) async {
    if (_sharesInMemoryDeduplicator) {
      return backgroundStateStore.tryAcquireDedupeKey(
        ownerUid: ownerUid,
        dedupeKey: dedupeKey,
        source: source,
        nowUtc: nowUtc,
        window: deduplicator.dedupeWindow,
      );
    }
    final memAcquired = deduplicator.tryAcquire(
      ownerUid: ownerUid,
      dedupeKey: dedupeKey,
      source: source,
      nowUtc: nowUtc,
    );
    if (!memAcquired) return false;
    try {
      return await backgroundStateStore.tryAcquireDedupeKey(
        ownerUid: ownerUid,
        dedupeKey: dedupeKey,
        source: source,
        nowUtc: nowUtc,
        window: deduplicator.dedupeWindow,
      );
    } catch (_) {
      return true;
    }
  }

  String? get activeOwnerUid => _activeOwnerUid;
  String? get authorizedOwnerUid => _authorizedOwnerUid;
  int get suppressedFcmDuplicateCount => _suppressedFcmDuplicateCount;

  List<PendingTokenDeactivation> get pendingDeactivations =>
      List.unmodifiable(_pendingDeactivations.values);

  int get pendingDeactivationCount => _pendingDeactivations.length;

  Map<String, DateTime> snoozesForOwner(String ownerUid) =>
      Map<String, DateTime>.unmodifiable(
        _snoozesByOwner[ownerUid] ?? const {},
      );

  void recordSnooze({
    required String ownerUid,
    required String itemId,
    required DateTime snoozedUntilUtc,
  }) {
    _snoozesByOwner.putIfAbsent(ownerUid, () => {})[itemId] =
        snoozedUntilUtc.toUtc();
  }

  void clearSnooze({required String ownerUid, required String itemId}) {
    _snoozesByOwner[ownerUid]?.remove(itemId);
  }

  /// Kích hoạt toàn bộ điều phối cho tài khoản vừa xác minh có quyền dữ liệu (`role: authenticated`).
  ///
  /// Chạy ở cấp toàn app ngay khi mở app / đăng nhập:
  /// - Gắn listener `onTokenRefresh` & `onForegroundMessage` của FCM.
  /// - Thử lại mọi tác vụ thu hồi token cũ còn tồn đọng.
  /// - Đăng ký `device_tokens` cho thiết bị hiện tại.
  /// - Đối chiếu & khôi phục lịch nhắc đã duyệt (kể cả sau khi máy vừa khởi động lại).
  Future<void> activateAuthorizedSession(String ownerUid) async {
    if (ownerUid.trim().isEmpty) return;
    _activeOwnerUid = ownerUid;
    _authorizedOwnerUid = ownerUid;
    _recentlyDeactivatedOnSignOut.remove(ownerUid);

    _attachFcmListenersIfNeeded();
    // 1. Ưu tiên hoàn tất mọi tác vụ thu hồi token cũ của chính chủ tài khoản này (an toàn RLS)
    //    trước khi đăng ký token thiết bị hiện hành.
    await retryPendingTokenDeactivations(onlyOwnerUid: ownerUid);
    // 2. Đăng ký token FCM hiện tại cho thiết bị.
    await _syncFcmTokenForOwner(ownerUid);
    // 3. Đối chiếu & khôi phục nhắc lịch cục bộ ở cấp toàn app.
    await reconcileActiveSession(forceOnEmptyQueue: true);
  }

  /// Gọi ở cấp toàn app khi `AppLifecycleState.resumed` (mở lại app sau boot, sau khi chỉnh quyền
  /// trong Cài đặt Android, hoặc khi mạng vừa khôi phục).
  Future<void> handleAppResumed() async {
    final ownerUid = _authorizedOwnerUid;
    if (ownerUid == null || ownerUid.isEmpty) return;

    await retryPendingTokenDeactivations(onlyOwnerUid: ownerUid);
    await _syncFcmTokenForOwner(ownerUid);
    await reconcileActiveSession(forceOnEmptyQueue: true);
  }

  /// Đối chiếu và khôi phục lịch nhắc cục bộ cho phiên hiện tại ở cấp toàn app.
  Future<int> reconcileActiveSession({bool forceOnEmptyQueue = true}) async {
    final ownerUid = _authorizedOwnerUid;
    final repo = repositoryResolver?.call();
    if (ownerUid == null || repo == null) return 0;

    try {
      await gateway.initialize();
      final permission = await gateway.checkPermissionStatus();
      final detectedTz = await gateway.detectDeviceTimezone();
      final prefs = await repo.getPreferences(ownerUid);
      await syncRuntimePreferences(prefs);
      final items = await repo.getPlanItems(ownerUid);
      final pending = await gateway.pendingNotifications();

      final permissionChanged = permission != _lastPermissionStatus;
      _lastPermissionStatus = permission;

      final nowUtc = _nowProvider().toUtc();
      final hasUpcomingApproved = items.any(
        (item) =>
            item.ownerUid == ownerUid &&
            item.isEligibleForReminder &&
            prefs.adjustForQuietHours(item.startsAtUtc).effectiveUtc.isAfter(
              nowUtc,
            ),
      );
      final needsRebootRecovery =
          forceOnEmptyQueue &&
          permission.canScheduleLocal &&
          prefs.remindersEnabled &&
          pending.isEmpty &&
          hasUpcomingApproved;

      final effectiveTzChanged =
          _lastSyncedTimezone != null && _lastSyncedTimezone != prefs.timezone;
      final deviceTzChanged =
          _lastDeviceTimezone != null &&
          detectedTz.isNotEmpty &&
          _lastDeviceTimezone != detectedTz;

      final plan = ReminderSchedulerEngine.reconcile(
        ownerUid: ownerUid,
        preferences: prefs,
        planItems: items,
        pendingOnDevice: pending,
        nowUtc: nowUtc,
        activeSnoozesUtc: snoozesForOwner(ownerUid),
        previousTimezone: _lastSyncedTimezone,
        forceReschedule:
            needsRebootRecovery ||
            permissionChanged ||
            effectiveTzChanged ||
            deviceTzChanged,
      );

      for (final id in plan.notificationIdsToCancel) {
        await gateway.cancel(id);
      }

      var scheduledCount = 0;
      if (permission.canScheduleLocal) {
        for (final reminder in plan.remindersToSchedule) {
          await gateway.schedule(reminder);
          scheduledCount++;
        }
      }

      _lastSyncedTimezone = prefs.timezone;
      if (detectedTz.isNotEmpty) {
        _lastDeviceTimezone = detectedTz;
      }
      return scheduledCount;
    } catch (_) {
      return 0;
    }
  }

  /// Xử lý thông báo đẩy FCM đến khi ứng dụng đang mở qua cùng bộ xử lý chống trùng
  /// và bảo vệ màn hình khóa với background/terminated handler (`FcmBackgroundMessageProcessor`).
  Future<bool> handleIncomingFcmMessage(IncomingFcmMessage message) async {
    final activeUid = _activeOwnerUid;
    if (activeUid == null || activeUid.isEmpty) return false;

    final nowUtc = _nowProvider().toUtc();
    ReminderPreferences? prefs;
    final repo = repositoryResolver?.call();
    if (repo != null) {
      try {
        prefs = await repo.getPreferences(activeUid);
        await syncRuntimePreferences(prefs);
      } catch (_) {
        // Nếu tạm không đọc được preferences khi online chập chờn, dùng trạng thái runtime đã lưu.
      }
    }

    final dedupeKey = message.effectiveDedupeKey(activeUid);
    if (!_sharesInMemoryDeduplicator &&
        deduplicator.isRecentlyDispatched(
          ownerUid: activeUid,
          dedupeKey: dedupeKey,
          nowUtc: nowUtc,
        )) {
      _suppressedFcmDuplicateCount++;
      return false;
    }

    final processor = FcmBackgroundMessageProcessor(
      gateway: gateway,
      stateStore: backgroundStateStore,
      dedupeWindow: deduplicator.dedupeWindow,
      nowProvider: _nowProvider,
    );
    final outcome = await processor.process(
      message,
      fallbackOwnerUid: activeUid,
      preferencesOverride: prefs,
      isBackgroundIsolate: false,
    );
    if (outcome == FcmHandleOutcome.suppressedDuplicate) {
      _suppressedFcmDuplicateCount++;
      return false;
    }
    if (outcome == FcmHandleOutcome.dispatched) {
      if (!_sharesInMemoryDeduplicator) {
        deduplicator.tryAcquire(
          ownerUid: activeUid,
          dedupeKey: dedupeKey,
          source: NotificationChannelSource.fcm,
          nowUtc: nowUtc,
        );
      }
      return true;
    }
    return false;
  }

  /// Gọi trước khi thực thi `auth.signOut()` để thu hồi nhắc lịch & vô hiệu hóa token của [ownerUid].
  Future<void> handleBeforeSignOut(String ownerUid) async {
    if (ownerUid.trim().isEmpty) return;
    await _cleanupOwner(ownerUid, deactivateRemoteTokens: true);
    _recentlyDeactivatedOnSignOut.add(ownerUid);
    if (_activeOwnerUid == ownerUid) {
      _activeOwnerUid = null;
    }
    if (_authorizedOwnerUid == ownerUid) {
      _authorizedOwnerUid = null;
    }
  }

  /// Gọi khi luồng phiên Firebase đổi tài khoản (`A → B`) hoặc đăng xuất từ bên ngoài (`A → null`).
  ///
  /// Luôn hủy toàn bộ nhắc cục bộ, xóa cache chống trùng và vô hiệu hóa `device_tokens`
  /// của tài khoản cũ (`previousUid`) trừ khi `handleBeforeSignOut` vừa dọn ngay trước đó.
  Future<void> handleAccountChanged({
    required String? previousUid,
    required String? nextUid,
  }) async {
    if (nextUid != null && nextUid.isNotEmpty) {
      _recentlyDeactivatedOnSignOut.remove(nextUid);
    }
    if (previousUid != null &&
        previousUid.isNotEmpty &&
        previousUid != nextUid) {
      final alreadyDeactivated =
          _recentlyDeactivatedOnSignOut.remove(previousUid);
      await _cleanupOwner(
        previousUid,
        deactivateRemoteTokens: !alreadyDeactivated,
      );
    }
    _activeOwnerUid = nextUid;
    if (nextUid == null || nextUid != _authorizedOwnerUid) {
      _authorizedOwnerUid = null;
    }
  }

  /// Thử lại các tác vụ vô hiệu hóa `device_tokens` từng thất bại do mất mạng.
  ///
  /// Phân vùng chặt theo `ownerUid` (`onlyOwnerUid ?? _authorizedOwnerUid`) để không bao giờ
  /// gửi cập nhật của tài khoản cũ dưới JWT của tài khoản khác (tôn trọng RLS).
  /// Trả về số tác vụ đã thu hồi thành công; tác vụ nào vẫn lỗi mạng sẽ được giữ lại trong hàng đợi.
  Future<int> retryPendingTokenDeactivations({String? onlyOwnerUid}) async {
    final repo = repositoryResolver?.call();
    final targetOwnerUid = onlyOwnerUid ?? _authorizedOwnerUid;
    if (repo == null ||
        _pendingDeactivations.isEmpty ||
        targetOwnerUid == null ||
        targetOwnerUid.isEmpty) {
      return 0;
    }

    final entries = _pendingDeactivations.values
        .where((e) => e.ownerUid == targetOwnerUid)
        .toList();
    var succeeded = 0;

    for (final entry in entries) {
      try {
        await repo.deactivateDeviceTokens(
          entry.ownerUid,
          token: entry.token,
        );
        _pendingDeactivations.remove(entry.key);
        succeeded++;
      } catch (_) {
        // Giữ nguyên trong hàng đợi để retry ở lần tiếp theo khi mạng / phiên hợp lệ.
      }
    }
    return succeeded;
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundMessageSub?.cancel();
    _tokenRefreshSub = null;
    _foregroundMessageSub = null;
    _listenersAttached = false;
  }

  void _attachFcmListenersIfNeeded() {
    if (_listenersAttached || fcmGateway == null) return;
    _listenersAttached = true;

    _tokenRefreshSub = fcmGateway!.onTokenRefresh.listen((newToken) {
      final ownerUid = _authorizedOwnerUid ?? _activeOwnerUid;
      if (ownerUid != null &&
          ownerUid.isNotEmpty &&
          newToken.trim().isNotEmpty) {
        _registerTokenForOwner(ownerUid, newToken.trim());
      }
    });

    _foregroundMessageSub = fcmGateway!.onForegroundMessage.listen((message) {
      handleIncomingFcmMessage(message);
    });
  }

  Future<void> _syncFcmTokenForOwner(String ownerUid) async {
    if (fcmGateway == null) return;
    try {
      final token = await fcmGateway!.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await _registerTokenForOwner(ownerUid, token.trim());
      }
    } catch (_) {
      // Không chặn luồng chính nếu thiết bị chưa sẵn sàng lấy token FCM.
    }
  }

  Future<void> _registerTokenForOwner(String ownerUid, String token) async {
    final repo = repositoryResolver?.call();
    if (repo == null) return;

    final previousToken = _lastRegisteredTokenByOwner[ownerUid];
    if (previousToken != null && previousToken != token) {
      try {
        await repo.deactivateDeviceTokens(ownerUid, token: previousToken);
      } catch (_) {
        // Nếu xoay vòng token lúc offline -> xếp vào hàng đợi để thu hồi token cũ khi mạng phục hồi.
        _enqueuePendingDeactivation(ownerUid, previousToken);
      }
    }

    try {
      await repo.registerDeviceToken(
        ownerUid: ownerUid,
        token: token,
        platform: fcmGateway?.platformName ?? 'android',
      );
      _lastRegisteredTokenByOwner[ownerUid] = token;
      // Người dùng đăng nhập lại trên chính token này -> hủy cờ chờ thu hồi cùng token cụ thể đó.
      _pendingDeactivations.removeWhere(
        (_, entry) => entry.ownerUid == ownerUid && entry.token == token,
      );
    } catch (_) {
      // Sẽ thử đăng ký lại ở lần handleAppResumed() tiếp theo.
    }
  }

  Future<void> _cleanupOwner(
    String ownerUid, {
    required bool deactivateRemoteTokens,
  }) async {
    deduplicator.clearForOwner(ownerUid);
    _snoozesByOwner.remove(ownerUid);
    try {
      await backgroundStateStore.clearForOwner(ownerUid);
    } catch (_) {
      // Không chặn đăng xuất nếu dọn kho trạng thái nền gặp lỗi cục bộ.
    }

    try {
      await gateway.cancelAll();
    } catch (_) {
      // Không chặn đăng xuất nếu thiết bị/Web không hỗ trợ cancelAll.
    }

    if (deactivateRemoteTokens) {
      try {
        await fcmGateway?.deleteToken();
      } catch (_) {
        // Không chặn đăng xuất nếu xóa token FCM cục bộ lỗi khi offline.
      }
      _lastRegisteredTokenByOwner.remove(ownerUid);

      final repo = repositoryResolver?.call();
      if (repo == null) {
        _enqueuePendingDeactivation(ownerUid, null);
        return;
      }
      try {
        await repo.deactivateDeviceTokens(ownerUid);
        _pendingDeactivations.removeWhere((_, e) => e.ownerUid == ownerUid);
      } catch (_) {
        // Không bỏ qua âm thầm: lưu vào hàng đợi retry phân vùng theo ownerUid để thử lại khi đúng chủ tài khoản kết nối lại.
        _enqueuePendingDeactivation(ownerUid, null);
      }
    }
  }

  void _enqueuePendingDeactivation(String ownerUid, String? token) {
    final entry = PendingTokenDeactivation(
      ownerUid: ownerUid,
      token: token,
      queuedAtUtc: _nowProvider().toUtc(),
    );
    _pendingDeactivations[entry.key] = entry;
  }
}
