import 'dart:async';
import 'dart:io';

import '../../../../core/utils/id_generator.dart';
import '../../../recommendations/domain/entities/meal_catalog_item.dart';
import '../../../recommendations/domain/entities/recommendation_profile.dart';
import '../../../recommendations/domain/usecases/get_recommendations_usecase.dart';
import '../entities/meal_label_suggestion.dart';
import '../entities/meal_log.dart';
import '../entities/meal_photo_access_error.dart';
import '../entities/meal_photo_attachment.dart';
import '../entities/meal_photo_policy.dart';
import '../entities/meal_suggestion_session.dart';
import '../repositories/meal_log_repository.dart';
import '../repositories/meal_photo_picker.dart';
import '../repositories/meal_photo_storage.dart';
import '../repositories/optional_meal_label_suggester.dart';
import '../repositories/pending_meal_photo_store.dart';
import '../services/meal_photo_processor.dart';

/// Use case điều phối luồng cốt lõi của nhật ký bữa ăn:
/// 1. Gợi ý & đổi món theo hồ sơ thông qua [GetRecommendationsUseCase] (Issue #10).
/// 2. Chụp/chọn ảnh bữa ăn qua [MealPhotoPicker], kiểm tra/nén/xóa EXIF qua [MealPhotoProcessor].
/// 3. Xử lý từ chối quyền, ảnh lỗi và mất mạng với fallback nhập tay & hàng đợi ảnh chờ,
///    bảo đảm không mất nhật ký bữa ăn.
class MealNutritionUseCase {
  final GetRecommendationsUseCase recommendationsUseCase;
  final MealLogRepository mealLogRepository;
  final MealPhotoPicker photoPicker;
  final MealPhotoStorage photoStorage;
  final MealPhotoProcessor photoProcessor;
  final PendingMealPhotoStore? pendingPhotoStore;
  final OptionalMealLabelSuggester? optionalLabelSuggester;
  final Duration labelSuggestionTimeout;

  static const List<String> _forbiddenPhotoInferenceKeywords = [
    'kcal',
    'calo',
    'calorie',
    'dị nguyên',
    'di nguyen',
    'dị ứng',
    'di ung',
    'allergen',
    'allergy',
    'không gây dị ứng',
    'an toàn tuyệt đối',
  ];

  const MealNutritionUseCase({
    required this.recommendationsUseCase,
    required this.mealLogRepository,
    required this.photoPicker,
    required this.photoStorage,
    this.photoProcessor = const DefaultMealPhotoProcessor(),
    this.pendingPhotoStore,
    this.optionalLabelSuggester,
    this.labelSuggestionTimeout = const Duration(seconds: 5),
  });

  /// Lấy danh sách món gợi ý và lựa chọn thay thế hợp lệ theo hồ sơ người dùng.
  Future<MealSuggestionSession> loadSuggestions({
    required RecommendationProfile profile,
    String? mealType,
    List<String> recentSlugs = const [],
    int maxResults = 3,
  }) async {
    final result = await recommendationsUseCase.getMealRecommendations(
      profile: profile,
      mealType: mealType,
      recentSlugs: recentSlugs,
      maxResults: maxResults,
    );
    return MealSuggestionSession(mealType: mealType, result: result);
  }

  /// Đổi sang món thay thế tiếp theo trong danh sách đã lọc an toàn.
  MealSuggestionSession swapSuggestion(MealSuggestionSession session) {
    return session.swapToNext();
  }

  /// Chọn trực tiếp một món thay thế trong phiên gợi ý hiện tại.
  MealSuggestionSession selectSuggestionBySlug(
    MealSuggestionSession session,
    String slug,
  ) {
    return session.selectBySlug(slug);
  }

  /// Chụp ảnh từ camera hoặc chọn ảnh từ thư viện thiết bị.
  Future<SelectedMealPhoto?> captureOrPickPhoto(MealPhotoSource source) {
    return photoPicker.pickPhoto(source);
  }

  /// Kiểm tra định dạng/kích thước ở client, nén ảnh và xóa sạch EXIF/vị trí trước upload.
  Future<PreparedMealPhoto> preparePhoto(SelectedMealPhoto photo) {
    return photoProcessor.prepare(photo);
  }

