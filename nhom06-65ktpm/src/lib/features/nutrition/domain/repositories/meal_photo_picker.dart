import '../entities/meal_photo_attachment.dart';

/// Interface chụp ảnh bữa ăn từ camera hoặc chọn ảnh từ thư viện thiết bị.
abstract interface class MealPhotoPicker {
  /// Trả về `null` nếu người dùng hủy thao tác chọn/chụp ảnh.
  Future<SelectedMealPhoto?> pickPhoto(MealPhotoSource source);
}
