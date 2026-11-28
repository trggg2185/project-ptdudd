import '../logic/notification_deduplicator.dart';
import '../repositories/local_notification_gateway.dart';
import '../repositories/notification_repository.dart';

/// Điều phối vòng đời nhắc lịch khi **đăng xuất** hoặc **đổi tài khoản Firebase** (Issue #6).
///
/// Bảo đảm:
/// 1. Đăng xuất hoặc chuyển từ tài khoản A sang tài khoản B lập tức hủy toàn bộ thông báo cục bộ
///    đang chờ trên thiết bị (`gateway.cancelAll()`), không bao giờ để lịch tài khoản cũ phát nổ.
/// 2. Xóa bộ nhớ chống trùng (`NotificationDeduplicator`) và trạng thái tạm hoãn của tài khoản cũ.
/// 3. Hủy liên kết (`is_active = false`) các `device_tokens` của tài khoản cũ nếu có repository
///    (bắt lỗi mạng an toàn để không làm kẹt thao tác đăng xuất).
class NotificationAccountCoordinator {
  final LocalNotificationGateway gateway;
  final NotificationDeduplicator deduplicator;
  final NotificationRepository? Function()? repositoryResolver;

  String? _activeOwnerUid;
  final Map<String, Map<String, DateTime>> _snoozesByOwner = {};
  final Set<String> _recentlyDeactivatedOnSignOut = {};

  NotificationAccountCoordinator({
    required this.gateway,
    NotificationDeduplicator? deduplicator,
    this.repositoryResolver,
  }) : deduplicator = deduplicator ?? NotificationDeduplicator();

  String? get activeOwnerUid => _activeOwnerUid;

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

  /// Gọi trước khi thực thi `auth.signOut()` để thu hồi nhắc lịch & vô hiệu hóa token của [ownerUid].
  Future<void> handleBeforeSignOut(String ownerUid) async {
    if (ownerUid.trim().isEmpty) return;
    await _cleanupOwner(ownerUid, deactivateRemoteTokens: true);
    _recentlyDeactivatedOnSignOut.add(ownerUid);
    if (_activeOwnerUid == ownerUid) {
      _activeOwnerUid = null;
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
  }

  Future<void> _cleanupOwner(
    String ownerUid, {
    required bool deactivateRemoteTokens,
  }) async {
    deduplicator.clearForOwner(ownerUid);
    _snoozesByOwner.remove(ownerUid);

    try {
      await gateway.cancelAll();
    } catch (_) {
      // Không chặn đăng xuất nếu thiết bị/Web không hỗ trợ cancelAll.
    }

    if (deactivateRemoteTokens) {
      final repo = repositoryResolver?.call();
      if (repo != null) {
        try {
          await repo.deactivateDeviceTokens(ownerUid);
        } catch (_) {
          // Không chặn đăng xuất khi ngoại tuyến; token vẫn cô lập theo RLS.
        }
      }
    }
  }
}
