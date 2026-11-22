# Module `recommendations` — Danh mục có nguồn & Bộ gợi ý có giải thích (Issue #10)

- **Người phụ trách:** Nguyễn Đăng Đại (`@nddai0710`)
- **Review chéo:** Nguyễn Thế Trưởng (`@trggg2185`)
- **Nhánh phát triển:** `feature/nhom06/recommend` (base PR nội bộ: `nhom06-65ktpm`)
- **Trạng thái hiện tại:** Đã hoàn thiện danh mục mẫu/seed có nguồn kiểm duyệt, bộ lọc cứng an toàn, bộ xếp hạng có giải thích, widget xem trước độc lập và 29 unit/widget tests chạy bằng mock/fixture. Chưa gắn vào `lib/main.dart`, điều hướng chung hoặc truy vấn trực tiếp từ Supabase thật.

---

## 1. Cấu trúc mã nguồn

```text
nhom06-65ktpm/src/
├── lib/features/recommendations/
│   ├── data/
│   │   ├── fixtures/
│   │   │   ├── sample_catalog_fixture.dart      # 10 môn tập + 10 món ăn mẫu có nguồn WHO và mẫu biên kiểm thử
│   │   │   └── sample_profile_fixtures.dart     # 11 hồ sơ giả lập (văn phòng, sinh viên, ca đêm, các ca biên)
│   │   └── repositories/
│   │       └── fixture_catalog_repository.dart  # Mock/fixture repository triển khai CatalogRepository
│   ├── domain/
│   │   ├── entities/
│   │   │   ├── catalog_source.dart              # Nguồn kiểm duyệt (source_name, source_url, source_version, reviewed_at)
│   │   │   ├── exercise_catalog_item.dart       # Model môn tập (thiết bị, thời lượng, ngân sách, giới hạn, nguồn)
│   │   │   ├── meal_catalog_item.dart           # Model món ăn (nguyên liệu rõ ràng, dị nguyên, ngân sách, thời gian, nguồn)
│   │   │   ├── recommendation_profile.dart      # Hồ sơ đầu vào cá nhân hóa
│   │   │   ├── hard_filter_result.dart          # Trạng thái cổng kiểm tra và kết quả lọc cứng
│   │   │   └── recommendation_result.dart       # Kết quả xếp hạng, lý do giải thích và lựa chọn thay thế
│   │   ├── repositories/
│   │   │   └── catalog_repository.dart          # Interface truy xuất danh mục độc lập nguồn lưu trữ
│   │   ├── services/
│   │   │   ├── catalog_hard_filter.dart         # Kiểm tra đầu vào bắt buộc + lọc cứng an toàn trước xếp hạng
│   │   │   └── recommendation_engine.dart       # Xếp hạng theo sở thích/thời gian/ngân sách/đa dạng + giải thích
│   │   └── usecases/
│   │       └── get_recommendations_usecase.dart # Use case kết nối CatalogRepository và RecommendationEngine
│   ├── presentation/
│   │   └── widgets/
│   │       └── recommendation_preview_view.dart # Widget hiển thị gợi ý độc lập (không chạm main.dart)
│   └── README.md
├── supabase/seed/
│   └── catalog_seed.json                        # File seed JSON đồng bộ 10 môn tập + 10 món ăn với fixture
└── test/features/recommendations/
    ├── catalog_fixture_test.dart                # Kiểm thử danh mục mẫu, nguồn kiểm duyệt và JSON seed (4 tests)
    ├── catalog_hard_filter_test.dart            # Kiểm thử cổng đầu vào và lọc cứng (9 tests)
    ├── recommendation_engine_test.dart          # Kiểm thử xếp hạng, giải thích, đa dạng và use case (6 tests)
    └── recommendation_acceptance_test.dart      # Kiểm thử nghiệm thu ca biên + widget test (10 tests)
```

---

## 2. Nguyên tắc nghiệp vụ và an toàn đã áp dụng

