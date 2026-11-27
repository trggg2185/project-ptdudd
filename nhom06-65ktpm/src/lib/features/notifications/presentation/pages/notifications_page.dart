import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../profile/domain/profile_time.dart';
import '../../domain/entities/approved_plan_reminder_item.dart';
import '../../domain/entities/scheduled_reminder.dart';
import '../../domain/logic/notification_privacy_formatter.dart';
import '../../domain/repositories/local_notification_gateway.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/services/notification_account_coordinator.dart';
import '../controllers/notification_controller.dart';
import '../widgets/quiet_hours_dialog.dart';

/// Màn hình quản lý **Nhắc lịch cục bộ, Giờ yên lặng & Quyền riêng tư màn hình khóa** (Issue #6).
///
/// - Tự thích ứng bố cục: 1 cột trên Android (`< 760px`) và 2 cột trên Web/màn rộng (`>= 760px`).
/// - Chỉ tạo nhắc cho các mục thuộc lịch **đã duyệt (`approved`)**; hiển thị rõ mục nháp bị loại.
/// - Tôn trọng giờ yên lặng (ban đêm lẫn ca đêm), hỗ trợ tạm hoãn (snooze), đổi múi giờ,
///   khôi phục lịch khi mở lại ứng dụng và cảnh báo rõ khi quyền thông báo bị tắt.
class NotificationsPage extends StatefulWidget {
  final NotificationRepository repository;
  final LocalNotificationGateway gateway;
  final String currentUserId;
  final NotificationAccountCoordinator? accountCoordinator;
  final DateTime Function()? nowProvider;

  const NotificationsPage({
    super.key,
    required this.repository,
    required this.gateway,
    required this.currentUserId,
    this.accountCoordinator,
    this.nowProvider,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  static const double _wideBreakpoint = 760;

  static const List<String> _supportedTimezones = [
    'Asia/Ho_Chi_Minh',
    'Asia/Bangkok',
    'Asia/Singapore',
    'Asia/Tokyo',
    'Asia/Seoul',
    'Europe/London',
    'America/New_York',
    'America/Los_Angeles',
    'UTC',
  ];

  late final NotificationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = NotificationController(
      repository: widget.repository,
      gateway: widget.gateway,
      currentUserId: widget.currentUserId,
      accountCoordinator: widget.accountCoordinator,
      nowProvider: widget.nowProvider,
    );
    _controller.loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.refreshOnAppResumed();
    }
  }

  Future<void> _openQuietHoursDialog() async {
    final prefs = _controller.preferences;
    final result = await showDialog<QuietHoursDialogResult>(
      context: context,
      builder: (_) => QuietHoursDialog(
        initialStartMinute: prefs.quietHoursStartMinute,
        initialEndMinute: prefs.quietHoursEndMinute,
      ),
    );
    if (!mounted || result == null) return;

    if (result is SaveQuietHoursResult) {
      await _controller.updatePreferences(
        prefs.copyWith(
          quietHoursStartMinute: result.startMinute,
          quietHoursEndMinute: result.endMinute,
        ),
      );
    } else if (result is DisableQuietHoursResult) {
      await _controller.updatePreferences(
        prefs.copyWith(clearQuietHours: true),
      );
    }
  }

  String _formatZonedClock(DateTime utcInstant, String timezoneName) {
    final location =
        profileLocation(timezoneName) ??
        profileLocation(defaultProfileZone) ??
        tz.UTC;
    final zoned = tz.TZDateTime.from(utcInstant.toUtc(), location);
    final hh = zoned.hour.toString().padLeft(2, '0');
    final mm = zoned.minute.toString().padLeft(2, '0');
    final dd = zoned.day.toString().padLeft(2, '0');
    final mo = zoned.month.toString().padLeft(2, '0');
    return '$hh:$mm • $dd/$mo';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhắc lịch & Giờ yên lặng'),
        actions: [
          Semantics(
            button: true,
            label: 'Đồng bộ lại toàn bộ nhắc lịch cục bộ',
            child: IconButton(
              key: const Key('notifications_resync_button'),
              tooltip: 'Đồng bộ lại lịch nhắc',
              onPressed: () => _controller.syncNow(forceReschedule: true),
              icon: const Icon(Icons.sync),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            if (_controller.isLoading && !_controller.hasLoadedOnce) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Đang tải cấu hình nhắc lịch và kiểm tra quyền...'),
                  ],
                ),
              );
            }

