import '../../../../core/utils/date_helper.dart';
import '../entities/insight_data_source.dart';
import '../entities/weekly_insights_summary.dart';

/// Bộ định dạng hiển thị và kiểm tra an toàn ngôn ngữ cho Dashboard tuần (Issue #12 - Tiêu chí 2).
///
/// Bảo đảm:
/// 1. Luôn tách bạch "Chưa ghi nhận" khỏi "Không hoàn thành".
/// 2. Hiển thị tường minh nguồn dữ liệu (nhập tay / tự khai báo / thiết bị GPS / camera).
/// 3. Không bao giờ gọi tỷ lệ kỷ luật hay độ đều đặn là "điểm sức khỏe" hay đánh giá y khoa.
class InsightsDisplayFormatter {
  const InsightsDisplayFormatter._();

  static const List<String> forbiddenMedicalClaims = [
    'điểm sức khỏe',
    'diem suc khoe',
    'health score',
    'chẩn đoán',
    'chan doan',
    'phác đồ điều trị',
    'cải thiện bệnh lý',
  ];

  /// Kiểm tra một nhãn/tiêu đề hiển thị có vi phạm ranh giới phi y khoa hay không
  /// (bỏ qua câu phủ định tường minh "không phải điểm sức khỏe").
  static bool containsForbiddenHealthScoreClaim(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll('không phải điểm sức khỏe', '')
        .replaceAll('khong phai diem suc khoe', '')
        .replaceAll('không gọi là điểm sức khỏe', '');
    for (final phrase in forbiddenMedicalClaims) {
      if (normalized.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  /// Định dạng khoảng tuần hiển thị: "23/11/2026 – 29/11/2026".
  static String formatWeekRange(DateTime weekStart, DateTime weekEnd) {
    return '${_ddMmYyyy(weekStart)} – ${_ddMmYyyy(weekEnd)}';
  }

  /// Định dạng tỷ lệ hoàn thành thói quen: trả "Chưa có lượt đến hạn" nếu `null`.
  static String formatCompletionRate(double? ratePercent) {
    if (ratePercent == null) return 'Chưa có lượt đến hạn';
    final text = ratePercent == ratePercent.roundToDouble()
        ? ratePercent.toStringAsFixed(0)
        : ratePercent.toStringAsFixed(1);
    return '$text%';
  }

  /// Tóm tắt rõ ràng nguồn dữ liệu cho phần vận động (nhập tay vs thiết bị GPS).
  static String formatActivitySources(WeeklyActivityInsights activity) {
    if (!activity.hasData) {
      return 'Nguồn: Chưa có dữ liệu ghi nhận';
    }
    final parts = <String>[];
    if (activity.gpsSessionCount > 0) {
      parts.add(
        '${InsightDataSource.deviceGps.label}: ${activity.gpsSessionCount} buổi',
      );
    }
    if (activity.manualSessionCount > 0) {
      parts.add(
        '${InsightDataSource.manualInput.label}: ${activity.manualSessionCount} buổi',
      );
    }
    if (activity.unknownSourceSessionCount > 0) {
      parts.add(
        '${InsightDataSource.unknownSource.label}: ${activity.unknownSourceSessionCount} buổi',
      );
    }
    return 'Nguồn: ${parts.join(' • ')}';
  }

  /// Tóm tắt rõ ràng nguồn dữ liệu cho phần bữa ăn (camera/thư viện vs nhập tay).
  static String formatMealSources(WeeklyMealInsights meals) {
    if (!meals.hasData) {
      return 'Nguồn: Chưa có dữ liệu ghi nhận';
    }
    final parts = <String>[];
    if (meals.withPhotoCount > 0) {
      parts.add(
        '${InsightDataSource.cameraOrGallery.label}: ${meals.withPhotoCount} bữa',
      );
    }
    if (meals.manualOnlyCount > 0) {
      parts.add(
        '${InsightDataSource.manualInput.label}: ${meals.manualOnlyCount} bữa',
      );
    }
    return 'Nguồn: ${parts.join(' • ')}';
  }

  /// Định dạng quãng đường ước tính GPS (vẫn hiển thị 0 m nếu có phiên GPS 0 m).
  static String formatEstimatedDistance(
    double meters, {
    bool hasGpsSession = false,
  }) {
    if (meters <= 0) {
      return hasGpsSession ? '0 m (ước tính GPS)' : 'Không có quãng đường GPS';
    }
    if (meters < 1000) {
      return '${meters.round()} m (ước tính GPS)';
    }
    return '${(meters / 1000).toStringAsFixed(2)} km (ước tính GPS)';
  }

  /// Tạo nhận xét ngắn trung lập theo tuần (tuyệt đối không đưa khuyến cáo y khoa hay phạt thiếu dữ liệu).
  static List<String> buildNeutralWeeklyNotes(WeeklyInsightsSummary summary) {
    final notes = <String>[];
    if (!summary.hasAnyData) {
      notes.add(
        'Tuần này chưa có bản ghi nào. Dữ liệu trống được hiển thị là "Chưa ghi nhận", không tính là không hoàn thành.',
      );
      return notes;
    }

    if (summary.habits.totalUnloggedCount > 0) {
      notes.add(
        'Có ${summary.habits.totalUnloggedCount} lượt thói quen chưa ghi nhận (tách riêng với ${summary.habits.explicitFailedCount} lượt không hoàn thành).',
      );
    }
    if (summary.habits.skippedCount > 0) {
      notes.add(
        '${summary.habits.skippedCount} lượt bỏ qua có lý do đã được giữ nguyên chuỗi streak theo quy tắc kỷ luật.',
      );
    }
    if (summary.sleep.hasData && summary.sleep.unloggedDaysCount > 0) {
      notes.add(
        'Thời lượng ngủ trung bình chỉ tính trên ${summary.sleep.loggedDaysCount} ngày đã tự khai báo; ${summary.sleep.unloggedDaysCount} ngày chưa ghi nhận không bị tính là 0 giờ.',
      );
    }
    if (summary.sleep.daytimeSleepCount > 0) {
      notes.add(
        'Đã ghi nhận ${summary.sleep.daytimeSleepCount} giấc ngủ ban ngày phù hợp lịch làm ca.',
      );
    }
    if (notes.isEmpty) {
      notes.add(
        'Các mục đã ghi nhận trong tuần được tổng hợp đầy đủ từ nhật ký cá nhân của bạn.',
      );
    }
    return List<String>.unmodifiable(notes);
  }

  static String shortWeekdayLabel(DateTime date) =>
      DateHelper.weekdayToVietnamese(date.weekday, short: true);

  static String _ddMmYyyy(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }
}
