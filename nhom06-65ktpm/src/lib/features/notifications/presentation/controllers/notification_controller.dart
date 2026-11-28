import 'package:flutter/foundation.dart';

import '../../../profile/domain/profile_time.dart';
import '../../domain/entities/approved_plan_reminder_item.dart';
import '../../domain/entities/reminder_preferences.dart';
import '../../domain/entities/scheduled_reminder.dart';
import '../../domain/logic/notification_deduplicator.dart';
import '../../domain/logic/notification_privacy_formatter.dart';
import '../../domain/logic/reminder_scheduler_engine.dart';
import '../../domain/repositories/local_notification_gateway.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/services/notification_account_coordinator.dart';

/// Bộ điều khiển trạng thái (`ChangeNotifier`) cho module Nhắc lịch cục bộ & Giờ yên lặng (Issue #6).
class NotificationController extends ChangeNotifier {
  final NotificationRepository repository;
  final LocalNotificationGateway gateway;
  final NotificationAccountCoordinator accountCoordinator;
  final String currentUserId;
  final DateTime Function() _nowProvider;

  bool _isLoading = false;
  bool _hasLoadedOnce = false;
  bool _isMutating = false;
  String? _loadError;
  String? _actionError;
  String? _statusMessage;

  late ReminderPreferences _preferences;
  List<ApprovedPlanReminderItem> _planItems = [];
  List<ScheduledReminder> _scheduledReminders = [];
  NotificationPermissionStatus _permissionStatus =
      NotificationPermissionStatus.unknown;
  String? _deviceTimezone;
  String? _lastSyncedTimezone;
  int _lastCanceledCount = 0;
  int _lastScheduledCount = 0;
  int _suppressedDuplicateCount = 0;

  NotificationController({
    required this.repository,
    required this.gateway,
    required this.currentUserId,
    NotificationAccountCoordinator? accountCoordinator,
    DateTime Function()? nowProvider,
  }) : accountCoordinator =
           accountCoordinator ??
           NotificationAccountCoordinator(
             gateway: gateway,
             repositoryResolver: () => repository,
           ),
       _nowProvider = nowProvider ?? DateTime.now {
    _preferences = ReminderPreferences(ownerUid: currentUserId);
  }

  bool get isLoading => _isLoading;
  bool get hasLoadedOnce => _hasLoadedOnce;
  bool get isMutating => _isMutating;
  String? get loadError => _loadError;
  String? get actionError => _actionError;
  String? get statusMessage => _statusMessage;

  ReminderPreferences get preferences => _preferences;
  List<ApprovedPlanReminderItem> get planItems => List.unmodifiable(_planItems);
  List<ScheduledReminder> get scheduledReminders =>
      List.unmodifiable(_scheduledReminders);
  NotificationPermissionStatus get permissionStatus => _permissionStatus;
  String? get deviceTimezone => _deviceTimezone;
  String? get lastSyncedTimezone => _lastSyncedTimezone;
  int get lastCanceledCount => _lastCanceledCount;
  int get lastScheduledCount => _lastScheduledCount;
  int get suppressedDuplicateCount => _suppressedDuplicateCount;
  DateTime get now => _nowProvider();

  NotificationDeduplicator get deduplicator => accountCoordinator.deduplicator;

  /// Các mục đã duyệt đủ điều kiện đặt nhắc.
  List<ApprovedPlanReminderItem> get approvedItems =>
      _planItems.where((i) => i.isEligibleForReminder).toList();

  /// Các mục chưa duyệt / nháp / hoàn thành / bỏ qua — hiển thị minh bạch là KHÔNG tạo nhắc.
  List<ApprovedPlanReminderItem> get excludedItems =>
      _planItems.where((i) => !i.isEligibleForReminder).toList();