            if (_controller.loadError != null && !_controller.hasLoadedOnce) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'Không thể tải cấu hình nhắc lịch',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _controller.loadError!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _controller.loadAll,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= _wideBreakpoint;
                if (isWide) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          key: const Key('notifications_wide_layout'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: SingleChildScrollView(
                                child: _buildSettingsColumn(context),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 6,
                              child: SingleChildScrollView(
                                child: _buildScheduleColumn(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return SingleChildScrollView(
                  key: const Key('notifications_compact_layout'),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSettingsColumn(context),
                      const SizedBox(height: 16),
                      _buildScheduleColumn(context),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettingsColumn(BuildContext context) {
    final prefs = _controller.preferences;
    final tzOptions = {
      ..._supportedTimezones,
      prefs.timezone,
      if (_controller.deviceTimezone != null) _controller.deviceTimezone!,
    }.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPermissionBanner(context),
        if (_controller.hasTimezoneMismatch) ...[
          const SizedBox(height: 12),
          _buildTimezoneMismatchBanner(context),
        ],
        if (_controller.actionError != null) ...[
          const SizedBox(height: 12),
          _FeedbackBanner(
            isError: true,
            message: _controller.actionError!,
            onDismiss: _controller.clearActionError,
          ),
        ],
        if (_controller.statusMessage != null) ...[
          const SizedBox(height: 12),
          _FeedbackBanner(
            isError: false,
            message: _controller.statusMessage!,
            onDismiss: _controller.clearStatusMessage,
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Cài đặt nhắc lịch cục bộ',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('reminders_enabled_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bật nhắc lịch từ lịch đã duyệt'),
                  subtitle: const Text(
                    'Ưu tiên thông báo cục bộ theo múi giờ; tự hủy khi sửa/xóa lịch hoặc đăng xuất.',
                  ),
                  value: prefs.remindersEnabled,
                  onChanged: _controller.isMutating
                      ? null
                      : (value) => _controller.updatePreferences(
                          prefs.copyWith(remindersEnabled: value),
                        ),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bedtime_outlined),
                  title: const Text('Giờ yên lặng'),
                  subtitle: Text(
                    prefs.hasQuietHours
                        ? '${prefs.quietHoursLabel} (${prefs.quietHoursCrossesMidnight ? "qua nửa đêm" : "trong ngày"})'
                        : 'Đang tắt — mọi nhắc lịch phát đúng giờ đã duyệt',
                  ),
                  trailing: OutlinedButton(
                    key: const Key('edit_quiet_hours_button'),
                    onPressed: _controller.isMutating
                        ? null
                        : _openQuietHoursDialog,
                    child: const Text('Chỉnh giờ'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('timezone_dropdown'),
                  isExpanded: true,
                  initialValue: prefs.timezone,
                  decoration: const InputDecoration(
                    labelText: 'Múi giờ nhắc lịch (IANA)',
                    helperText:
                        'Đổi múi giờ sẽ tự động hủy nhắc cũ và đặt lại toàn bộ theo múi giờ mới.',
                    helperMaxLines: 2,
                  ),
                  items: tzOptions
                      .map(
                        (zone) => DropdownMenuItem(
                          value: zone,
                          child: Text(zone, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _controller.isMutating
                      ? null
                      : (value) {
                          if (value != null && value != prefs.timezone) {
                            _controller.updatePreferences(
                              prefs.copyWith(timezone: value),
                            );
                          }
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('snooze_default_dropdown'),
                  isExpanded: true,
                  initialValue: prefs.defaultSnoozeMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Thời gian tạm hoãn mặc định',
                  ),
                  items: const [5, 10, 15, 30]
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text('$m phút'),
                        ),
                      )
                      .toList(),
                  onChanged: _controller.isMutating
                      ? null
                      : (value) {
                          if (value != null) {
                            _controller.updatePreferences(
                              prefs.copyWith(defaultSnoozeMinutes: value),
                            );
                          }
                        },
                ),
                const Divider(),
                SwitchListTile(
                  key: const Key('lock_screen_privacy_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ẩn chi tiết sức khỏe trên màn hình khóa'),
                  subtitle: const Text(
                    'Mặc định bật: thông báo ngoài màn hình khóa chỉ hiển thị nội dung trung tính.',
                  ),
                  value: prefs.hideHealthDetailsOnLockScreen,
                  onChanged: _controller.isMutating
                      ? null
                      : (value) => _controller.updatePreferences(
                          prefs.copyWith(hideHealthDetailsOnLockScreen: value),
                        ),
                ),
                const SizedBox(height: 8),
                Container(
                  key: const Key('lock_screen_preview_box'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xem trước trên màn hình khóa',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        NotificationPrivacyFormatter.neutralLockScreenTitle,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        NotificationPrivacyFormatter.neutralLockScreenBody,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('send_privacy_test_button'),
                  onPressed: _controller.permissionStatus.canScheduleLocal
                      ? _controller.sendPrivacyTestNotification
                      : null,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Gửi thử thông báo riêng tư'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildDeviceLimitsCard(context),
      ],
    );
  }

  Widget _buildPermissionBanner(BuildContext context) {
    final status = _controller.permissionStatus;
    final scheme = Theme.of(context).colorScheme;
    if (status == NotificationPermissionStatus.granted) {
      return Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('permission_granted_banner'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_outlined, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Quyền thông báo cục bộ đang bật. Hệ thống đã chống trùng với FCM và tự hủy khi đăng xuất.',
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isUnsupported =
        status == NotificationPermissionStatus.unsupportedPlatform;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('permission_warning_banner'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isUnsupported
                        ? 'Nền tảng hiện tại (Web/Desktop) không hỗ trợ hẹn giờ thông báo nền. Bạn vẫn có thể cấu hình giờ yên lặng và xem danh sách lịch trong ứng dụng.'
                        : 'Quyền thông báo đang bị tắt. Hãy cấp quyền hoặc bật trong Cài đặt Android để nhận nhắc lịch; danh sách việc trong app vẫn hiển thị bình thường.',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            if (!isUnsupported) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('request_permission_button'),
                  onPressed: _controller.requestNotificationPermission,
                  child: const Text('Cấp quyền thông báo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimezoneMismatchBanner(BuildContext context) {
    final detected = _controller.deviceTimezone!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('timezone_mismatch_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.public, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Phát hiện múi giờ thiết bị ($detected) khác cấu hình (${_controller.preferences.timezone}).',
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
          TextButton(
            key: const Key('apply_device_timezone_button'),
            onPressed: () => _controller.applyDeviceTimezone(detected),
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleColumn(BuildContext context) {
    final scheduled = _controller.scheduledReminders;
    final excluded = _controller.excludedItems;
    final tzName = _controller.preferences.timezone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Nhắc lịch từ lịch đã duyệt (${scheduled.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Chip(
                      label: Text(
                        _controller.preferences.remindersEnabled
                            ? 'Đang bật'
                            : 'Đang tắt',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (scheduled.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _controller.preferences.remindersEnabled
                          ? 'Chưa có mục nào sắp tới trong lịch đã duyệt để đặt nhắc. Lịch nháp (draft) sẽ không tạo nhắc.'
                          : 'Nhắc lịch cục bộ đang tắt. Toàn bộ thông báo chờ đã được hủy.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  ...scheduled.map(
                    (reminder) => _ScheduledReminderTile(
                      reminder: reminder,
                      formattedOriginalTime: _formatZonedClock(
                        reminder.originalScheduledAtUtc,
                        tzName,
                      ),
                      formattedEffectiveTime: _formatZonedClock(
                        reminder.effectiveScheduledAtUtc,
                        tzName,
                      ),
                      snoozeMinutes:
                          _controller.preferences.defaultSnoozeMinutes,
                      onSnooze: () => _controller.snoozeReminder(
                        reminder.itemId,
                      ),
                      onSkip: () => _controller.skipPlanItem(reminder.itemId),
                      onDelete: () =>
                          _controller.deletePlanItem(reminder.itemId),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mục không đặt nhắc — nháp / đã xong (${excluded.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Chỉ các mục thuộc lịch đã duyệt (approved) mới được tạo nhắc. '
                  'Mục nháp, đã hoàn thành hoặc đã bỏ qua luôn bị loại trừ.',
                ),
                const SizedBox(height: 8),
                if (excluded.isEmpty)
                  const Text('Không có mục bị loại trừ.')
                else
                  ...excluded.map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        item.planStatus == PlanApprovalStatus.draft ||
                                item.itemStatus == PlanItemStatus.draft
                            ? Icons.edit_note_outlined
                            : Icons.check_circle_outline,
                      ),
                      title: Text(item.title),
                      subtitle: Text(
                        '${item.itemType.displayLabel} • '
                        'Lịch: ${item.planStatus.name} • Mục: ${item.itemStatus.name}',
                      ),
                      trailing: const Text('Không nhắc'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceLimitsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Giới hạn thực tế thiết bị & bảo mật',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              '• Android Doze / tiết kiệm pin OEM (Xiaomi, Oppo, Huawei, Samsung) có thể làm trễ '
              'nhắc inexact vài phút; không cam kết chính xác tuyệt đối từng giây khi máy ngủ sâu.\n'
              '• Sau khi khởi động lại máy, receiver BOOT_COMPLETED hỗ trợ khôi phục nhắc, và mở lại '
              'ứng dụng sẽ tự đối chiếu khôi phục nếu hãng chặn chạy nền.\n'
              '• Đăng xuất hoặc đổi tài khoản Firebase sẽ tự hủy toàn bộ nhắc cục bộ và vô hiệu hóa '
              'device_tokens của tài khoản cũ.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduledReminderTile extends StatelessWidget {
  final ScheduledReminder reminder;
  final String formattedOriginalTime;
  final String formattedEffectiveTime;
  final int snoozeMinutes;
  final VoidCallback onSnooze;
  final VoidCallback onSkip;
  final VoidCallback onDelete;

  const _ScheduledReminderTile({
    required this.reminder,
    required this.formattedOriginalTime,
    required this.formattedEffectiveTime,
    required this.snoozeMinutes,
    required this.onSnooze,
    required this.onSkip,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    reminder.inAppBody,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  formattedEffectiveTime,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(reminder.itemType.displayLabel),
                ),
                if (reminder.deferredByQuietHours)
                  Chip(
                    key: Key('quiet_deferred_badge_${reminder.itemId}'),
                    visualDensity: VisualDensity.compact,
                    label: Text('Đã dời qua giờ yên lặng (gốc: $formattedOriginalTime)'),
                  ),
                if (reminder.isSnoozed)
                  Chip(
                    key: Key('snoozed_badge_${reminder.itemId}'),
                    visualDensity: VisualDensity.compact,
                    label: const Text('Đang tạm hoãn'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: Key('snooze_button_${reminder.itemId}'),
                  onPressed: onSnooze,
                  icon: const Icon(Icons.snooze, size: 18),
                  label: Text('Hoãn +$snoozeMinutes phút'),
                ),
                TextButton(
                  key: Key('skip_button_${reminder.itemId}'),
                  onPressed: onSkip,
                  child: const Text('Bỏ qua'),
                ),
                TextButton(
                  key: Key('delete_button_${reminder.itemId}'),
                  onPressed: onDelete,
                  child: const Text('Xóa mục'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  final bool isError;
  final String message;
  final VoidCallback onDismiss;

  const _FeedbackBanner({
    required this.isError,
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isError ? scheme.errorContainer : scheme.primaryContainer;
    final fg = isError ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: fg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: TextStyle(color: fg)),
            ),
            IconButton(
              tooltip: 'Đóng thông báo',
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 18, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
