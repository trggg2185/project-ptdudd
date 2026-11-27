import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

import '../../domain/entities/meal_photo_policy.dart';
import '../../domain/services/meal_photo_processor.dart';

class JpegMealPhotoCompressor implements MealPhotoCompressor {
  const JpegMealPhotoCompressor();

  @override
  Future<Uint8List> compress({
    required Uint8List bytes,
    required String mimeType,
    required int maxBytes,
    required int quality,
  }) => compute(_compress, (bytes: bytes, quality: quality));

  static Uint8List _compress(({Uint8List bytes, int quality}) request) {
    final decoder = image.findDecoderForData(request.bytes);
    final info = decoder?.startDecode(request.bytes);
    // Bound decoded memory as well as the size of the selected file.
    if (info == null || info.width * info.height > 32000000) {
      throw const MealPhotoException(
        MealPhotoFailureCode.corruptedImage,
        'Không thể xử lý độ phân giải của ảnh. Hãy chọn ảnh nhỏ hơn.',
      );
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) {
      throw const MealPhotoException(
        MealPhotoFailureCode.corruptedImage,
        'Không thể đọc nội dung ảnh.',
      );
    }
    var photo = image.bakeOrientation(decoded);
    final maxEdge = request.quality >= 85 ? 1600 : (request.quality * 16);
    if (math.max(photo.width, photo.height) > maxEdge) {
      photo = photo.width >= photo.height
          ? image.copyResize(photo, width: maxEdge)
          : image.copyResize(photo, height: maxEdge);
    }
    return image.encodeJpg(photo, quality: request.quality);
  }
}
