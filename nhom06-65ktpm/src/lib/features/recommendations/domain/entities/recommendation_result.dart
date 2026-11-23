import 'hard_filter_result.dart';

/// Một ứng viên đã vượt qua lọc cứng, được xếp hạng và kèm lý do giải thích cụ thể.
class RankedRecommendation<T> {
  final T item;
  final double score;
  final List<String> reasons;
  final String explanation;
  final String conditionsSummary;

  const RankedRecommendation({
    required this.item,
    required this.score,
    required this.reasons,
    required this.explanation,
    required this.conditionsSummary,
  });
}

/// Kết quả gợi ý có giải thích và danh sách lựa chọn thay thế.
/// Khi không có ứng viên hợp lệ, danh sách luôn trả rỗng và không nới lỏng ràng buộc.
class RecommendationResult<T> {
  static const String productRuleDisclaimer =
      'Gợi ý được tính theo quy tắc sản phẩm từ hồ sơ cá nhân và danh mục kiểm duyệt, không phải chỉ định y khoa hay mô hình dự báo hiệu quả sức khỏe.';

  final RecommendationGateStatus status;
  final String? emptyReason;
  final List<String> missingFields;
  final List<RankedRecommendation<T>> recommendations;
  final List<RankedRecommendation<T>> alternatives;
  final int excludedCount;
  final String note;

  const RecommendationResult({
    required this.status,
    this.emptyReason,
    this.missingFields = const [],
    this.recommendations = const [],
    this.alternatives = const [],
    this.excludedCount = 0,
    this.note = productRuleDisclaimer,
  });

  bool get isEmpty => recommendations.isEmpty;

  bool get hasRecommendations => recommendations.isNotEmpty;

  RankedRecommendation<T>? get primaryRecommendation =>
      recommendations.isEmpty ? null : recommendations.first;
}
