import '../entities/scheduled_reminder.dart';

class _DispatchRecord {
  final NotificationChannelSource source;
  final DateTime dispatchedAtUtc;

  const _DispatchRecord({
    required this.source,
    required this.dispatchedAtUtc,
  });
}

/// Bộ chống trùng thông báo giữa **Local Notifications** và **FCM** (Issue #6).
///
/// Quy tắc:
/// - Phân vùng hoàn toàn theo `ownerUid`.
/// - Mỗi sự kiện có khóa `dedupeKey` (ví dụ `uid:exercise:item-1:2026-11-27T10:00:00.000Z`).
/// - Nếu thông báo cục bộ đã phát (hoặc đã được ghi nhận) trong cửa sổ [dedupeWindow],
///   thông báo FCM cùng khóa sẽ bị chặn (và ngược lại) để người dùng không nhận 2 thông báo giống nhau.
/// - Khi đăng xuất hoặc đổi tài khoản phải xóa toàn bộ trạng thái của tài khoản cũ.
class NotificationDeduplicator {
  final Duration dedupeWindow;
  final Map<String, Map<String, _DispatchRecord>> _recordsByOwner = {};

  NotificationDeduplicator({
    this.dedupeWindow = const Duration(minutes: 15),
  });

  /// Kiểm tra có được phép phát thông báo với `(ownerUid, dedupeKey)` tại thời điểm [nowUtc] không.
  /// Nếu hợp lệ, tự động ghi nhận để chặn các bản trùng từ nguồn khác (local ↔ FCM).
  bool tryAcquire({
    required String ownerUid,
    required String dedupeKey,
    required NotificationChannelSource source,
    required DateTime nowUtc,
  }) {
    final normalizedNow = nowUtc.toUtc();
    final ownerMap = _recordsByOwner.putIfAbsent(ownerUid, () => {});
    _pruneExpired(ownerMap, normalizedNow);

    final existing = ownerMap[dedupeKey];
    if (existing != null) {
      final elapsed = normalizedNow.difference(existing.dispatchedAtUtc);
      if (!elapsed.isNegative && elapsed < dedupeWindow) {
        return false;
      }
    }

    ownerMap[dedupeKey] = _DispatchRecord(
      source: source,
      dispatchedAtUtc: normalizedNow,
    );
    return true;
  }

  /// Kiểm tra khóa đã bị tiêu thụ gần đây chưa mà không ghi đè trạng thái.
  bool isRecentlyDispatched({
    required String ownerUid,
    required String dedupeKey,
    required DateTime nowUtc,
  }) {
    final ownerMap = _recordsByOwner[ownerUid];
    if (ownerMap == null) return false;
    final normalizedNow = nowUtc.toUtc();
    _pruneExpired(ownerMap, normalizedNow);
    return ownerMap.containsKey(dedupeKey);
  }

  /// Số khóa chống trùng đang hoạt động của một tài khoản.
  int activeCountForOwner(String ownerUid) =>
      _recordsByOwner[ownerUid]?.length ?? 0;

  /// Xóa toàn bộ bộ nhớ chống trùng của tài khoản cũ khi đăng xuất / đổi tài khoản.
  void clearForOwner(String ownerUid) {
    _recordsByOwner.remove(ownerUid);
  }

  /// Xóa sạch toàn bộ bộ nhớ chống trùng trên thiết bị.
  void clearAll() {
    _recordsByOwner.clear();
  }

  void _pruneExpired(Map<String, _DispatchRecord> ownerMap, DateTime nowUtc) {
    ownerMap.removeWhere((_, record) {
      final elapsed = nowUtc.difference(record.dispatchedAtUtc);
      return elapsed >= dedupeWindow;
    });
  }
}
