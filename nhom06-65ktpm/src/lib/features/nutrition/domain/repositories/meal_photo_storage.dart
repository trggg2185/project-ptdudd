import '../entities/meal_photo_attachment.dart';

/// Interface lưu trữ ảnh bữa ăn trong bucket riêng tư `meal-images`
/// với đường dẫn bắt buộc `<owner_uid>/<file-name>` để khớp RLS Storage.
abstract interface class MealPhotoStorage {
  static const String privateBucketName = 'meal-images';

  Future<StoredMealPhoto> uploadPrivatePhoto({
    required String ownerUid,
    required String logId,
    required SelectedMealPhoto photo,
  });

  Future<String?> createShortLivedSignedUrl({
    required String ownerUid,
    required String storagePath,
    Duration expiresIn = const Duration(minutes: 10),
  });

  Future<void> deletePrivatePhoto({
    required String ownerUid,
    required String storagePath,
  });
}
