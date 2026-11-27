import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/meal_photo_access_error.dart';
import '../../domain/entities/meal_photo_attachment.dart';
import '../../domain/entities/meal_photo_policy.dart';
import '../../domain/repositories/meal_photo_picker.dart';

class ImagePickerMealPhotoPicker implements MealPhotoPicker {
  ImagePickerMealPhotoPicker({
    ImagePicker? picker,
    this.policy = const MealPhotoPolicy(),
  }) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final MealPhotoPolicy policy;

  @override
  Future<SelectedMealPhoto?> pickPhoto(MealPhotoSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == MealPhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      if (await file.length() > policy.maxRawBytes) {
        throw const MealPhotoException(
          MealPhotoFailureCode.rawFileTooLarge,
          'Ảnh gốc vượt giới hạn 10 MiB.',
        );
      }
      return SelectedMealPhoto(
        source: source,
        fileName: file.name,
        mimeType: file.mimeType,
        bytes: await file.readAsBytes(),
      );
    } on PlatformException catch (error) {
      final code = switch (error.code) {
        'camera_access_denied' =>
          MealPhotoAccessFailureCode.cameraPermissionDenied,
        'camera_access_restricted' =>
          MealPhotoAccessFailureCode.cameraPermissionPermanentlyDenied,
        'photo_access_denied' || 'photo_access_restricted' =>
          MealPhotoAccessFailureCode.galleryPermissionDenied,
        'no_available_camera' ||
        'camera_unavailable' => MealPhotoAccessFailureCode.deviceUnavailable,
        _ => MealPhotoAccessFailureCode.captureFailed,
      };
      throw MealPhotoAccessException(code, 'Không thể lấy ảnh trên thiết bị.');
    } on UnsupportedError {
      throw const MealPhotoAccessException(
        MealPhotoAccessFailureCode.deviceUnavailable,
        'Thiết bị không hỗ trợ nguồn ảnh này.',
      );
    }
  }
}
