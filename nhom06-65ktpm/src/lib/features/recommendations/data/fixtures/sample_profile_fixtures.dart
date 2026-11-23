import '../../domain/entities/recommendation_profile.dart';

/// Bộ hồ sơ giả lập (mock/fixture) đại diện cho các kịch bản demo và ca biên kiểm thử.
/// Không chứa dữ liệu cá nhân hay dữ liệu sức khỏe thật.
class SampleProfileFixtures {
  /// Nhân viên văn phòng 08:00–17:00, thích đi bộ ngoài trời, không có thiết bị, rảnh 20 phút.
  static const RecommendationProfile officeWorkerWalking =
      RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'regular_activity',
        availableMinutesPerSession: 20,
        sessionsPerWeek: 4,
        experienceLevel: 'beginner',
        availableEquipment: [],
        preferredEnvironment: 'outdoor',
        preferredExerciseCategories: ['walking'],
        preferredExerciseTags: ['outdoor', 'no_equipment'],
        allergiesConfirmed: true,
        allergies: ['seafood'],
        canCook: true,
        maxMealPrepMinutes: 25,
        maxMealBudgetVnd: 45000,
        preferredDietTags: ['balanced', 'quick_prep'],
      );

  /// Sinh viên ngân sách thấp, không có bếp nấu, không có thiết bị, dị ứng đậu phộng.
  static const RecommendationProfile studentLowBudgetNoCook =
      RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'maintain_habit',
        availableMinutesPerSession: 15,
        sessionsPerWeek: 3,
        experienceLevel: 'beginner',
        availableEquipment: [],
        preferredEnvironment: 'indoor',
        preferredExerciseTags: ['no_equipment', 'desk_worker'],
        allergiesConfirmed: true,
        allergies: ['peanut'],
        canCook: false,
        maxMealPrepMinutes: 15,
        maxMealBudgetVnd: 30000,
        preferredDietTags: ['quick_prep', 'no_cook'],
      );

  /// Người làm ca đêm, có thảm tập, cần tránh tác động mạnh lên khớp gối, dị ứng sữa và trứng.
  static const RecommendationProfile shiftWorkerNight = RecommendationProfile(
    isAdultConfirmed: true,
    timezone: 'Asia/Ho_Chi_Minh',
    goal: 'regular_sleep',
    availableMinutesPerSession: 25,
    sessionsPerWeek: 3,
    experienceLevel: 'intermediate',
    availableEquipment: ['mat'],
    movementLimitations: ['knee_impact'],
    preferredEnvironment: 'indoor',
    preferredExerciseCategories: ['flexibility'],
    allergiesConfirmed: true,
    allergies: ['dairy', 'egg'],
    canCook: true,
    maxMealPrepMinutes: 30,
    maxMealBudgetVnd: 40000,
    preferredDietTags: ['balanced'],
  );

  /// Ca biên: thiếu các trường đầu vào bắt buộc.
  static const RecommendationProfile missingRequiredInputs =
      RecommendationProfile(
        isAdultConfirmed: true,
        timezone: '',
        goal: null,
        availableMinutesPerSession: null,
        sessionsPerWeek: 0,
        allergiesConfirmed: true,
      );

  /// Ca biên: chưa xác nhận đủ 18 tuổi.
  static const RecommendationProfile underageProfile = RecommendationProfile(
    isAdultConfirmed: false,
    timezone: 'Asia/Ho_Chi_Minh',
    goal: 'maintain_habit',
    availableMinutesPerSession: 20,
    sessionsPerWeek: 3,
    allergiesConfirmed: true,
  );

  /// Ca biên: đủ thông tin vận động nhưng chưa xác nhận dị ứng thực phẩm.
  static const RecommendationProfile unconfirmedAllergies =
      RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'maintain_habit',
        availableMinutesPerSession: 20,
        sessionsPerWeek: 3,
        availableEquipment: [],
        allergiesConfirmed: false,
      );

  /// Ca biên: tự khai báo cần tư vấn chuyên môn.
  static const RecommendationProfile professionalGuidanceProfile =
      RecommendationProfile(
        isAdultConfirmed: true,
        requiresProfessionalGuidance: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'maintain_habit',
        availableMinutesPerSession: 20,
        sessionsPerWeek: 3,
        allergiesConfirmed: true,
      );

  /// Ca biên: mục tiêu điều trị y khoa (ngoài phạm vi hỗ trợ tự động).
  static const RecommendationProfile medicalTreatmentGoalProfile =
      RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'dieu_tri_benh_ly',
        availableMinutesPerSession: 20,
        sessionsPerWeek: 3,
        allergiesConfirmed: true,
      );

  /// Ca biên: mục tiêu giảm cân nhanh (ngoài phạm vi hỗ trợ tự động).
  static const RecommendationProfile rapidWeightLossGoalProfile =
      RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'giam_can_nhanh',
        availableMinutesPerSession: 30,
        sessionsPerWeek: 5,
        allergiesConfirmed: true,
      );

  /// Ca biên: không có thiết bị và quỹ thời gian quá ngắn nên không có bài tập phù hợp.
  static const RecommendationProfile noEquipmentStrictProfile =
      RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'regular_activity',
        availableMinutesPerSession: 5,
        sessionsPerWeek: 3,
        availableEquipment: [],
        preferredEnvironment: 'outdoor',
        allergiesConfirmed: true,
      );

  /// Ca biên: dị ứng đa nhóm kèm ngân sách quá thấp khiến không còn món hợp lệ.
  static const RecommendationProfile multiAllergyNoMatchProfile =
      RecommendationProfile(
        isAdultConfirmed: true,
        timezone: 'Asia/Ho_Chi_Minh',
        goal: 'maintain_habit',
        availableMinutesPerSession: 20,
        sessionsPerWeek: 3,
        allergiesConfirmed: true,
        allergies: ['dairy', 'egg', 'peanut', 'gluten', 'seafood', 'soy'],
        canCook: false,
        maxMealBudgetVnd: 10000,
      );
}