  /// Phát hiện múi giờ thiết bị đang lệch so với múi giờ lưu trong `reminder_preferences`.
  bool get hasTimezoneMismatch =>
      _deviceTimezone != null &&
      _deviceTimezone!.isNotEmpty &&
      _deviceTimezone != _preferences.timezone;

  /// Mốc tạm hoãn đang hoạt động (nếu có) của từng mục.
  DateTime? snoozedUntilFor(String itemId) =>
      accountCoordinator.snoozesForOwner(currentUserId)[itemId];

  void clearActionError() {
    if (_actionError != null) {
      _actionError = null;
      notifyListeners();
    }
  }

  void clearStatusMessage() {
    if (_statusMessage != null) {
      _statusMessage = null;
      notifyListeners();
    }
  }

  /// Tải cấu hình, danh sách lịch, trạng thái quyền thông báo và đồng bộ lịch nhắc trên thiết bị.
  Future<void> loadAll() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      await gateway.initialize();
      final results = await Future.wait<Object?>([
        repository.getPreferences(currentUserId),
        repository.getPlanItems(currentUserId),
        gateway.checkPermissionStatus(),
        gateway.detectDeviceTimezone(),
      ]);

      _preferences = results[0]! as ReminderPreferences;
      _planItems = results[1]! as List<ApprovedPlanReminderItem>;
      _permissionStatus = results[2]! as NotificationPermissionStatus;
      _deviceTimezone = results[3]! as String;