1. **Cổng đầu vào bắt buộc (`CatalogHardFilter.validateBaseInput`)**:
   - Yêu cầu xác nhận từ 18 tuổi trở lên (`isAdultConfirmed == true`).
   - Khi người dùng tự khai báo cần tư vấn chuyên môn (`requiresProfessionalGuidance == true`) → chặn gợi ý tự động, trả trạng thái `professionalGuidanceRequired` để dùng lịch thủ công.
   - Chặn mục tiêu và nội dung liên quan điều trị y khoa hoặc giảm cân nhanh/thâm hụt calo cực đoan (`unsafeGoalBlocked`).
   - Thiếu `timezone`, `goal`, `availableMinutesPerSession` hoặc `sessionsPerWeek` bất hợp lý → trả `missingRequiredInput` kèm danh sách `missingFields`.
2. **Lọc cứng trước xếp hạng (`CatalogHardFilter`)**:
   - Món ăn: chưa xác nhận dị ứng (`allergiesConfirmed == false`) thì chưa bật gợi ý món ăn (`allergiesUnconfirmed`). Loại mọi món chưa kiểm duyệt, không rõ thành phần nguyên liệu (`!hasClearIngredients`), chứa dị nguyên hoặc nguyên liệu cần tránh, không khớp khả năng nấu/thời gian/ngân sách/chế độ ăn bắt buộc.
   - Môn tập: loại mọi bài tập chưa kiểm duyệt, vi phạm giới hạn vận động tự khai báo, thiếu thiết bị, lệch môi trường (`indoor`/`outdoor`), vượt mức kinh nghiệm, vượt thời lượng rảnh/ngân sách hoặc nằm trong môn không thích.
3. **Xếp hạng có giải thích & không nới ràng buộc (`RecommendationEngine`)**:
   - Chấm điểm minh bạch theo quy tắc sản phẩm (sở thích, thời gian, thiết bị/ngân sách, phản hồi thích/không phù hợp, đa dạng) và sinh câu giải thích tiếng Việt kèm lựa chọn thay thế (`alternatives`).
   - Nếu lọc cứng không còn ứng viên nào → trả danh sách rỗng kèm `emptyReason`, **tuyệt đối không nới lỏng ràng buộc**.

---

## 3. Cách chạy kiểm tra phần thay đổi

Từ thư mục gốc repository (`project-ptdudd/`):

```powershell
cd nhom06-65ktpm/src
flutter pub get
flutter analyze --no-pub
flutter test test/features/recommendations/ --no-pub
```

Hoặc chạy toàn bộ bộ test trong `src/`:

```powershell
flutter test --no-pub
```

### Phạm vi đã kiểm tra và chưa kiểm tra
- **Đã kiểm tra:**
  - `flutter analyze --no-pub`: không có lỗi/cảnh báo.
  - `flutter test --no-pub`: toàn bộ **29/29** unit tests và widget test của module `recommendations` đạt.
- **Chưa kiểm tra:**
  - Chưa kiểm thử đọc danh mục trực tiếp từ Supabase thật (đang chạy với `FixtureCatalogRepository` mock/fixture).
  - Chưa kiểm thử luồng tích hợp với `main.dart`, `auth`, `profile` và `planner`.

---

## 4. Đề xuất phối hợp tích hợp

- **Với Trưởng (`@trggg2185` — `profile`, `planner`, `app/`):**
  - Ánh xạ dữ liệu từ hồ sơ người dùng sang `RecommendationProfile` và gọi `GetRecommendationsUseCase`.
  - Gắn `RecommendationPreviewView` vào điều hướng chung; sử dụng callback `onSelectExercise` / `onSelectMeal` để chuyển lựa chọn người dùng duyệt sang lịch nháp của `planner`.
- **Với Hà (`@HanHoangHa` — `supabase/migrations`, `supabase/seed`):**
  - `ExerciseCatalogItem.fromMap` và `MealCatalogItem.fromMap` đã tương thích các cột cơ bản trong bảng `exercise_catalog` và `meal_catalog` (`slug`, `name`, `description`, `duration_minutes`, `equipment`, `experience_level`, `ingredients`, `allergens`, `estimated_cost`, `preparation_minutes`, `source_name`, `source_url`, `source_version`, `approved`).
  - Đề xuất chốt thêm (dạng cột hoặc `jsonb` metadata) cho các trường phục vụ lọc/xếp hạng: `category`, `environment`, `budget_tier`, `contraindicated_limitations`, `tags`, `meal_type`, `ingredients_clear`, `diet_tags`, `requires_cooking`, `notes`; đồng thời thống nhất nguồn seed giữa `supabase/seed/20261121_initial_catalog.sql` và `supabase/seed/catalog_seed.json`.
