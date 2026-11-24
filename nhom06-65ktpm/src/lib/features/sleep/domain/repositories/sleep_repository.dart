import '../entities/routine_block.dart';
import '../entities/sleep_log.dart';
import '../entities/sleep_window.dart';

/// Ngoại lệ ném ra khi thao tác tải hoặc lưu dữ liệu giấc ngủ với backend thất bại.
/// Không nuốt lỗi ngầm để controller và UI hiển thị trạng thái lỗi trung thực + nút thử lại.
class SleepSyncException implements Exception {
  final String message;
  final Object? cause;

  const SleepSyncException(this.message, {this.cause});

  @override
  String toString() =>
      'SleepSyncException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Giao diện kho dữ liệu cho module Giấc ngủ & Lịch sinh hoạt (Issue #5).
abstract interface class SleepRepository {
  /// Lấy danh sách nhật ký ngủ của tài khoản [ownerUid], sắp xếp mới nhất trước.
  Future<List<SleepLog>> getSleepLogs({
    required String ownerUid,
    DateTime? fromDate,
    DateTime? toDate,
  });

  /// Lưu mới hoặc cập nhật bản ghi nhật ký ngủ.
  Future<void> saveSleepLog(SleepLog log);

  /// Xóa bản ghi nhật ký ngủ theo [logId] thuộc về [ownerUid].
  Future<void> deleteSleepLog({
    required String ownerUid,
    required String logId,
  });

  /// Lấy khoảng ngủ mong muốn hiện tại của tài khoản [ownerUid] (null nếu chưa thiết lập).
  Future<SleepWindow?> getSleepWindow(String ownerUid);

  /// Lưu khoảng ngủ mong muốn của tài khoản [ownerUid].
  Future<void> saveSleepWindow({
    required String ownerUid,
    required SleepWindow window,
  });

  /// Xóa khoảng ngủ mong muốn (quay về trạng thái chưa đặt mốc cố định).
  Future<void> clearSleepWindow(String ownerUid);

  /// Lấy danh sách các khối lịch bận / ca làm việc (từ `availability_blocks` hoặc fixture)
  /// để hiển thị ngữ cảnh trên giao diện lịch sinh hoạt 24 giờ responsive.
  Future<List<RoutineBlock>> getRoutineBlocks({
    required String ownerUid,
    DateTime? referenceDate,
  });
}