  /// Luồng chọn/chụp và tiền xử lý ảnh an toàn: khi bị từ chối quyền, không có camera
  /// hoặc ảnh lỗi sẽ trả [MealPhotoPickOutcome] hướng dẫn nhập tay thay vì văng lỗi làm mất form.
  Future<MealPhotoPickOutcome> pickAndPreparePhoto(MealPhotoSource source) async {
    try {
      final selected = await captureOrPickPhoto(source);
      if (selected == null) {
        return const MealPhotoPickOutcome(cancelled: true);
      }
      final prepared = await preparePhoto(selected);
      return MealPhotoPickOutcome(preparedPhoto: prepared);
    } on MealPhotoAccessException catch (error) {
      return MealPhotoPickOutcome(
        manualFallbackRequired: true,
        accessError: error.code,
        userMessage: _friendlyAccessFallbackMessage(error),
      );
    } on MealPhotoException catch (error) {
      return MealPhotoPickOutcome(
        manualFallbackRequired: true,
        photoError: error.code,
        userMessage:
            '${error.message} Bạn vẫn có thể tiếp tục nhập tay tên món để không mất nhật ký.',
      );
    } catch (_) {
      return const MealPhotoPickOutcome(
        manualFallbackRequired: true,
        accessError: MealPhotoAccessFailureCode.captureFailed,
        userMessage:
            'Không thể đọc ảnh từ thiết bị. Bạn vẫn có thể nhập tay tên món để lưu nhật ký.',
      );
    }
  }

  /// Lưu nhật ký bữa ăn có khả năng chịu lỗi mạng:
  /// - Nếu upload ảnh gặp lỗi mất mạng/timeout -> giữ ảnh sạch EXIF trong [PendingMealPhotoStore]
  ///   và VẪN lưu nhật ký cục bộ với trạng thái `pendingLocal` (không báo đã upload cloud thành công).
  /// - Nếu ảnh không hợp lệ (sai định dạng/vượt dung lượng/còn EXIF) -> ném [MealPhotoException].
  Future<MealLogSaveResult> saveMealLogResilient({
    required String ownerUid,
    required String confirmedMealName,
    String mealType = 'lunch',
    MealCatalogItem? selectedCatalogMeal,
    SelectedMealPhoto? selectedPhoto,
    PreparedMealPhoto? preparedPhoto,
    DateTime? consumedAt,
    String? note,
  }) async {
    final trimmedOwner = ownerUid.trim();
    if (trimmedOwner.isEmpty) {
      throw ArgumentError.value(
        ownerUid,
        'ownerUid',
        'Thiếu định danh chủ tài khoản.',
      );
    }

    final trimmedMealName = confirmedMealName.trim();
    if (trimmedMealName.isEmpty) {
      throw ArgumentError.value(
        confirmedMealName,
        'confirmedMealName',
        'Người dùng cần nhập hoặc xác nhận tên món ăn trước khi lưu.',
      );
    }

    final now = DateTime.now().toUtc();
    final logId = IdGenerator.generateUuid();
    final photoToUpload = preparedPhoto ??
        (selectedPhoto == null ? null : await preparePhoto(selectedPhoto));

    StoredMealPhoto? storedPhoto;
    var savedOfflinePhoto = false;
    MealPhotoUploadStatus uploadStatus = MealPhotoUploadStatus.none;

    if (photoToUpload != null) {
      try {
        storedPhoto = await photoStorage.uploadPrivatePhoto(
          ownerUid: trimmedOwner,
          logId: logId,
          photo: photoToUpload,
        );
        uploadStatus = storedPhoto.uploadStatus;
      } on MealPhotoException {
        rethrow;
      } on SocketException {
        savedOfflinePhoto = true;
      } on TimeoutException {
        savedOfflinePhoto = true;
      } on MealPhotoAccessException catch (error) {
        if (error.code == MealPhotoAccessFailureCode.networkOffline) {
          savedOfflinePhoto = true;
        } else {
          rethrow;
        }
      }

      if (savedOfflinePhoto) {
        uploadStatus = MealPhotoUploadStatus.pendingLocal;
        await pendingPhotoStore?.savePendingPhoto(
          ownerUid: trimmedOwner,
          logId: logId,
          photo: photoToUpload,
        );
      }
    }

    final normalizedNote = note?.trim();
    final log = MealLog(
      id: logId,
      ownerUid: trimmedOwner,
      mealId: selectedCatalogMeal?.id,
      catalogSlug: selectedCatalogMeal?.slug,
      mealName: trimmedMealName,
      userConfirmedName: true,
      mealType: mealType,
      consumedAt: (consumedAt ?? now).toUtc(),
      imagePath: storedPhoto?.storagePath,
      photoSource: storedPhoto?.source ?? photoToUpload?.source,
      photoUploadStatus: uploadStatus,
      note: (normalizedNote == null || normalizedNote.isEmpty)
          ? null
          : normalizedNote,
      createdAt: now,
      updatedAt: now,
      version: 1,
    );

    final saved = await mealLogRepository.saveMealLog(log);
    final message = savedOfflinePhoto
        ? 'Mất kết nối mạng khi tải ảnh. Nhật ký "$trimmedMealName" đã được lưu cục bộ và ảnh sẽ đồng bộ khi có mạng.'
        : (saved.hasPhoto
              ? 'Đã lưu nhật ký bữa ăn "$trimmedMealName" kèm ảnh riêng tư.'
              : 'Đã lưu nhật ký bữa ăn "$trimmedMealName" (nhập tay).');

    return MealLogSaveResult(
      log: saved,
      savedOfflineWithoutCloudPhoto: savedOfflinePhoto,
      userMessage: message,
    );
  }

