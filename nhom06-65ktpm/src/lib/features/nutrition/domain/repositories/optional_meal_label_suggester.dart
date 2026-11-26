import '../entities/meal_photo_policy.dart';

/// Điểm mở rộng tùy chọn cho AI đề xuất nhãn món ăn (chỉ gọi qua server có đồng ý riêng ở giai đoạn mở rộng).
/// Tuyệt đối không nhúng AI API key vào ứng dụng Flutter và không được suy ra calo hay an toàn dị nguyên từ ảnh.
abstract interface class OptionalMealLabelSuggester {
  Future<List<String>> suggestMealLabelsFromPhoto({
    required String ownerUid,
    required PreparedMealPhoto photo,
  });
}
