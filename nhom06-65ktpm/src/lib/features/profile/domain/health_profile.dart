import '../../recommendations/domain/entities/recommendation_profile.dart';
import '../../recommendations/domain/services/catalog_hard_filter.dart';
import 'profile_time.dart';

enum ProfileGoal {
  maintainHabit('maintain_habit'),
  regularSleep('regular_sleep'),
  regularActivity('regular_activity');

  const ProfileGoal(this.code);

  final String code;

  static ProfileGoal? fromCode(Object? code) =>
      values.where((goal) => goal.code == code).firstOrNull;
}

enum ActivityLevel { beginner, intermediate, advanced }

enum AllergyStatus { unconfirmed, none, declared }

class HealthProfile {
  HealthProfile({
    this.adultConfirmed = false,
    this.requiresProfessionalGuidance = false,
    this.timeZone,
    this.goal,
    this.activityLevel,
    this.occupation,
    this.sessionMinutes,
    this.sessionsPerWeek,
    this.exerciseBudget,
    this.mealBudget,
    this.sleepStart,
    this.sleepEnd,
    this.allergyStatus = AllergyStatus.unconfirmed,
    Iterable<String> equipment = const [],
    Iterable<String> preferredSports = const [],
    Iterable<String> dislikedSports = const [],
    Iterable<String> movementLimits = const [],
    Iterable<String> allergens = const [],
    Iterable<String> avoidedIngredients = const [],
  }) : equipment = Set.unmodifiable(equipment),
       preferredSports = Set.unmodifiable(preferredSports),
       dislikedSports = Set.unmodifiable(dislikedSports),
       movementLimits = Set.unmodifiable(movementLimits),
       allergens = Set.unmodifiable(allergens),
       avoidedIngredients = Set.unmodifiable(avoidedIngredients);

  final bool adultConfirmed;
  final bool requiresProfessionalGuidance;
  final String? timeZone;
  final ProfileGoal? goal;
  final ActivityLevel? activityLevel;
  final String? occupation;
  final int? sessionMinutes;
  final int? sessionsPerWeek;
  final int? exerciseBudget;
  final int? mealBudget;
  final int? sleepStart;
  final int? sleepEnd;
  final AllergyStatus allergyStatus;
  final Set<String> equipment;
  final Set<String> preferredSports;
  final Set<String> dislikedSports;
  final Set<String> movementLimits;
  final Set<String> allergens;
  final Set<String> avoidedIngredients;

  static const goals = {
    ProfileGoal.maintainHabit: 'Duy trì thói quen',
    ProfileGoal.regularSleep: 'Ngủ đều hơn',
    ProfileGoal.regularActivity: 'Vận động thường xuyên',
  };
  static const activityLevels = {
    ActivityLevel.beginner: 'Ít vận động hoặc mới bắt đầu',
    ActivityLevel.intermediate: 'Đã tập và có kinh nghiệm cơ bản',
    ActivityLevel.advanced: 'Tập đều và có kinh nghiệm',
  };
  static const occupations = {
    'student': 'Học sinh, sinh viên',
    'office': 'Văn phòng',
    'mobile': 'Thường xuyên di chuyển',
    'physical': 'Lao động thể lực',
    'shift': 'Làm việc theo ca',
    'other': 'Khác',
  };
  static const sports = {
    'walking': 'Đi bộ',
    'flexibility': 'Giãn cơ, yoga',
    'strength': 'Tập sức mạnh',
    'cardio': 'Chạy, cardio',
    'cycling': 'Đạp xe',
  };
  static const availableEquipment = {
    'mat': 'Thảm',
    'resistance_band': 'Dây kháng lực',
    'jump_rope': 'Dây nhảy',
    'running_shoes': 'Giày chạy',
    'dumbbells': 'Tạ tay',
    'bicycle': 'Xe đạp',
  };
  static const movementOptions = {
    'knee_impact': 'Tránh tác động mạnh lên gối',
    'shoulder_pain': 'Tránh tải lên vai',
    'ankle_injury': 'Tránh tải lên cổ chân',
    'lower_back_strain': 'Tránh tải lên lưng dưới',
    'high_impact': 'Tránh bài tác động mạnh',
  };
  static const allergenOptions = {
    'peanut': 'Đậu phộng',
    'soy': 'Đậu nành',
    'dairy': 'Sữa',
    'egg': 'Trứng',
    'gluten': 'Gluten',
    'fish': 'Cá',
    'shellfish': 'Tôm, cua và động vật có vỏ',
    'seafood': 'Hải sản nói chung',
    'sesame': 'Mè',
  };