  /// Ghi nhật ký bữa ăn với tên món do người dùng xác nhận và ảnh đã xử lý an toàn (nếu có).
  Future<MealLog> confirmAndLogMeal({
    required String ownerUid,
    required String confirmedMealName,
    String mealType = 'lunch',
    MealCatalogItem? selectedCatalogMeal,
    SelectedMealPhoto? selectedPhoto,
    PreparedMealPhoto? preparedPhoto,
    DateTime? consumedAt,
    String? note,
  }) async {
    final result = await saveMealLogResilient(
      ownerUid: ownerUid,
      confirmedMealName: confirmedMealName,
      mealType: mealType,
      selectedCatalogMeal: selectedCatalogMeal,
      selectedPhoto: selectedPhoto,
      preparedPhoto: preparedPhoto,
      consumedAt: consumedAt,
      note: note,
    );
    return result.log;
  }

  /// Thử tải lên lại các ảnh đang chờ của đúng `ownerUid` khi có mạng,
  /// cập nhật `imagePath` vào đúng bản ghi nhật ký cũ (không tạo bản ghi trùng).
  Future<int> retryPendingPhotoUploads({required String ownerUid}) async {
    final store = pendingPhotoStore;
    if (store == null) return 0;

    final pendingList = await store.getPendingPhotos(ownerUid: ownerUid);
    if (pendingList.isEmpty) return 0;

    final existingLogs = await mealLogRepository.getMealLogs(ownerUid: ownerUid);
    final logsById = {for (final log in existingLogs) log.id: log};
    var uploadedCount = 0;

    for (final pending in pendingList) {
      if (pending.ownerUid != ownerUid) continue;
      final existingLog = logsById[pending.logId];
      if (existingLog == null) {
        await store.removePendingPhoto(
          ownerUid: ownerUid,
          logId: pending.logId,
        );
        continue;
      }

      try {
        final stored = await photoStorage.uploadPrivatePhoto(
          ownerUid: ownerUid,
          logId: pending.logId,
          photo: pending.photo,
        );
        final updatedLog = existingLog.copyWith(
          imagePath: stored.storagePath,
          photoSource: stored.source,
          photoUploadStatus: MealPhotoUploadStatus.uploaded,
          updatedAt: DateTime.now().toUtc(),
        );
        await mealLogRepository.saveMealLog(updatedLog);
        await store.removePendingPhoto(
          ownerUid: ownerUid,
          logId: pending.logId,
        );
        uploadedCount++;
      } on SocketException {
        break;
      } on TimeoutException {
        break;
      } on MealPhotoAccessException catch (error) {
        if (error.code == MealPhotoAccessFailureCode.networkOffline) {
          break;
        }
      }
    }

    return uploadedCount;
  }

  Future<int> countPendingPhotos({required String ownerUid}) async {
    final store = pendingPhotoStore;
    if (store == null) return 0;
    final list = await store.getPendingPhotos(ownerUid: ownerUid);
    return list.length;
  }

