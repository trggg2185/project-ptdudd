import '../entities/exercise_catalog_item.dart';
import '../entities/hard_filter_result.dart';
import '../entities/meal_catalog_item.dart';
import '../entities/recommendation_profile.dart';

/// Dịch vụ kiểm tra đầu vào bắt buộc và lọc cứng ứng viên trước khi xếp hạng.
///
/// Nguyên tắc bất biến:
/// 1. Kiểm tra đủ 18 tuổi, không cần tư vấn chuyên môn, không nhận mục tiêu điều trị/giảm cân nhanh,
///    và đủ dữ liệu đầu vào bắt buộc.
/// 2. Chưa xác nhận dị ứng thì chưa bật gợi ý món ăn.
/// 3. Món ăn không rõ thành phần nguyên liệu không được coi là an toàn.
/// 4. Lọc cứng dị nguyên, nguyên liệu cần tránh, giới hạn vận động, thiết bị, thời lượng, ngân sách.
/// 5. Nếu không còn ứng viên hợp lệ thì trả rỗng, tuyệt đối không nới lỏng ràng buộc.
class CatalogHardFilter {
  static const int _maxReasonableSessionMinutes = 240;
  static const int _maxReasonableSessionsPerWeek = 14;

  static const List<String> _forbiddenSafetyKeywords = [
    'giảm cân nhanh',
    'giam can nhanh',
    'giam_can_nhanh',
    'rapid_weight_loss',
    'rapid weight loss',
    'thâm hụt calo',
    'tham hut calo',
    'calorie_deficit',
    'điều trị',
    'dieu tri',
    'dieu_tri',
    'medical_treatment',
    'chữa bệnh',
    'chua benh',
    'chua_benh',
    'clinical_diet',
  ];

  static const Map<String, int> _experienceRank = {
    'beginner': 1,
    'intermediate': 2,
    'advanced': 3,
  };

  const CatalogHardFilter();

  /// Kiểm tra các điều kiện bắt buộc chung trước khi gợi ý môn tập hoặc món ăn.
  HardFilterResult<T>? validateBaseInput<T>(RecommendationProfile profile) {
    if (!profile.isAdultConfirmed) {
      return HardFilterResult<T>(
        status: RecommendationGateStatus.underageBlocked,
        message:
            'Cần xác nhận người dùng từ 18 tuổi trở lên trước khi sử dụng bộ gợi ý.',
        missingFields: const ['isAdultConfirmed'],
      );
    }

    if (profile.requiresProfessionalGuidance) {
      return HardFilterResult<T>(
        status: RecommendationGateStatus.professionalGuidanceRequired,
        message:
            'Tình trạng cần tư vấn chuyên môn không áp dụng kế hoạch tự động. Vui lòng dùng lịch thủ công và nhập hướng dẫn đã được chuyên gia xác nhận.',
      );
    }

    final normalizedGoal = _normalize(profile.goal ?? '');
    if (normalizedGoal.isNotEmpty && _containsForbiddenSafetyPhrase(normalizedGoal)) {
      return HardFilterResult<T>(
        status: RecommendationGateStatus.unsafeGoalBlocked,
        message:
            'HealthyLife hỗ trợ lối sống lành mạnh, không đề xuất phác đồ điều trị hoặc mục tiêu giảm cân nhanh.',
      );
    }

    final missing = <String>[];
    if (profile.timezone == null || profile.timezone!.trim().isEmpty) {
      missing.add('timezone');
    }
    if (profile.goal == null || profile.goal!.trim().isEmpty) {
      missing.add('goal');
    }
    final minutes = profile.availableMinutesPerSession;
    if (minutes == null ||
        minutes <= 0 ||
        minutes > _maxReasonableSessionMinutes) {
      missing.add('availableMinutesPerSession');
    }
    final sessions = profile.sessionsPerWeek;
    if (sessions == null ||
        sessions <= 0 ||
        sessions > _maxReasonableSessionsPerWeek) {
      missing.add('sessionsPerWeek');
    }

    if (missing.isNotEmpty) {
      return HardFilterResult<T>(
        status: RecommendationGateStatus.missingRequiredInput,
        message:
            'Thiếu thông tin bắt buộc hoặc khung thời lượng chưa hợp lý. Vui lòng bổ sung hoặc dùng lịch thủ công.',
        missingFields: List<String>.unmodifiable(missing),
      );
    }

    return null;
  }