  bool get allergiesAreConfirmed =>
      allergyStatus == AllergyStatus.none ||
      (allergyStatus == AllergyStatus.declared &&
          allergens.isNotEmpty &&
          allergens.every(allergenOptions.containsKey));

  RecommendationProfile toRecommendationProfile() => RecommendationProfile(
    isAdultConfirmed: adultConfirmed,
    requiresProfessionalGuidance: requiresProfessionalGuidance,
    timezone: profileLocation(timeZone) == null ? null : timeZone,
    goal: goal?.code,
    availableMinutesPerSession: activityLevel == null ? null : sessionMinutes,
    sessionsPerWeek: sessionsPerWeek,
    experienceLevel: activityLevel?.name ?? ActivityLevel.beginner.name,
    availableEquipment: equipment.toList(),
    movementLimitations: movementLimits.toList(),
    preferredExerciseCategories: preferredSports.toList(),
    dislikedExerciseCategories: dislikedSports.toList(),
    maxExerciseBudgetVnd: exerciseBudget,
    maxMealBudgetVnd: mealBudget,
    allergiesConfirmed: allergiesAreConfirmed,
    allergies: allergyStatus == AllergyStatus.declared
        ? allergens.toList()
        : [],
    avoidedIngredients: avoidedIngredients.map(ingredientCode).toSet().toList(),
  );

  String? get automaticScheduleBlockReason {
    final input = toRecommendationProfile();
    if (adultConfirmed &&
        !requiresProfessionalGuidance &&
        activityLevel == null) {
      return 'Hãy chọn mức vận động hiện tại hoặc dùng lịch thủ công.';
    }
    return const CatalogHardFilter().validateBaseInput<Object>(input)?.message;
  }

  void validate() {
    if (timeZone != null && profileLocation(timeZone) == null) {
      throw const FormatException('Múi giờ không hợp lệ. Hãy nhập mã IANA.');
    }
    if ((sessionMinutes != null &&
            (sessionMinutes! < 1 || sessionMinutes! > 240)) ||
        (sessionsPerWeek != null &&
            (sessionsPerWeek! < 1 || sessionsPerWeek! > 14))) {
      throw const FormatException(
        'Thời lượng hoặc số buổi nằm ngoài khoảng cho phép.',
      );
    }
    if ((exerciseBudget != null && exerciseBudget! < 0) ||
        (mealBudget != null && mealBudget! < 0)) {
      throw const FormatException('Ngân sách phải từ 0 đồng trở lên.');
    }
    if ((sleepStart == null) != (sleepEnd == null) ||
        (sleepStart != null &&
            (!validClockMinute(sleepStart!) ||
                !validClockMinute(sleepEnd!) ||
                sleepStart == sleepEnd))) {
      throw const FormatException('Chọn đủ hai giờ ngủ và thức khác nhau.');
    }
    if (allergyStatus == AllergyStatus.declared && !allergiesAreConfirmed) {
      throw const FormatException(
        'Chọn dị nguyên hoặc để tình trạng chưa xác nhận.',
      );
    }
    if (preferredSports.intersection(dislikedSports).isNotEmpty) {
      throw const FormatException(
        'Mỗi nhóm môn tập chỉ có thể chọn thích hoặc tránh.',
      );
    }
  }

  static String ingredientCode(String value) {
    var normalized = value.toLowerCase();
    const groups = {
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    for (final entry in groups.entries) {
      normalized = normalized.replaceAll(RegExp('[${entry.value}]'), entry.key);
    }
    return normalized
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .trim()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .join('_');
  }
}
