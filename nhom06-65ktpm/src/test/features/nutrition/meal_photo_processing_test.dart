import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/nutrition/data/repositories/in_memory_meal_log_repository.dart';
import 'package:healthylife/features/nutrition/data/repositories/mock_meal_photo_services.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_attachment.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_policy.dart';
import 'package:healthylife/features/nutrition/domain/services/meal_photo_processor.dart';
import 'package:healthylife/features/nutrition/domain/services/meal_photo_validator.dart';
import 'package:healthylife/features/nutrition/domain/usecases/meal_nutrition_usecase.dart';
import 'package:healthylife/features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'package:healthylife/features/recommendations/domain/usecases/get_recommendations_usecase.dart';

/// Tạo ảnh PNG tối giản hợp lệ có tùy chọn chèn chunk `eXIf` / `tEXt`.
Uint8List _buildMinimalPng({bool includeExifChunk = false}) {
  final builder = BytesBuilder(copy: false);
  // PNG 8-byte signature
  builder.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  void addChunk(String type, List<int> data) {
    final len = data.length;
    builder.add([
      (len >> 24) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
    ]);
    builder.add(ascii.encode(type));
    builder.add(data);
    builder.add(const [0x00, 0x00, 0x00, 0x00]); // dummy CRC for structure test
  }

  addChunk('IHDR', List<int>.filled(13, 0));
  if (includeExifChunk) {
    addChunk('eXIf', ascii.encode('GPS:21.0285,105.8542'));
    addChunk('tEXt', ascii.encode('Location\x00Hanoi'));
  }
  addChunk('IDAT', const [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]);
  addChunk('IEND', const []);
  return builder.toBytes();
}