  /// Lọc cứng danh mục bài tập theo giới hạn vận động, thiết bị, môi trường, kinh nghiệm, thời lượng và ngân sách.
  HardFilterResult<ExerciseCatalogItem> filterExercises({
    required List<ExerciseCatalogItem> catalog,
    required RecommendationProfile profile,
  }) {
    final gateFailure = validateBaseInput<ExerciseCatalogItem>(profile);
    if (gateFailure != null) {
      return gateFailure;
    }

    final userEquipment = profile.availableEquipment.map(_normalize).toSet();
    final userLimitations = profile.movementLimitations.map(_normalize).toSet();
    final dislikedCategories = profile.dislikedExerciseCategories
        .map(_normalize)
        .toSet();
    final userExperience =
        _experienceRank[_normalize(profile.experienceLevel)] ?? 1;
    final preferredEnv = _normalize(profile.preferredEnvironment);
    final maxMinutes = profile.availableMinutesPerSession!;
    final maxBudget = profile.maxExerciseBudgetVnd;

    final eligible = <ExerciseCatalogItem>[];
    final excluded = <FilteredOutCandidate<ExerciseCatalogItem>>[];

    for (final item in catalog) {
      final reasons = <String>[];

      if (!item.hasVerifiedSource) {
        reasons.add('Bài tập chưa được kiểm duyệt hoặc thiếu nguồn tham khảo.');
      }

      if (_containsForbiddenSafetyPhrase('${item.name} ${item.description}')) {
        reasons.add('Nội dung nằm ngoài phạm vi lối sống lành mạnh.');
      }

      if (item.durationMinutes <= 0) {
        reasons.add('Thời lượng bài tập không hợp lệ.');
      } else if (item.durationMinutes > maxMinutes) {
        reasons.add(
          'Thời lượng ${item.durationMinutes} phút vượt quá thời gian rảnh $maxMinutes phút.',
        );
      }

      final itemLimitations = item.contraindicatedLimitations
          .map(_normalize)
          .where(userLimitations.contains)
          .toList();
      if (itemLimitations.isNotEmpty) {
        reasons.add(
          'Vi phạm giới hạn vận động tự khai báo: ${itemLimitations.join(', ')}.',
        );
      }

      final missingEquipment = item.equipmentNeeded
          .map(_normalize)
          .where((eq) => eq.isNotEmpty && !userEquipment.contains(eq))
          .toList();
      if (missingEquipment.isNotEmpty) {
        reasons.add('Thiếu thiết bị cần thiết: ${missingEquipment.join(', ')}.');
      }

      final itemEnv = _normalize(item.environment);
      if (preferredEnv == 'indoor' && itemEnv == 'outdoor') {
        reasons.add('Bài tập ngoài trời không khớp ưu tiên tập trong nhà.');
      } else if (preferredEnv == 'outdoor' && itemEnv == 'indoor') {
        reasons.add('Bài tập trong nhà không khớp ưu tiên tập ngoài trời.');
      }

      final itemExperience =
          _experienceRank[_normalize(item.experienceLevel)] ?? 1;
      if (itemExperience > userExperience) {
        reasons.add(
          'Mức kinh nghiệm ${item.experienceLevel} vượt mức hiện tại (${profile.experienceLevel}).',
        );
      }

      if (maxBudget != null && item.estimatedCostVnd > maxBudget) {
        reasons.add(
          'Chi phí ${item.estimatedCostVnd} VND vượt ngân sách tối đa $maxBudget VND.',
        );
      }

      if (dislikedCategories.contains(_normalize(item.category)) ||
          dislikedCategories.contains(_normalize(item.slug))) {
        reasons.add('Thuộc nhóm môn tập người dùng đánh dấu không thích.');
      }

      if (reasons.isEmpty) {
        eligible.add(item);
      } else {
        excluded.add(FilteredOutCandidate(item: item, reasons: reasons));
      }
    }

    return HardFilterResult<ExerciseCatalogItem>(
      status: RecommendationGateStatus.ready,
      message: eligible.isEmpty
          ? 'Không có môn tập phù hợp với các ràng buộc hiện tại; hệ thống không nới lỏng ràng buộc an toàn.'
          : null,
      eligibleItems: List<ExerciseCatalogItem>.unmodifiable(eligible),
      excludedItems: List<FilteredOutCandidate<ExerciseCatalogItem>>.unmodifiable(
        excluded,
      ),
    );
  }

