import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../profile/domain/profile_time.dart';
import '../../domain/entities/scheduled_reminder.dart';
import '../../domain/repositories/local_notification_gateway.dart';

/// Triển khai `LocalNotificationGateway` dùng `flutter_local_notifications` cho Android thật.
///
/// - Tạo kênh riêng `healthylife_approved_reminders` với `NotificationVisibility.private`
///   và luôn gửi chuỗi trung tính khi `hideDetailsOnLockScreen == true` để màn hình khóa
///   tuyệt đối không lộ thông tin sức khỏe.
/// - Dùng `AndroidScheduleMode.inexactAllowWhileIdle` để tương thích Android 7–16 mà không
///   ép quyền `USE_EXACT_ALARM` bị hạn chế trên Google Play.
/// - Trên Web/Desktop (không hỗ trợ hẹn giờ nền đáng tin cậy), hạ cấp an toàn sang
///   `NotificationPermissionStatus.unsupportedPlatform` mà không văng ngoại lệ.
class FlutterLocalNotificationsGateway implements LocalNotificationGateway {
  static const String channelId = 'healthylife_approved_reminders';
  static const String channelName = 'Nhắc lịch HealthyLife đã duyệt';
  static const String channelDescription =
      'Nhắc lịch cục bộ theo múi giờ cho các hoạt động trong lịch đã duyệt.';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  FlutterLocalNotificationsGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  bool get _isAndroidNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    // Đảm bảo dữ liệu múi giờ IANA đã khởi tạo qua helper chung của nhóm.
    profileLocation(defaultProfileZone);

    if (!_isAndroidNative) {
      _initialized = true;
      return;
    }

    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: settings);
      _initialized = true;
    } catch (_) {
      // Giữ an toàn khi chạy trong môi trường không có platform channel (widget test).
    }
  }

  @override
  Future<NotificationPermissionStatus> checkPermissionStatus() async {
    if (!_isAndroidNative) {
      return NotificationPermissionStatus.unsupportedPlatform;
    }
    await initialize();
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await androidImpl?.areNotificationsEnabled();
      if (enabled == true) return NotificationPermissionStatus.granted;
      if (enabled == false) return NotificationPermissionStatus.denied;
      return NotificationPermissionStatus.unknown;
    } catch (_) {
      return NotificationPermissionStatus.unknown;
    }
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    if (!_isAndroidNative) {
      return NotificationPermissionStatus.unsupportedPlatform;
    }
    await initialize();
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidImpl?.requestNotificationsPermission();
      if (granted == true) return NotificationPermissionStatus.granted;
      final stillEnabled = await androidImpl?.areNotificationsEnabled();
      return stillEnabled == true
          ? NotificationPermissionStatus.granted
          : NotificationPermissionStatus.denied;
    } catch (_) {
      return NotificationPermissionStatus.denied;
    }
  }

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    if (!_isAndroidNative) return;
    await initialize();

    final location =
        profileLocation(reminder.timezoneName) ??
        profileLocation(defaultProfileZone) ??
        tz.UTC;
    final scheduledDate = tz.TZDateTime.from(
      reminder.effectiveScheduledAtUtc.toUtc(),
      location,
    );

    await _plugin.zonedSchedule(
      id: reminder.notificationId,
      title: reminder.systemNotificationTitle,
      body: reminder.systemNotificationBody,
      scheduledDate: scheduledDate,
      notificationDetails: _buildNotificationDetails(reminder),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: _encodeNonSensitivePayload(reminder),
    );
  }

  @override
  Future<void> showImmediate(ScheduledReminder reminder) async {
    if (!_isAndroidNative) return;
    await initialize();

    await _plugin.show(
      id: reminder.notificationId,
      title: reminder.systemNotificationTitle,
      body: reminder.systemNotificationBody,
      notificationDetails: _buildNotificationDetails(reminder),
      payload: _encodeNonSensitivePayload(reminder),
    );
  }

  @override
  Future<void> cancel(int notificationId) async {
    if (!_isAndroidNative) return;
    await initialize();
    await _plugin.cancel(id: notificationId);
  }

  @override
  Future<void> cancelAll() async {
    if (!_isAndroidNative) return;
    await initialize();
    await _plugin.cancelAll();
  }

  @override
  Future<List<PendingDeviceNotification>> pendingNotifications() async {
    if (!_isAndroidNative) return const [];
    await initialize();
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.map((req) {
        final meta = _decodePayload(req.payload);
        return PendingDeviceNotification(
          notificationId: req.id,
          ownerUid: meta['ownerUid'] as String?,
          itemId: meta['itemId'] as String?,
          dedupeKey: meta['dedupeKey'] as String?,
          fingerprint: meta['fingerprint'] as String?,
          timezoneName: meta['tz'] as String?,
          scheduledAtUtc: meta['effectiveUtc'] != null
              ? DateTime.tryParse(meta['effectiveUtc'] as String)?.toUtc()
              : null,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<String> detectDeviceTimezone() async {
    // Đọc tên múi giờ chuẩn nếu thiết bị trả IANA, hoặc ánh xạ độ lệch UTC phổ biến an toàn.
    final now = DateTime.now();
    final rawName = now.timeZoneName.trim();
    if (profileLocation(rawName) != null) {
      return rawName;
    }
    final offsetHours = now.timeZoneOffset.inHours;
    final offsetMinutes = now.timeZoneOffset.inMinutes;
    if (offsetMinutes == 7 * 60) return 'Asia/Ho_Chi_Minh';
    if (offsetMinutes == 9 * 60) return 'Asia/Tokyo';
    if (offsetMinutes == 8 * 60) return 'Asia/Singapore';
    if (offsetMinutes == 0) return 'UTC';
    if (offsetHours == -8 || offsetHours == -7) return 'America/Los_Angeles';
    if (offsetHours == -5 || offsetHours == -4) return 'America/New_York';
    return defaultProfileZone;
  }

  NotificationDetails _buildNotificationDetails(ScheduledReminder reminder) {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        // Luôn đặt chế độ private để màn hình khóa Android không bao giờ lộ thông tin sức khỏe.
        visibility: NotificationVisibility.private,
        category: AndroidNotificationCategory.reminder,
      ),
    );
  }

  /// Chỉ lưu siêu dữ liệu kỹ thuật tối thiểu trong payload — KHÔNG đưa chi tiết sức khỏe.
  static String _encodeNonSensitivePayload(ScheduledReminder reminder) {
    return jsonEncode({
      'ownerUid': reminder.ownerUid,
      'itemId': reminder.itemId,
      'dedupeKey': reminder.dedupeKey,
      'fingerprint': reminder.scheduleFingerprint,
      'tz': reminder.timezoneName,
      'effectiveUtc': reminder.effectiveScheduledAtUtc
          .toUtc()
          .toIso8601String(),
    });
  }

  static Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Bỏ qua payload cũ không phải JSON.
    }
    return const {};
  }
}