  /// Gọi phần mở rộng AI đề xuất nhãn món (nếu bật và có đồng ý riêng).
  /// Không bao giờ suy ra calo hoặc khẳng định an toàn dị nguyên từ ảnh; mọi lỗi đều fallback
  /// về nhập tay để không chặn luồng ghi nhật ký cốt lõi.
  Future<MealLabelSuggestionResult> requestOptionalPhotoLabelSuggestions({
    required String ownerUid,
    required PreparedMealPhoto photo,
    required bool aiConsentGranted,
  }) async {
    final suggester = optionalLabelSuggester;
    if (suggester == null) {
      return const MealLabelSuggestionResult(
        status: MealLabelSuggestionStatus.disabled,
        userNotice: MealLabelSuggestionResult.photoSafetyDisclaimer,
      );
    }

    if (!aiConsentGranted) {
      return const MealLabelSuggestionResult(
        status: MealLabelSuggestionStatus.consentRequired,
        userNotice:
            'Tính năng gợi ý nhãn món bằng AI chỉ bật khi có đồng ý riêng. Bạn hãy tự xác nhận tên món ăn.',
      );
    }

    try {
      final rawLabels = await suggester
          .suggestMealLabelsFromPhoto(ownerUid: ownerUid, photo: photo)
          .timeout(labelSuggestionTimeout);
      final safeLabels = rawLabels
          .map((label) => label.trim())
          .where((label) => label.isNotEmpty && !_containsUnsafePhotoInference(label))
          .toSet()
          .toList();

      if (safeLabels.isEmpty) {
        return const MealLabelSuggestionResult(
          status: MealLabelSuggestionStatus.fallbackToManual,
          userNotice:
              'Không có nhãn món phù hợp từ phần mở rộng AI. Vui lòng tự nhập và xác nhận tên món.',
        );
      }

      return MealLabelSuggestionResult(
        status: MealLabelSuggestionStatus.suggestedForConfirmation,
        candidateLabels: List<String>.unmodifiable(safeLabels),
        userNotice:
            'Nhãn tham khảo từ AI mở rộng — không suy ra calo hay an toàn dị nguyên. Vui lòng tự kiểm tra và xác nhận tên món.',
      );
    } catch (_) {
      return const MealLabelSuggestionResult(
        status: MealLabelSuggestionStatus.fallbackToManual,
        userNotice:
            'Phần mở rộng AI tạm không khả dụng. Luồng cốt lõi vẫn hoạt động bình thường, vui lòng tự xác nhận tên món.',
      );
    }
  }

  static bool _containsUnsafePhotoInference(String label) {
    final normalized = label.trim().toLowerCase();
    for (final keyword in _forbiddenPhotoInferenceKeywords) {
      if (normalized.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  Future<List<MealLog>> getMealHistory({required String ownerUid}) {
    return mealLogRepository.getMealLogs(ownerUid: ownerUid);
  }

  static String _friendlyAccessFallbackMessage(MealPhotoAccessException error) {
    return switch (error.code) {
      MealPhotoAccessFailureCode.cameraPermissionDenied =>
        'Quyền Camera bị từ chối. Bạn vẫn có thể nhập tay tên món hoặc chọn ảnh từ thư viện.',
      MealPhotoAccessFailureCode.cameraPermissionPermanentlyDenied =>
        'Quyền Camera đang bị tắt trong cài đặt thiết bị. Bạn vẫn có thể tiếp tục nhập tay nhật ký bữa ăn.',
      MealPhotoAccessFailureCode.galleryPermissionDenied =>
        'Quyền Thư viện ảnh bị từ chối. Bạn vẫn có thể nhập tay tên món để lưu nhật ký.',
      MealPhotoAccessFailureCode.deviceUnavailable =>
        'Thiết bị không hỗ trợ hoặc không có camera. Hãy tiếp tục ghi nhật ký bằng cách nhập tay.',
      MealPhotoAccessFailureCode.captureFailed =>
        'Chụp/chọn ảnh gặp lỗi. Bạn vẫn có thể nhập tay tên món để không mất nhật ký.',
      MealPhotoAccessFailureCode.networkOffline =>
        'Thiết bị đang ngoại tuyến. Nhật ký sẽ được lưu cục bộ và đồng bộ khi có mạng.',
    };
  }
}