  /// Lọc cứng danh mục món ăn theo xác nhận dị ứng, độ rõ thành phần, dị nguyên, nguyên liệu tránh, khả năng nấu, thời gian và ngân sách.
  HardFilterResult<MealCatalogItem> filterMeals({
    required List<MealCatalogItem> catalog,
    required RecommendationProfile profile,
    String? mealType,
  }) {
    final gateFailure = validateBaseInput<MealCatalogItem>(profile);
    if (gateFailure != null) {
      return gateFailure;
    }

    if (!profile.allergiesConfirmed) {
      return const HardFilterResult<MealCatalogItem>(
        status: RecommendationGateStatus.allergiesUnconfirmed,
        message:
            'Chưa xác nhận tình trạng dị ứng và nguyên liệu cần tránh nên chưa bật gợi ý món ăn.',
        missingFields: ['allergiesConfirmed'],
      );
    }

    final blockedAllergens = profile.allergies.map(_normalize).toSet();
    final blockedIngredients = profile.avoidedIngredients.map(_normalize).toSet();
    final allBlockedTerms = <String>{...blockedAllergens, ...blockedIngredients};
    final requiredDiets = profile.requiredDietTags.map(_normalize).toSet();
    final targetMealType = mealType == null ? null : _normalize(mealType);

    final eligible = <MealCatalogItem>[];
    final excluded = <FilteredOutCandidate<MealCatalogItem>>[];

    for (final item in catalog) {
      final reasons = <String>[];

      if (!item.hasVerifiedSource) {
        reasons.add('Món ăn chưa được kiểm duyệt hoặc thiếu nguồn tham khảo.');
      }

      if (!item.hasClearIngredients) {
        reasons.add(
          'Món ăn không rõ thành phần nguyên liệu nên không được coi là an toàn.',
        );
      }

      if (_containsForbiddenSafetyPhrase(
        '${item.name} ${item.description} ${item.notes ?? ''}',
      )) {
        reasons.add('Nội dung nằm ngoài phạm vi lối sống lành mạnh.');
      }

      if (targetMealType != null &&
          targetMealType.isNotEmpty &&
          _normalize(item.mealType) != targetMealType) {
        reasons.add('Không thuộc loại bữa ăn đang cần ($mealType).');
      }

      final matchedAllergens = item.allergens
          .map(_normalize)
          .where(allBlockedTerms.contains)
          .toList();
      if (matchedAllergens.isNotEmpty) {
        reasons.add(
          'Chứa dị nguyên cần tránh: ${matchedAllergens.join(', ')}.',
        );
      }

      final matchedIngredients = item.ingredients
          .map(_normalize)
          .where((ingredient) => _matchesBlockedIngredient(ingredient, allBlockedTerms))
          .toList();
      if (matchedIngredients.isNotEmpty) {
        reasons.add(
          'Chứa nguyên liệu cần tránh: ${matchedIngredients.join(', ')}.',
        );
      }

      if (!profile.canCook && item.requiresCooking) {
        reasons.add('Món ăn cần nấu nhưng hồ sơ không có điều kiện nấu.');
      }

      if (profile.maxMealPrepMinutes != null &&
          item.prepTimeMinutes > profile.maxMealPrepMinutes!) {
        reasons.add(
          'Thời gian chuẩn bị ${item.prepTimeMinutes} phút vượt giới hạn ${profile.maxMealPrepMinutes} phút.',
        );
      }

      if (profile.maxMealBudgetVnd != null &&
          item.estimatedCostVnd > profile.maxMealBudgetVnd!) {
        reasons.add(
          'Chi phí ước tính ${item.estimatedCostVnd}đ vượt ngân sách ${profile.maxMealBudgetVnd}đ.',
        );
      }

      if (requiredDiets.isNotEmpty) {
        final itemDiets = item.dietTags.map(_normalize).toSet();
        final missingDiets = requiredDiets.difference(itemDiets).toList();
        if (missingDiets.isNotEmpty) {
          reasons.add(
            'Không đáp ứng chế độ ăn bắt buộc: ${missingDiets.join(', ')}.',
          );
        }
      }

      if (reasons.isEmpty) {
        eligible.add(item);
      } else {
        excluded.add(FilteredOutCandidate(item: item, reasons: reasons));
      }
    }

    return HardFilterResult<MealCatalogItem>(
      status: RecommendationGateStatus.ready,
      message: eligible.isEmpty
          ? 'Không có món ăn phù hợp với các ràng buộc an toàn hiện tại; hệ thống không nới lỏng ràng buộc dị ứng hoặc thành phần.'
          : null,
      eligibleItems: List<MealCatalogItem>.unmodifiable(eligible),
      excludedItems: List<FilteredOutCandidate<MealCatalogItem>>.unmodifiable(
        excluded,
      ),
    );
  }

  static bool _matchesBlockedIngredient(
    String normalizedIngredient,
    Set<String> blockedTerms,
  ) {
    if (blockedTerms.contains(normalizedIngredient)) {
      return true;
    }
    for (final term in blockedTerms) {
      if (term.length >= 3 && normalizedIngredient.contains(term)) {
        return true;
      }
    }
    return false;
  }

  static bool _containsForbiddenSafetyPhrase(String text) {
    final normalized = _normalize(text);
    for (final keyword in _forbiddenSafetyKeywords) {
      if (normalized.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
