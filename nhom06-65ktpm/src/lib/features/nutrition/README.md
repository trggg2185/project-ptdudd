# Module `nutrition` — Nhật ký bữa ăn và camera với ảnh riêng tư (Issue #11)

- **Người phụ trách:** Nguyễn Đăng Đại (`@nddai0710`)
- **Review chéo:** Nguyễn Thế Trưởng (`@trggg2185`)
- **Nhánh phát triển:** `feature/nhom06/nutrition` (base PR nội bộ: `nhom06-65ktpm`)
- **Phụ thuộc phối hợp:** Issue #7 (`LocalDatabase`, `public.meal_logs`, bucket riêng tư `meal-images`) và Issue #10 (`GetRecommendationsUseCase`, `MealCatalogItem`, `RecommendationProfile`).
- **Trạng thái hiện tại:** Đã đồng bộ mới nhất từ `nhom06-65ktpm` (`464d08b` — bản tích hợp #1, #4, #7, #10), hoàn thiện luồng gợi ý/đổi món theo hồ sơ, xác nhận tên món người dùng, validate định dạng/kích thước ở cả client và dịch vụ, nén & xóa EXIF/GPS trên JPEG/PNG/WebP, xử lý từ chối quyền/ảnh lỗi/mất mạng (tích hợp `LocalDatabase` SQLite + `LocalSyncWorker` + hàng đợi ảnh chờ retry), khóa suy luận calo/dị nguyên từ ảnh, tách ranh giới AI mở rộng và 22 unit/widget tests. Chưa gắn vào `lib/main.dart`, chưa cấu hình plugin camera thiết bị thật hoặc upload trực tiếp lên Supabase cloud thật.

---

## 1. Cấu trúc mã nguồn

```text
nhom06-65ktpm/src/
├── lib/features/nutrition/
│   ├── data/
│   │   └── repositories/
│   │       ├── in_memory_meal_log_repository.dart        # Mock/fixture lưu nhật ký theo owner_uid
│   │       ├── in_memory_pending_meal_photo_store.dart   # Hàng đợi ảnh sạch EXIF chờ retry theo owner_uid
│   │       ├── local_database_meal_log_repository.dart   # Adapter SQLite dùng LocalDatabase (entity_type = 'meal_log')
│   │       ├── mock_meal_photo_services.dart             # MockMealPhotoPicker & InMemoryPrivateMealPhotoStorage
│   │       └── supabase_private_meal_photo_storage.dart  # Adapter bucket riêng tư 'meal-images' (<owner_uid>/<log_id>.<ext>)
│   ├── domain/
│   │   ├── entities/
│   │   │   ├── meal_label_suggestion.dart                # Trạng thái AI mở rộng & cảnh báo không suy calo/dị nguyên từ ảnh
│   │   │   ├── meal_log.dart                             # Model nhật ký tương thích public.meal_logs (toSupabasePayload)
│   │   │   ├── meal_photo_access_error.dart              # Mã lỗi quyền/thiết bị/mạng, MealPhotoPickOutcome, MealLogSaveResult
│   │   │   ├── meal_photo_attachment.dart                # MealPhotoSource, MealPhotoUploadStatus, Selected/StoredMealPhoto
│   │   │   ├── meal_photo_policy.dart                    # Giới hạn loại/kích thước ảnh, MealPhotoException, PreparedMealPhoto
│   │   │   └── meal_suggestion_session.dart              # Phiên gợi ý & đổi món (swapToNext / selectBySlug)
│   │   ├── repositories/
│   │   │   ├── meal_log_repository.dart                  # Interface lưu trữ nhật ký bữa ăn
│   │   │   ├── meal_photo_picker.dart                    # Interface chụp camera / chọn thư viện
│   │   │   ├── meal_photo_storage.dart                   # Interface lưu ảnh riêng tư 'meal-images'
│   │   │   ├── optional_meal_label_suggester.dart        # Điểm mở rộng tùy chọn cho AI đề xuất nhãn qua server
│   │   │   └── pending_meal_photo_store.dart             # Interface hàng đợi ảnh chờ đồng bộ khi mất mạng
│   │   ├── services/
│   │   │   ├── meal_photo_processor.dart                 # Xóa EXIF/GPS nhị phân (JPEG/PNG/WebP) + nén lặp + kiểm tra lại
│   │   │   └── meal_photo_validator.dart                 # Validate magic bytes, MIME, cấu trúc, kích thước và phát hiện EXIF
│   │   └── usecases/
│   │       └── meal_nutrition_usecase.dart               # Use case điều phối toàn bộ luồng nutrition
│   ├── presentation/
│   │   └── widgets/
│   │       └── meal_log_composer_view.dart               # Widget ghi nhật ký độc lập (không chỉnh main.dart)
│   └── README.md
└── test/features/nutrition/
    ├── meal_nutrition_flow_test.dart                     # Gợi ý/đổi món, xác nhận tên món, ảnh riêng tư & widget test (4 tests)
    ├── meal_photo_processing_test.dart                   # Validate client/service, xóa EXIF JPEG/PNG/WebP, nén lặp (7 tests)
    ├── meal_resilience_offline_test.dart                 # Từ chối quyền, ảnh lỗi, mất mạng SQLite + LocalSyncWorker + Storage guard (6 tests)
    └── meal_ai_safety_boundary_test.dart                 # Không suy calo/dị nguyên từ ảnh, AI mở rộng không chặn lõi (5 tests)
```

---

## 2. Nguyên tắc kỹ thuật và an toàn đã áp dụng

1. **Gợi ý/đổi món & xác nhận tên món (`MealNutritionUseCase` + `MealSuggestionSession`)**:
   - Tái sử dụng trực tiếp `GetRecommendationsUseCase` (Issue #10) nên đổi món chỉ xoay vòng trong danh sách đã lọc cứng dị ứng/thành phần rõ ràng.
   - Bắt buộc người dùng nhập hoặc xác nhận `confirmedMealName` trước khi lưu (`userConfirmedName = true`).
2. **Validate 2 lớp (client + dịch vụ), nén và xóa EXIF trước upload (`MealPhotoValidator`, `DefaultMealPhotoProcessor`, `MealPhotoStorage`)**:
   - Chỉ chấp nhận JPEG/PNG/WebP xác minh theo **magic bytes** và cấu trúc nhị phân hợp lệ (chặn tệp rỗng, tệp giả mạo đuôi `.jpg`, lệch MIME, ảnh hỏng).
   - Giới hạn ảnh gốc tối đa **10 MB**, ảnh sau xử lý/upload tối đa **1 MB**.
   - Xóa triệt để metadata EXIF/GPS/XMP/IPTC/Comment ở mức nhị phân cho JPEG (`APP1`/`APP13`/`COM`), PNG (`eXIf`/`tEXt`/`iTXt`/`zTXt`) và WebP (`EXIF`/`XMP ` + bit cờ `VP8X`), sau đó chạy nén lặp qua `MealPhotoCompressor` (nếu có) và xóa lại EXIF.
   - Lớp dịch vụ Storage (`SupabasePrivateMealPhotoStorage` và `InMemoryPrivateMealPhotoStorage`) luôn gọi lại `validateForUpload` và ép đường dẫn riêng tư `<owner_uid>/<log_id>.<ext>` khớp RLS bucket `meal-images`.
3. **Từ chối quyền / ảnh lỗi / mất mạng không mất nhật ký**:
   - `pickAndPreparePhoto` bắt mọi lỗi quyền Camera/Thư viện, không có camera, ảnh lỗi và chuyển về hướng dẫn nhập tay mà không xóa dữ liệu người dùng đang nhập.
   - `saveMealLogResilient` khi gặp mất mạng/timeout vẫn lưu nhật ký vào `LocalDatabaseMealLogRepository` (`local_records` + `sync_queue` với `entity_type = 'meal_log'`), giữ ảnh sạch EXIF trong `PendingMealPhotoStore` theo đúng `owner_uid` và đánh dấu `photoUploadStatus = pendingLocal` (không báo upload cloud thành công giả). Khi có mạng lại, `retryPendingPhotoUploads` cập nhật `imagePath` vào đúng `logId` cũ mà không tạo bản ghi trùng.
4. **Không suy ra calo/dị nguyên từ ảnh; AI chỉ là mở rộng**:
   - Bản cốt lõi tắt AI (`optionalLabelSuggester == null`). Nếu bật mở rộng về sau phải gọi qua server với đồng ý riêng (`aiConsentGranted == true`), tự động lọc bỏ mọi nhãn chứa tuyên bố calo/an toàn dị nguyên, fallback êm về nhập tay khi lỗi và không tự ghi đè tên món người dùng.

---

## 3. Cách chạy kiểm tra phần thay đổi

Từ thư mục gốc repository (`project-ptdudd/`):

```powershell
cd nhom06-65ktpm/src
flutter pub get
flutter analyze --no-pub
flutter test test/features/nutrition/ --no-pub
```

Chạy toàn bộ bộ test dự án:

```powershell
flutter test --no-pub
```

### Phạm vi đã kiểm tra và chưa kiểm tra
- **Đã kiểm tra:**
  - `flutter analyze --no-pub`: không có lỗi/cảnh báo.
  - `flutter test test/features/nutrition/ --no-pub`: **22/22** unit tests & widget tests đạt (bao gồm test lưu SQLite + `LocalSyncWorker` qua `sqflite_common_ffi` và kiểm tra chống lệch `ownerUid`/path traversal).
  - `flutter test --no-pub`: toàn bộ tests của dự án đạt.
- **Chưa kiểm tra:**
  - Chưa kiểm thử chụp ảnh thật, cấp/thu hồi quyền Camera và nén native trên thiết bị Android vật lý (cần bổ sung adapter `image_picker` / quyền Android khi cả nhóm chốt tích hợp phần cứng).
  - Chưa kiểm thử upload/xem signed URL trực tiếp trên Supabase Storage thật với 3 tài khoản A/B/C (thuộc bước tích hợp và Issue #9).

---

## 4. Đề xuất phối hợp tích hợp

- **Với Trưởng (`@trggg2185` — `auth`, `profile`, `app/`):**
  - Gắn `MealLogComposerView` vào `_SessionNavigator` của `AuthGate` (đã hỗ trợ làm mới dữ liệu & xóa ảnh tạm khi đổi `ownerUid`); truyền `ownerUid` từ `AuthSession` và `RecommendationProfile` từ hồ sơ người dùng.
  - `SupabasePrivateMealPhotoStorage` yêu cầu truyền `currentOwnerUid` bắt buộc đồng nhất với `SupabaseSyncTransport` (commit `464d08b`), chặn truy cập/tải lên chéo tài khoản.
  - Khi đăng xuất/đổi tài khoản, gọi `pendingPhotoStore.clearForOwner(oldUid)` hoặc xử lý hàng đợi chờ rõ ràng theo quy định bảo mật.
- **Với Hà (`@HanHoangHa` — `supabase/migrations`, `LocalDatabase`):**
  - `MealLog.toSupabasePayload()` đã khớp các cột `meal_id`, `meal_name`, `image_path`, `consumed_at`, `note` của bảng `public.meal_logs`, tương thích `LocalDatabase` + `LocalSyncWorker` (`entity_type = 'meal_log'`) và migration `20261123_000003_catalog_and_sync_integration.sql` (`p_expected_owner_uid` + trigger `advance_log_version`). Lưu ý khi ghi trực tiếp lần đầu lên `meal_logs` cần bảo đảm đã có hàng tối thiểu trong `public.profiles` (tương tự `SupabaseHabitRepository`).
  - Đề xuất cân nhắc bổ sung ràng buộc mức bucket trên `storage.buckets` cho `'meal-images'` (`file_size_limit = 1048576`, `allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']`) trong lần cập nhật migration tiếp theo để củng cố thêm lớp kiểm tra phía Supabase Storage.