/// Tạo ảnh WebP tối giản hợp lệ có tùy chọn chèn chunk `EXIF`.
Uint8List _buildMinimalWebp({bool includeExifChunk = false}) {
  final body = BytesBuilder(copy: false);
  body.add(ascii.encode('WEBP'));

  void addChunk(String fourCc, List<int> data) {
    final len = data.length;
    body.add(ascii.encode(fourCc));
    body.add([len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF, (len >> 24) & 0xFF]);
    body.add(data);
    if (len.isOdd) body.add([0x00]);
  }

  addChunk('VP8X', [includeExifChunk ? 0x08 : 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  addChunk('VP8 ', const [0x01, 0x02, 0x03, 0x04]);
  if (includeExifChunk) {
    addChunk('EXIF', ascii.encode('Exif\x00\x00GPS21.0285'));
  }

  final bodyBytes = body.toBytes();
  final riffSize = bodyBytes.length;
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('RIFF'))
    ..add([
      riffSize & 0xFF,
      (riffSize >> 8) & 0xFF,
      (riffSize >> 16) & 0xFF,
      (riffSize >> 24) & 0xFF,
    ])
    ..add(bodyBytes);
  return out.toBytes();
}

class _FakeShrinkCompressor implements MealPhotoCompressor {
  int attempts = 0;
  final bool reInjectExif;
  final bool failToShrink;

  _FakeShrinkCompressor({
    this.reInjectExif = false,
    this.failToShrink = false,
  });

  @override
  Future<Uint8List> compress({
    required Uint8List bytes,
    required String mimeType,
    required int maxBytes,
    required int quality,
  }) async {
    attempts++;
    if (failToShrink) {
      return bytes;
    }
    return MockMealPhotoPicker.buildMinimalValidJpeg(
      app1ExifPayload: reInjectExif
          ? [...ascii.encode('Exif\x00\x00'), ...ascii.encode('GPS_LEAK')]
          : null,
    );
  }
}

void main() {
  const validator = MealPhotoValidator();
  const processor = DefaultMealPhotoProcessor();

  group('Validate loại và kích thước ảnh ở client (Issue #11 - Tiêu chí 2)', () {
    test('từ chối ảnh rỗng, tệp giả mạo đuôi .jpg, lệch MIME và JPEG cắt cụt', () async {
      final emptyPhoto = SelectedMealPhoto(
        source: MealPhotoSource.gallery,
        fileName: 'empty.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List(0),
      );
      final fakeSvgAsJpg = SelectedMealPhoto(
        source: MealPhotoSource.gallery,
        fileName: 'meal.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList(utf8.encode('<svg><script>alert(1)</script></svg>')),
      );
      final mimeMismatch = SelectedMealPhoto(
        source: MealPhotoSource.gallery,
        fileName: 'dish.png',
        mimeType: 'image/jpeg',
        bytes: _buildMinimalPng(),
      );
      final truncatedJpeg = SelectedMealPhoto(
        source: MealPhotoSource.camera,
        fileName: 'broken.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x20, 0x01]),
      );

      await expectLater(
        processor.prepare(emptyPhoto),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.emptyFile,
          ),
        ),
      );
      await expectLater(
        processor.prepare(fakeSvgAsJpg),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.unsupportedFormat,
          ),
        ),
      );
      await expectLater(
        processor.prepare(mimeMismatch),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.mimeMismatch,
          ),
        ),
      );
      await expectLater(
        processor.prepare(truncatedJpeg),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.corruptedImage,
          ),
        ),
      );
    });

    test('từ chối ảnh gốc vượt quá giới hạn maxRawBytes ở client', () async {
      const strictProcessor = DefaultMealPhotoProcessor(
        validator: MealPhotoValidator(
          policy: MealPhotoPolicy(maxRawBytes: 64, maxUploadBytes: 32),
        ),
      );
      final rawBytes = MockMealPhotoPicker.buildMinimalValidJpeg(
        app1ExifPayload: List<int>.filled(80, 0x41),
      );
      final photo = SelectedMealPhoto(
        source: MealPhotoSource.camera,
        fileName: 'huge.jpg',
        mimeType: 'image/jpeg',
        bytes: rawBytes,
      );

      await expectLater(
        strictProcessor.prepare(photo),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.rawFileTooLarge,
          ),
        ),
      );
    });
  });

  group('Bỏ EXIF/GPS và nén ảnh trước khi upload (Issue #11 - Tiêu chí 2)', () {
    test('loại bỏ sạch APP1 EXIF/GPS trên JPEG, eXIf/tEXt trên PNG và EXIF trên WebP', () async {
      final jpegWithExif = MockMealPhotoPicker.buildMinimalValidJpeg(
        app1ExifPayload: [
          ...ascii.encode('Exif\x00\x00'),
          ...ascii.encode('GPSLatitude=21.0285,GPSLongitude=105.8542'),
        ],
      );
      expect(
        validator.containsExifOrSensitiveMetadata(jpegWithExif),
        isTrue,
      );

      final preparedJpeg = await processor.prepare(
        SelectedMealPhoto(
          source: MealPhotoSource.camera,
          fileName: 'pho_ga.jpg',
          mimeType: 'image/jpeg',
          bytes: jpegWithExif,
        ),
      );
      expect(preparedJpeg.exifStripped, isTrue);
      expect(
        validator.containsExifOrSensitiveMetadata(preparedJpeg.bytes),
        isFalse,
      );
      expect(
        utf8.decode(preparedJpeg.bytes, allowMalformed: true),
        isNot(contains('21.0285')),
      );
      expect(preparedJpeg.sizeBytes, lessThan(jpegWithExif.length));

      final pngWithExif = _buildMinimalPng(includeExifChunk: true);
      expect(validator.containsExifOrSensitiveMetadata(pngWithExif), isTrue);
      final preparedPng = await processor.prepare(
        SelectedMealPhoto(
          source: MealPhotoSource.gallery,
          fileName: 'salad.png',
          mimeType: 'image/png',
          bytes: pngWithExif,
        ),
      );
      expect(
        validator.containsExifOrSensitiveMetadata(preparedPng.bytes),
        isFalse,
      );

      final webpWithExif = _buildMinimalWebp(includeExifChunk: true);
      expect(validator.containsExifOrSensitiveMetadata(webpWithExif), isTrue);
      final preparedWebp = await processor.prepare(
        SelectedMealPhoto(
          source: MealPhotoSource.gallery,
          fileName: 'soup.webp',
          mimeType: 'image/webp',
          bytes: webpWithExif,
        ),
      );
      expect(
        validator.containsExifOrSensitiveMetadata(preparedWebp.bytes),
        isFalse,
      );
    });

    test('nén ảnh vượt maxUploadBytes và xóa lại EXIF nếu bộ nén chèn lại metadata', () async {
      final compressor = _FakeShrinkCompressor(reInjectExif: true);
      final customProcessor = DefaultMealPhotoProcessor(
        validator: const MealPhotoValidator(
          policy: MealPhotoPolicy(maxRawBytes: 5000, maxUploadBytes: 120),
        ),
        compressor: compressor,
      );

      // Tạo JPEG > 120 bytes bằng đoạn dữ liệu scan lớn hơn (không phải EXIF)
      final oversizedJpeg = Uint8List.fromList([
        0xFF, 0xD8,
        0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
        ...List<int>.filled(300, 0x2A),
        0xFF, 0xD9,
      ]);

      final prepared = await customProcessor.prepare(
        SelectedMealPhoto(
          source: MealPhotoSource.camera,
          fileName: 'large_meal.jpg',
          mimeType: 'image/jpeg',
          bytes: oversizedJpeg,
        ),
      );

      expect(compressor.attempts, greaterThanOrEqualTo(1));
      expect(prepared.compressed, isTrue);
      expect(prepared.sizeBytes, lessThanOrEqualTo(120));
      expect(validator.containsExifOrSensitiveMetadata(prepared.bytes), isFalse);
    });

    test('từ chối nếu sau khi nén ảnh vẫn vượt giới hạn maxUploadBytes', () async {
      final compressor = _FakeShrinkCompressor(failToShrink: true);
      final customProcessor = DefaultMealPhotoProcessor(
        validator: const MealPhotoValidator(
          policy: MealPhotoPolicy(maxRawBytes: 5000, maxUploadBytes: 80),
        ),
        compressor: compressor,
      );

      final oversizedJpeg = Uint8List.fromList([
        0xFF, 0xD8,
        0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
        ...List<int>.filled(200, 0x2A),
        0xFF, 0xD9,
      ]);

      await expectLater(
        customProcessor.prepare(
          SelectedMealPhoto(
            source: MealPhotoSource.camera,
            fileName: 'too_big.jpg',
            mimeType: 'image/jpeg',
            bytes: oversizedJpeg,
          ),
        ),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.compressedFileTooLarge,
          ),
        ),
      );
    });
  });

  group('Validate phía dịch vụ Storage (defense-in-depth) (Issue #11 - Tiêu chí 2)', () {
    test('dịch vụ Storage từ chối ảnh còn EXIF, vượt dung lượng hoặc sai định dạng khi gọi trực tiếp', () async {
      final storage = InMemoryPrivateMealPhotoStorage(
        validator: const MealPhotoValidator(
          policy: MealPhotoPolicy(maxUploadBytes: 120),
        ),
      );

      final unstrippedJpeg = MockMealPhotoPicker.buildMinimalValidJpeg(
        app1ExifPayload: ascii.encode('Exif\x00\x00GPS'),
      );
      await expectLater(
        storage.uploadPrivatePhoto(
          ownerUid: 'uid-dai',
          logId: 'log-1',
          photo: PreparedMealPhoto(
            source: MealPhotoSource.camera,
            fileName: 'raw.jpg',
            mimeType: 'image/jpeg',
            extension: 'jpg',
            bytes: unstrippedJpeg,
            originalSizeBytes: unstrippedJpeg.length,
            compressed: false,
            exifStripped: false,
          ),
        ),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.exifNotRemoved,
          ),
        ),
      );

      final oversizedClean = Uint8List.fromList([
        0xFF, 0xD8,
        0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
        ...List<int>.filled(200, 0x11),
        0xFF, 0xD9,
      ]);
      await expectLater(
        storage.uploadPrivatePhoto(
          ownerUid: 'uid-dai',
          logId: 'log-2',
          photo: PreparedMealPhoto(
            source: MealPhotoSource.camera,
            fileName: 'big.jpg',
            mimeType: 'image/jpeg',
            extension: 'jpg',
            bytes: oversizedClean,
            originalSizeBytes: oversizedClean.length,
            compressed: true,
            exifStripped: true,
          ),
        ),
        throwsA(
          isA<MealPhotoException>().having(
            (e) => e.code,
            'code',
            MealPhotoFailureCode.compressedFileTooLarge,
          ),
        ),
      );
    });

    test('MealNutritionUseCase tự động xóa EXIF trước khi lưu vào Storage riêng tư', () async {
      final storage = InMemoryPrivateMealPhotoStorage();
      final useCase = MealNutritionUseCase(
        recommendationsUseCase: const GetRecommendationsUseCase(
          repository: FixtureCatalogRepository(),
        ),
        mealLogRepository: InMemoryMealLogRepository(),
        photoPicker: MockMealPhotoPicker(),
        photoStorage: storage,
      );

      final jpegWithGps = MockMealPhotoPicker.buildMinimalValidJpeg(
        app1ExifPayload: [
          ...ascii.encode('Exif\x00\x00'),
          ...ascii.encode('GPS=21.0285,105.8542'),
        ],
      );

      final savedLog = await useCase.confirmAndLogMeal(
        ownerUid: 'uid-dai',
        confirmedMealName: 'Cơm gạo lứt ức gà',
        selectedPhoto: SelectedMealPhoto(
          source: MealPhotoSource.camera,
          fileName: 'lunch_gps.jpg',
          mimeType: 'image/jpeg',
          bytes: jpegWithGps,
        ),
      );

      expect(savedLog.hasPhoto, isTrue);
      final storedBytes = storage.objects[savedLog.imagePath!]!;
      expect(validator.containsExifOrSensitiveMetadata(storedBytes), isFalse);
      expect(
        utf8.decode(storedBytes, allowMalformed: true),
        isNot(contains('21.0285')),
      );
    });
  });
}
