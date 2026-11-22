/// Trạng thái kiểm tra điều kiện đầu vào trước khi gợi ý.
enum RecommendationGateStatus {
  /// Đủ điều kiện để lọc cứng và xếp hạng.
  ready,

  /// Chưa xác nhận đủ 18 tuổi.
  underageBlocked,

  /// Người dùng tự khai báo cần tư vấn chuyên môn; chỉ dùng lịch thủ công.
  professionalGuidanceRequired,

  /// Mục tiêu nằm ngoài phạm vi lối sống (điều trị y khoa hoặc giảm cân nhanh).
  unsafeGoalBlocked,

  /// Thiếu dữ liệu bắt buộc hoặc khung thời lượng không hợp lý.
  missingRequiredInput,

  /// Chưa xác nhận tình trạng dị ứng nên chưa bật gợi ý món ăn.
  allergiesUnconfirmed,
}

/// Ghi nhận một ứng viên bị loại ở bước lọc cứng kèm danh sách lý do cụ thể.
class FilteredOutCandidate<T> {
  final T item;
  final List<String> reasons;

  const FilteredOutCandidate({required this.item, required this.reasons});
}

/// Kết quả của bước kiểm tra đầu vào và lọc cứng trước khi xếp hạng.
class HardFilterResult<T> {
  final RecommendationGateStatus status;
  final String? message;
  final List<String> missingFields;
  final List<T> eligibleItems;
  final List<FilteredOutCandidate<T>> excludedItems;

  const HardFilterResult({
    required this.status,
    this.message,
    this.missingFields = const [],
    this.eligibleItems = const [],
    this.excludedItems = const [],
  });

  bool get canProceed => status == RecommendationGateStatus.ready;

  bool get hasCandidates => eligibleItems.isNotEmpty;
}
