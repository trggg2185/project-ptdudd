/// Hồ sơ đầu vào cá nhân hóa phục vụ kiểm tra điều kiện, lọc cứng và xếp hạng gợi ý.
/// Độc lập với module `profile` để phát triển và kiểm thử bằng fixture trước khi tích hợp.
class RecommendationProfile {
  /// Bắt buộc xác nhận người dùng từ 18 tuổi trở lên.
  final bool isAdultConfirmed;

  /// Người dùng tự khai báo có tình trạng cần tư vấn chuyên môn.
  /// Khi `true`, hệ thống không tạo kế hoạch tự động mà hướng dẫn dùng lịch thủ công.
  final bool requiresProfessionalGuidance;

  /// Múi giờ địa phương (vd: `Asia/Ho_Chi_Minh`).
  final String? timezone;

  /// Mục tiêu lối sống (vd: `maintain_habit`, `regular_sleep`, `regular_activity`).
  final String? goal;

  /// Thời lượng có thể dành cho mỗi buổi tập (phút).
  final int? availableMinutesPerSession;

  /// Số buổi vận động dự kiến mỗi tuần.
  final int? sessionsPerWeek;

  /// Mức kinh nghiệm vận động: `beginner`, `intermediate`, `advanced`.
  final String experienceLevel;

  /// Danh sách thiết bị sẵn có (vd: `['mat']`, `['dumbbells']`).
  final List<String> availableEquipment;

  /// Giới hạn vận động người dùng muốn áp dụng (vd: `['knee_impact']`).
  final List<String> movementLimitations;

  /// Môi trường tập ưu tiên: `indoor`, `outdoor`, `any`.
  final String preferredEnvironment;

  /// Ngân sách tối đa cho mỗi buổi tập (VND), `null` nếu không đặt trần.
  final int? maxExerciseBudgetVnd;

  /// Nhóm/môn tập yêu thích để ưu tiên khi xếp hạng.
  final List<String> preferredExerciseCategories;

  /// Nhóm/môn tập không thích để loại bỏ.
  final List<String> dislikedExerciseCategories;

  /// Thẻ sở thích vận động (vd: `['outdoor', 'no_equipment']`).
  final List<String> preferredExerciseTags;

  /// Cờ xác nhận người dùng đã khai báo/xác nhận tình trạng dị ứng thực phẩm.
  /// Theo đề cương: khi chưa xác nhận dị ứng thì chưa bật gợi ý món ăn.
  final bool allergiesConfirmed;

  /// Danh sách mã dị nguyên cần tránh (vd: `['peanut', 'dairy', 'seafood']`).
  final List<String> allergies;

  /// Danh sách nguyên liệu cụ thể người dùng muốn tránh (vd: `['tom', 'hanh_tay']`).
  final List<String> avoidedIngredients;

  /// Khả năng nấu ăn (`false` sẽ chỉ giữ các món không cần bếp nấu).
  final bool canCook;

  /// Thời gian chuẩn bị/nấu tối đa cho mỗi bữa (phút), `null` nếu không giới hạn.
  final int? maxMealPrepMinutes;

  /// Ngân sách tối đa cho mỗi bữa ăn (VND), `null` nếu không giới hạn.
  final int? maxMealBudgetVnd;

  /// Ràng buộc chế độ ăn bắt buộc (vd: `['vegetarian']`).
  final List<String> requiredDietTags;

  /// Thẻ sở thích ăn uống để cộng điểm xếp hạng (vd: `['quick_prep', 'high_protein']`).
  final List<String> preferredDietTags;

  /// Phản hồi trước đó từ người dùng: danh sách slug bài tập/món ăn đã thích.
  final List<String> likedSlugs;

  /// Phản hồi trước đó từ người dùng: danh sách slug bài tập/món ăn đánh dấu không phù hợp.
  final List<String> dislikedSlugs;

  const RecommendationProfile({
    this.isAdultConfirmed = false,
    this.requiresProfessionalGuidance = false,
    this.timezone,
    this.goal,
    this.availableMinutesPerSession,
    this.sessionsPerWeek,
    this.experienceLevel = 'beginner',
    this.availableEquipment = const [],
    this.movementLimitations = const [],
    this.preferredEnvironment = 'any',
    this.maxExerciseBudgetVnd,
    this.preferredExerciseCategories = const [],
    this.dislikedExerciseCategories = const [],
    this.preferredExerciseTags = const [],
    this.allergiesConfirmed = false,
    this.allergies = const [],
    this.avoidedIngredients = const [],
    this.canCook = true,
    this.maxMealPrepMinutes,
    this.maxMealBudgetVnd,
    this.requiredDietTags = const [],
    this.preferredDietTags = const [],
    this.likedSlugs = const [],
    this.dislikedSlugs = const [],
  });
}