      await accountCoordinator.syncRuntimePreferences(_preferences);
      await _reconcileDeviceSchedule(forceReschedule: false);
      _hasLoadedOnce = true;
      _loadError = null;
    } catch (error) {
      _loadError = _formatError('Không thể tải dữ liệu nhắc lịch', error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Kiểm tra lại quyền thông báo, phát hiện đổi múi giờ và khôi phục lịch khi app mở lại.
  Future<void> refreshOnAppResumed() async {
    if (!_hasLoadedOnce || _isLoading) return;
    try {
      final newPermission = await gateway.checkPermissionStatus();
      final detectedTz = await gateway.detectDeviceTimezone();
      final permissionChanged = newPermission != _permissionStatus;
      _permissionStatus = newPermission;
      _deviceTimezone = detectedTz;

      // Kiểm tra nếu thiết bị vừa khởi động lại (hàng đợi trống dù có mục hợp lệ) -> tự khôi phục
      final pending = await gateway.pendingNotifications();
      final needsRebootRecovery =
          _permissionStatus.canScheduleLocal &&
          _preferences.remindersEnabled &&
          pending.isEmpty &&
          approvedItems.any((i) => i.startsAtUtc.isAfter(_nowProvider().toUtc()));

      if (permissionChanged || needsRebootRecovery) {
        await _reconcileDeviceSchedule(forceReschedule: needsRebootRecovery);
        if (needsRebootRecovery) {
          _statusMessage =
              'Đã khôi phục $_lastScheduledCount nhắc lịch cục bộ sau khi mở lại ứng dụng.';
        }
      }
      notifyListeners();
    } catch (_) {
      // Giữ trạng thái an toàn khi resume.
    }
  }

  /// Yêu cầu cấp quyền thông báo trên thiết bị (Android 13+) và đồng bộ ngay nếu được cấp.
  Future<NotificationPermissionStatus> requestNotificationPermission() async {
    _actionError = null;
    _isMutating = true;
    notifyListeners();
    try {
      _permissionStatus = await gateway.requestPermission();
      if (_permissionStatus.canScheduleLocal) {
        await _reconcileDeviceSchedule(forceReschedule: true);
        _statusMessage =
            'Đã cấp quyền thông báo và đồng bộ $_lastScheduledCount nhắc lịch đã duyệt.';
      } else if (_permissionStatus ==
          NotificationPermissionStatus.unsupportedPlatform) {
        _statusMessage =
            'Trình duyệt Web/nền tảng hiện tại không hỗ trợ hẹn giờ thông báo nền; bạn vẫn xem và quản lý lịch trong ứng dụng.';
      } else {
        _statusMessage =
            'Quyền thông báo đang bị tắt. Bạn có thể bật lại trong Cài đặt hệ thống; danh sách việc trong app vẫn hoạt động bình thường.';
      }
      return _permissionStatus;
    } catch (error) {
      _actionError = _formatError('Không thể kiểm tra quyền thông báo', error);
      return _permissionStatus;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Cập nhật cấu hình nhắc lịch (bật/tắt, giờ yên lặng, múi giờ, ẩn chi tiết màn hình khóa).
  ///
  /// Tách biệt rõ bước lưu cấu hình và bước đồng bộ alarm trên thiết bị để tránh báo sai lỗi lưu.
  Future<bool> updatePreferences(ReminderPreferences updated) async {
    _actionError = null;
    try {
      updated.validate();
    } on FormatException catch (validationError) {
      _actionError = validationError.message;
      notifyListeners();
      return false;
    }

    _isMutating = true;
    notifyListeners();

    final previousTz = _preferences.timezone;
    late final ReminderPreferences saved;
    try {
      saved = await repository.savePreferences(
        updated,
        expectedVersion: _preferences.version,
      );
    } on NotificationConflictException catch (conflict) {
      if (conflict.serverPreferences != null) {
        _preferences = conflict.serverPreferences!;
      }
      _actionError = conflict.message;
      _isMutating = false;
      notifyListeners();
      return false;
    } catch (error) {
      _actionError = _formatError('Không thể lưu cấu hình nhắc lịch', error);
      _isMutating = false;
      notifyListeners();
      return false;
    }

    _preferences = saved;
    _actionError = null;
    await accountCoordinator.syncRuntimePreferences(_preferences);

    try {
      final tzChanged = previousTz != saved.timezone;
      await _reconcileDeviceSchedule(
        previousTimezoneOverride: previousTz,
        forceReschedule: tzChanged,
      );
      if (!saved.remindersEnabled) {
        _statusMessage =
            'Đã tắt nhắc lịch cục bộ và hủy $_lastCanceledCount nhắc đang chờ.';
      } else if (tzChanged) {
        _statusMessage =
            'Đã chuyển múi giờ sang ${saved.timezone}, hủy $_lastCanceledCount nhắc cũ và đặt lại $_lastScheduledCount nhắc mới.';
      } else {
        _statusMessage =
            'Đã lưu cấu hình và cập nhật lịch nhắc cục bộ ($_lastScheduledCount đặt mới, $_lastCanceledCount đã hủy).';
      }
    } catch (_) {
      _statusMessage =
          'Đã lưu cấu hình lên hệ thống, nhưng chưa thể đồng bộ ngay với thông báo thiết bị. Bạn có thể bấm Đồng bộ lại.';
    } finally {
      _isMutating = false;
      notifyListeners();
    }
    return true;
  }

  /// Áp dụng múi giờ mới của thiết bị vào cấu hình và tự hủy + đặt lại toàn bộ nhắc lịch.
  Future<bool> applyDeviceTimezone(String newTimezone) async {
    if (profileLocation(newTimezone) == null) {
      _actionError = 'Múi giờ thiết bị không hợp lệ: $newTimezone.';
      notifyListeners();
      return false;
    }
    _deviceTimezone = newTimezone;
    return updatePreferences(_preferences.copyWith(timezone: newTimezone));
  }

  /// Tạm hoãn (snooze) một mục đã duyệt thêm [snoozeMinutes] phút, có tôn trọng giờ yên lặng.
  Future<bool> snoozeReminder(String itemId, {int? minutes}) async {
    final snoozeMinutes = minutes ?? _preferences.defaultSnoozeMinutes;
    final item = _planItems.where((i) => i.itemId == itemId).firstOrNull;
    if (item == null || !item.isEligibleForReminder) {
      _actionError = 'Chỉ có thể tạm hoãn các mục thuộc lịch đã duyệt.';
      notifyListeners();
      return false;
    }

    _actionError = null;
    _isMutating = true;
    notifyListeners();

    try {
      final computed = ReminderSchedulerEngine.computeSnoozeTime(
        nowUtc: _nowProvider().toUtc(),
        snoozeMinutes: snoozeMinutes,
        preferences: _preferences,
      );
      accountCoordinator.recordSnooze(
        ownerUid: currentUserId,
        itemId: itemId,
        snoozedUntilUtc: computed.effectiveUtc,
      );

      await _reconcileDeviceSchedule(forceReschedule: false);
      _statusMessage = computed.deferredByQuietHours
          ? 'Thời điểm tạm hoãn +$snoozeMinutes phút rơi vào giờ yên lặng nên đã tự động dời sang sau ${_preferences.quietHoursLabel}.'
          : 'Đã tạm hoãn lời nhắc thêm $snoozeMinutes phút.';
      return true;
    } catch (error) {
      _actionError = _formatError('Không thể tạm hoãn lời nhắc', error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Đổi giờ một mục lịch đã duyệt — tự động hủy nhắc cũ và đặt lại theo giờ mới.
  Future<bool> reschedulePlanItemTime({
    required String itemId,
    required DateTime newStartsAt,
  }) async {
    final item = _planItems.where((i) => i.itemId == itemId).firstOrNull;
    if (item == null) return false;

    _actionError = null;
    _isMutating = true;
    notifyListeners();

    try {
      final delta = item.endsAtUtc?.difference(item.startsAtUtc);
      final updated = item.copyWith(
        startsAt: newStartsAt.toUtc(),
        endsAt: delta != null ? newStartsAt.toUtc().add(delta) : null,
      );
      await repository.upsertPlanItem(updated);
      accountCoordinator.clearSnooze(ownerUid: currentUserId, itemId: itemId);
      _planItems = _planItems
          .map((i) => i.itemId == itemId ? updated : i)
          .toList();
      await _reconcileDeviceSchedule(forceReschedule: false);
      _statusMessage = 'Đã cập nhật giờ mục lịch, hủy nhắc cũ và đặt lại nhắc mới.';
      return true;
    } catch (error) {
      _actionError = _formatError('Không thể cập nhật giờ mục lịch', error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Bỏ qua (skip) một mục lịch — hủy ngay thông báo cục bộ đang chờ của mục đó.
  Future<bool> skipPlanItem(String itemId) async {
    final item = _planItems.where((i) => i.itemId == itemId).firstOrNull;
    if (item == null) return false;

    _actionError = null;
    _isMutating = true;
    notifyListeners();

    try {
      final skipped = item.copyWith(itemStatus: PlanItemStatus.skipped);
      await repository.upsertPlanItem(skipped);
      accountCoordinator.clearSnooze(ownerUid: currentUserId, itemId: itemId);
      _planItems = _planItems
          .map((i) => i.itemId == itemId ? skipped : i)
          .toList();
      await _reconcileDeviceSchedule(forceReschedule: false);
      _statusMessage = 'Đã bỏ qua mục lịch và hủy nhắc cũ.';
      return true;
    } catch (error) {
      _actionError = _formatError('Không thể bỏ qua mục lịch', error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Xóa mục lịch — bắt buộc hủy nhắc cục bộ cũ ngay lập tức.
  Future<bool> deletePlanItem(String itemId) async {
    _actionError = null;
    _isMutating = true;
    notifyListeners();

    try {
      await repository.deletePlanItem(ownerUid: currentUserId, itemId: itemId);
      accountCoordinator.clearSnooze(ownerUid: currentUserId, itemId: itemId);
      _planItems = _planItems.where((i) => i.itemId != itemId).toList();
      await _reconcileDeviceSchedule(forceReschedule: false);
      _statusMessage = 'Đã xóa mục lịch và hủy nhắc cũ liên quan.';
      return true;
    } catch (error) {
      _actionError = _formatError('Không thể xóa mục lịch', error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Khôi phục / đồng bộ lại toàn bộ nhắc lịch (dùng sau khởi động lại máy hoặc kiểm tra thủ công).
  Future<void> syncNow({bool forceReschedule = true}) async {
    _actionError = null;
    _isMutating = true;
    notifyListeners();
    try {
      _permissionStatus = await gateway.checkPermissionStatus();
      _deviceTimezone = await gateway.detectDeviceTimezone();
      await _reconcileDeviceSchedule(forceReschedule: forceReschedule);
      _statusMessage = _permissionStatus.canScheduleLocal
          ? 'Đã đồng bộ xong: $_lastScheduledCount nhắc đã đặt, $_lastCanceledCount nhắc cũ đã hủy.'
          : 'Đã cập nhật danh sách dự kiến trong app (thiết bị chưa bật quyền thông báo cục bộ).';
    } catch (error) {
      _actionError = _formatError('Không thể đồng bộ lịch nhắc', error);
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Xử lý một sự kiện thông báo đến từ **Local** hoặc **FCM** qua bộ chống trùng `NotificationDeduplicator`.
  ///
  /// Trả về `true` nếu thông báo được phát; `false` nếu bị chặn do trùng nguồn (local ↔ FCM)
  /// hoặc rơi vào giờ yên lặng / quyền bị tắt.
  Future<bool> dispatchEventWithDeduplication({
    required ApprovedPlanReminderItem item,
    required NotificationChannelSource source,
  }) async {
    if (item.ownerUid != currentUserId || !item.isEligibleForReminder) {
      return false;
    }
    if (!_preferences.remindersEnabled) return false;
    final nowUtc = _nowProvider().toUtc();
    if (_preferences.isInQuietHours(nowUtc)) return false;

    final acquired = await accountCoordinator.tryAcquireDedupeKey(
      ownerUid: currentUserId,
      dedupeKey: item.dedupeKey,
      source: source,
      nowUtc: nowUtc,
    );
    if (!acquired) {
      _suppressedDuplicateCount++;
      notifyListeners();
      return false;
    }

    if (!_permissionStatus.canScheduleLocal) return false;

    final copy = NotificationPrivacyFormatter.format(
      item,
      isSnoozed: false,
      deferredByQuietHours: false,
    );
    final reminder = ScheduledReminder(
      notificationId: ReminderSchedulerEngine.stableNotificationId(
        ownerUid: currentUserId,
        itemId: item.itemId,
      ),
      ownerUid: currentUserId,
      planId: item.planId,
      itemId: item.itemId,
      itemType: item.itemType,
      dedupeKey: item.dedupeKey,
      originalScheduledAtUtc: item.startsAtUtc,
      effectiveScheduledAtUtc: nowUtc,
      timezoneName: _preferences.timezone,
      deferredByQuietHours: false,
      isSnoozed: false,
      lockScreenTitle: copy.lockScreenTitle,
      lockScreenBody: copy.lockScreenBody,
      inAppTitle: copy.inAppTitle,
      inAppBody: copy.inAppBody,
      hideDetailsOnLockScreen: _preferences.hideHealthDetailsOnLockScreen,
    );

    await gateway.showImmediate(reminder);
    return true;
  }

  /// Gửi thử ngay một thông báo riêng tư trên thiết bị thật để kiểm tra màn hình khóa.
  Future<bool> sendPrivacyTestNotification() async {
    _actionError = null;
    if (!_permissionStatus.canScheduleLocal) {
      _actionError =
          'Chưa có quyền thông báo trên thiết bị này để gửi thông báo thử.';
      notifyListeners();
      return false;
    }

    try {
      final nowUtc = _nowProvider().toUtc();
      final sampleItem = ApprovedPlanReminderItem(
        itemId: 'privacy-test-${nowUtc.millisecondsSinceEpoch}',
        planId: 'privacy-test-plan',
        ownerUid: currentUserId,
        itemType: ReminderItemType.habit,
        title: 'Kiểm tra màn hình khóa — dị ứng đậu phộng 65 kg',
        startsAt: nowUtc,
        planStatus: PlanApprovalStatus.approved,
        itemStatus: PlanItemStatus.approved,
      );
      final copy = NotificationPrivacyFormatter.format(
        sampleItem,
        isSnoozed: false,
        deferredByQuietHours: false,
      );
      final testReminder = ScheduledReminder(
        notificationId: ReminderSchedulerEngine.stableNotificationId(
          ownerUid: currentUserId,
          itemId: 'privacy-test-preview',
        ),
        ownerUid: currentUserId,
        planId: sampleItem.planId,
        itemId: sampleItem.itemId,
        itemType: sampleItem.itemType,
        dedupeKey: sampleItem.dedupeKey,
        originalScheduledAtUtc: nowUtc,
        effectiveScheduledAtUtc: nowUtc,
        timezoneName: _preferences.timezone,
        deferredByQuietHours: false,
        isSnoozed: false,
        lockScreenTitle: copy.lockScreenTitle,
        lockScreenBody: copy.lockScreenBody,
        inAppTitle: copy.inAppTitle,
        inAppBody: copy.inAppBody,
        hideDetailsOnLockScreen: _preferences.hideHealthDetailsOnLockScreen,
      );
      await gateway.showImmediate(testReminder);
      _statusMessage =
          'Đã gửi thông báo thử với nội dung màn hình khóa trung tính (không lộ thông tin sức khỏe).';
      notifyListeners();
      return true;
    } catch (error) {
      _actionError = _formatError('Không thể gửi thông báo thử', error);
      notifyListeners();
      return false;
    }
  }

  /// Dọn toàn bộ thông báo cục bộ và token thiết bị khi đăng xuất tài khoản hiện tại.
  Future<void> cleanupForSignOut() async {
    await accountCoordinator.handleBeforeSignOut(currentUserId);
    _scheduledReminders = [];
    notifyListeners();
  }

  Future<void> _reconcileDeviceSchedule({
    String? previousTimezoneOverride,
    required bool forceReschedule,
  }) async {
    final pending = await gateway.pendingNotifications();
    final plan = ReminderSchedulerEngine.reconcile(
      ownerUid: currentUserId,
      preferences: _preferences,
      planItems: _planItems,
      pendingOnDevice: pending,
      nowUtc: _nowProvider().toUtc(),
      activeSnoozesUtc: accountCoordinator.snoozesForOwner(currentUserId),
      previousTimezone: previousTimezoneOverride ?? _lastSyncedTimezone,
      forceReschedule: forceReschedule,
    );

    _scheduledReminders = plan.desiredReminders;
    _lastCanceledCount = plan.notificationIdsToCancel.length;
    _lastScheduledCount = 0;

    // Luôn hủy thông báo cũ ngay cả khi vừa tắt nhắc lịch hoặc tài khoản đổi.
    for (final id in plan.notificationIdsToCancel) {
      await gateway.cancel(id);
    }

    // Chỉ gọi API đặt lịch thiết bị khi quyền thông báo được cấp và nền tảng hỗ trợ.
    if (_permissionStatus.canScheduleLocal) {
      for (final reminder in plan.remindersToSchedule) {
        await gateway.schedule(reminder);
        _lastScheduledCount++;
      }
    }

    _lastSyncedTimezone = _preferences.timezone;
  }

  String _formatError(String prefix, Object error) {
    if (error is NotificationSyncException) return error.message;
    if (error is FormatException) return error.message;
    return '$prefix. Vui lòng thử lại.';
  }
}
