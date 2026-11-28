import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/approved_plan_reminder_item.dart';
import '../../domain/repositories/fcm_messaging_gateway.dart';

/// Triển khai `FcmMessagingGateway` kết nối trực tiếp `firebase_messaging` (v17 API:
/// `register()`, `unregister()`, `onRegistered`, `FirebaseMessaging.onMessage`).
///
/// - Kiểm tra `Firebase.apps.isNotEmpty` trước khi gọi SDK để không văng lỗi trong
///   widget test hoặc chế độ demo ngoại tuyến chưa khởi tạo Firebase.
/// - Chỉ trích xuất siêu dữ liệu điều phối (`dedupe_key`, `owner_uid`, `item_id`, `plan_id`,
///   `item_type`, `scheduled_at`), KHÔNG đưa nội dung nhạy cảm ra màn hình khóa.
class FirebaseMessagingGateway implements FcmMessagingGateway {
  FirebaseMessagingGateway();

  String? _cachedRegistrationId;

  bool get _hasFirebaseApp {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  String get platformName {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'android';
  }

  @override
  Future<String?> getToken() async {
    if (!_hasFirebaseApp) return null;
    final completer = Completer<String?>();
    StreamSubscription<String>? sub;
    try {
      sub = FirebaseMessaging.instance.onRegistered.listen(
        (id) {
          final trimmed = id.trim();
          if (trimmed.isNotEmpty && !completer.isCompleted) {
            _cachedRegistrationId = trimmed;
            completer.complete(trimmed);
          }
        },
        onError: (_) {
          if (!completer.isCompleted) {
            completer.complete(_cachedRegistrationId);
          }
        },
      );
      await FirebaseMessaging.instance.register();
      return await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => _cachedRegistrationId,
      );
    } catch (_) {
      return _cachedRegistrationId;
    } finally {
      await sub?.cancel();
    }
  }

  @override
  Future<void> deleteToken() async {
    if (!_hasFirebaseApp) return;
    try {
      _cachedRegistrationId = null;
      await FirebaseMessaging.instance.unregister();
    } catch (_) {
      // Không chặn đăng xuất khi offline; hàng đợi retry Supabase sẽ tiếp tục thu hồi khi có mạng.
    }
  }

  @override
  Stream<String> get onTokenRefresh {
    if (!_hasFirebaseApp) return const Stream<String>.empty();
    try {
      return FirebaseMessaging.instance.onRegistered.map((id) {
        final trimmed = id.trim();
        if (trimmed.isNotEmpty) {
          _cachedRegistrationId = trimmed;
        }
        return trimmed;
      });
    } catch (_) {
      return const Stream<String>.empty();
    }
  }

  @override
  Stream<IncomingFcmMessage> get onForegroundMessage {
    if (!_hasFirebaseApp) return const Stream<IncomingFcmMessage>.empty();
    try {
      return FirebaseMessaging.onMessage.map(_mapRemoteMessage);
    } catch (_) {
      return const Stream<IncomingFcmMessage>.empty();
    }
  }

  static IncomingFcmMessage _mapRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final rawScheduled = data['scheduled_at'] as String?;
    return IncomingFcmMessage(
      messageId: message.messageId,
      ownerUid: (data['owner_uid'] as String?)?.trim(),
      planId: (data['plan_id'] as String?)?.trim(),
      itemId: (data['item_id'] as String?)?.trim(),
      itemType: ReminderItemType.fromDb(data['item_type'] as String?),
      dedupeKey: (data['dedupe_key'] as String?)?.trim(),
      scheduledAtUtc: rawScheduled != null
          ? DateTime.tryParse(rawScheduled)?.toUtc()
          : null,
      sentTimeUtc: message.sentTime?.toUtc(),
    );
  }
}
