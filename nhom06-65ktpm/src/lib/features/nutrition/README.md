# Module `nutrition` — Nhật ký bữa ăn và camera với ảnh riêng tư (Issue #11)

- **Người phụ trách:** Nguyễn Đăng Đại (`@nddai0710`)
- **Review chéo:** Nguyễn Thế Trưởng (`@trggg2185`)
- **Nhánh phát triển:** `feature/nhom06/nutrition` (base PR nội bộ: `nhom06-65ktpm`)
- **Phụ thuộc phối hợp:** Issue #7 (`LocalDatabase`, `public.meal_logs`, bucket riêng tư `meal-images`) và Issue #10 (`GetRecommendationsUseCase`, `MealCatalogItem`, `RecommendationProfile`).
- **Trạng thái hiện tại:** Đã đồng bộ mới nhất từ `nhom06-65ktpm` (`464d08b` — bản tích hợp #1, #4, #7, #10), hoàn thiện luồng gợi ý/đổi món theo hồ sơ, xác nhận tên món người dùng, validate định dạng/kích thước ở client & adapter + bổ sung migration giới hạn phía Storage bucket `meal-images` (`20261125_000004_meal_images_bucket_limits.sql`), nén & xóa EXIF/GPS trên JPEG/PNG/WebP, xử lý retry idempotent khi mất phản hồi sau khi Storage đã lưu ảnh, lưu ảnh chờ bền vững trên SQLite (`LocalDatabasePendingMealPhotoStore`) qua đóng/mở lại app, báo đúng trạng thái nhập tay khi không có kho ảnh chờ, khóa suy luận calo/dị nguyên từ ảnh và tách ranh giới AI mở rộng. Chưa gắn vào `lib/main.dart`, chưa nối adapter phần cứng camera/nén native trên thiết bị Android thật và migration bucket cần được áp dụng lên project Supabase của nhóm cùng Hà.

---

## 1. Cấu trúc mã nguồn

```text
nhom06-65ktpm/src/
├── lib/features/nutrition/
│   ├── data/
│   │   └── repositories/
│   │       ├── in_memory_meal_log_repository.dart        # Mock/fixture lưu nhật ký theo owner_uid
│   │       ├── in_memory_pending_meal_photo_store.dart   # Hàng đợi ảnh chờ trong RAM (chỉ dùng mock/test)
│   │       ├── local_database_meal_log_repository.dart   # Adapter SQLite dùng LocalDatabase (entity_type = 'meal_log')
│   │       ├── local_database_pending_meal_photo_store.dart # Kho lưu bền vững SQLite (pending_meal_photos) theo owner_uid & log_id
│   │       ├── mock_meal_photo_services.dart             # MockMealPhotoPicker & InMemoryPrivateMealPhotoStorage
│   │       └── supabase_private_meal_photo_storage.dart  # Adapter bucket riêng tư 'meal-images' + retry idempotent khi mất phản hồi
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
    ├── meal_photo_processing_test.dart                   # Validate client/adapter, xóa EXIF JPEG/PNG/WebP, nén lặp (7 tests)
    ├── meal_resilience_offline_test.dart                 # Từ chối quyền, ảnh lỗi, SQLite bền vững qua restart, thiếu store (9 tests)
    ├── supabase_meal_photo_retry_test.dart               # Adapter Supabase + HTTP cục bộ: mất phản hồi, 409 Conflict vs Duplicate, 413/200, 429/500/unclassified, lỗi ghi SQLite sau 200 (7 tests)
    └── meal_ai_safety_boundary_test.dart                 # Không suy calo/dị nguyên từ ảnh, AI mở rộng không chặn lõi (5 tests)
```

---

## 2. Nguyên tắc kỹ thuật và an toàn đã áp dụng

1. **Gợi ý/đổi món & xác nhận tên món (`MealNutritionUseCase` + `MealSuggestionSession`)**:
   - Tái sử dụng trực tiếp `GetRecommendationsUseCase` (Issue #10) nên đổi món chỉ xoay vòng trong danh sách đã lọc cứng dị ứng/thành phần rõ ràng.
   - Bắt buộc người dùng nhập hoặc xác nhận `confirmedMealName` trước khi lưu (`userConfirmedName = true`).
2. **Validate ở app + giới hạn phía Storage, nén và xóa EXIF trước upload (`MealPhotoValidator`, `DefaultMealPhotoProcessor`, `MealPhotoStorage`, `20261125_000004_meal_images_bucket_limits.sql`)**:
   - Chỉ chấp nhận JPEG/PNG/WebP xác minh theo **magic bytes** và cấu trúc nhị phân hợp lệ (chặn tệp rỗng, tệp giả mạo đuôi `.jpg`, lệch MIME, ảnh hỏng).
   - Giới hạn ảnh gốc tối đa **10 MB**, ảnh sau xử lý/upload tối đa **1 MB**.
   - Xóa triệt để metadata EXIF/GPS/XMP/IPTC/Comment ở mức nhị phân cho JPEG (`APP1`/`APP13`/`COM`), PNG (`eXIf`/`tEXt`/`iTXt`/`zTXt`) và WebP (`EXIF`/`XMP ` + bit cờ `VP8X`), sau đó chạy nén lặp qua `MealPhotoCompressor` (nếu có) và xóa lại EXIF.
   - Adapter Storage (`SupabasePrivateMealPhotoStorage`) gọi lại `validateForUpload`, ép đường dẫn riêng tư `<owner_uid>/<log_id>.<ext>`, xử lý lỗi mất phản hồi HTTP thành `networkOffline` và chỉ chấp nhận nhánh đã tồn tại ở lần retry (`isRetry: true`) khi gặp lỗi trùng object xác định (`Duplicate`/`ResourceAlreadyExists`), không coi mọi HTTP `409 Conflict` hoặc lần upload đầu (`isRetry: false`) là đã upload.
   - Khi đồng bộ hàng đợi nhiều ảnh chờ (`retryPendingPhotoUploadsDetailed`), chỉ gỡ ảnh khỏi hàng đợi khi xác định đúng lỗi riêng của ảnh (`MealPhotoException`, `400`, `409` khác lỗi trùng object, `413`, `415`, `422`) để báo người dùng sửa và tiếp tục gửi các ảnh hợp lệ phía sau. Với lỗi mạng, `408`, `429`, mọi `5xx`, `401/403`, lỗi chưa phân loại hoặc lỗi ghi `image_path` vào SQLite sau khi upload `200`, hệ thống luôn giữ nguyên ảnh trong hàng đợi cho lần thử lại sau.
   - Phía Supabase Storage: đã bổ sung migration `supabase/migrations/20261125_000004_meal_images_bucket_limits.sql` đặt `public = false`, `file_size_limit = 1048576` (1 MB) và `allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']` cho bucket `meal-images`, giữ nguyên 4 chính sách RLS theo UID.
3. **Từ chối quyền / ảnh lỗi / mất mạng không mất nhật ký & bền vững qua khởi động lại app**:
   - `pickAndPreparePhoto` bắt mọi lỗi quyền Camera/Thư viện, không có camera, ảnh lỗi và chuyển về hướng dẫn nhập tay mà không xóa dữ liệu người dùng đang nhập.
   - `saveMealLogResilient` khi gặp mất mạng/mất phản hồi sẽ lưu ảnh sạch EXIF bền vững vào `LocalDatabasePendingMealPhotoStore` (bảng SQLite `pending_meal_photos` khóa chính `(owner_uid, log_id)`), lưu nhật ký vào `LocalDatabaseMealLogRepository` và đánh dấu `photoUploadStatus = pendingLocal`. Sau khi đóng rồi mở lại app, ảnh chờ và trạng thái `pendingLocal` vẫn được khôi phục đúng theo UID; khi retry thành công sẽ cập nhật `image_path` vào đúng `logId` cũ mà không tạo bản ghi trùng.
   - Khi không truyền `PendingMealPhotoStore` (hoặc lưu kho chờ thất bại), use case **không** báo ảnh chờ đồng bộ mà gán `photoQueuedForRetry = false`, `photoUploadStatus = failed` và thông báo rõ chỉ ghi được nhật ký nhập tay (chưa có ảnh).
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
  - `flutter test test/features/nutrition/ --no-pub`: **32/32** unit tests & widget tests đạt (bao gồm test mất phản hồi HTTP + retry `409 Duplicate`/`x-upsert`, chặn `409 Conflict` không phải lỗi trùng object, hàng đợi SQLite 2 ảnh gặp `413`/`200`, giữ nguyên hàng đợi khi gặp `429`/`500`/lỗi chưa phân loại và khi ghi SQLite lỗi sau upload `200`, lưu bền vững ảnh chờ SQLite qua đóng/mở lại app, báo đúng nhập tay khi không truyền store và chống lệch `ownerUid`/path traversal).
  - `flutter test --no-pub`: toàn bộ **128/128** tests của dự án trên nhánh này đạt.
- **Chưa kiểm tra:**
  - Luồng chụp/chọn ảnh thật, cấp/thu hồi quyền Camera và nén native trên thiết bị Android vật lý vẫn cần kiểm tra khi nối adapter phần cứng (`image_picker` / bộ nén native).
  - Migration giới hạn bucket `20261125_000004_meal_images_bucket_limits.sql` đã có trong mã nguồn nhưng cần phối hợp với Hà áp dụng lên project Supabase của nhóm và kiểm thử upload/xem signed URL trực tiếp với 3 tài khoản A/B/C (Issue #9).

---

## 4. Đề xuất phối hợp tích hợp

- **Với Trưởng (`@trggg2185` — `auth`, `profile`, `app/`):**
  - Gắn `MealLogComposerView` vào `_SessionNavigator` của `AuthGate` (đã hỗ trợ làm mới dữ liệu & xóa ảnh tạm khi đổi `ownerUid`); truyền `ownerUid` từ `AuthSession` và `RecommendationProfile` từ hồ sơ người dùng.
  - `SupabasePrivateMealPhotoStorage` yêu cầu truyền `currentOwnerUid` bắt buộc đồng nhất với `SupabaseSyncTransport` (commit `464d08b`), chặn truy cập/tải lên chéo tài khoản.
  - Khi đăng xuất/đổi tài khoản, gọi `pendingPhotoStore.clearForOwner(oldUid)` hoặc xử lý hàng đợi chờ rõ ràng theo quy định bảo mật.
- **Với Hà (`@HanHoangHa` — `supabase/migrations`, `LocalDatabase`):**
  - `MealLog.toSupabasePayload()` đã khớp các cột `meal_id`, `meal_name`, `image_path`, `consumed_at`, `note` của bảng `public.meal_logs`, tương thích `LocalDatabase` + `LocalSyncWorker` (`entity_type = 'meal_log'`) và migration `20261123_000003_catalog_and_sync_integration.sql` (`p_expected_owner_uid` + trigger `advance_log_version`). Lưu ý khi ghi trực tiếp lần đầu lên `meal_logs` cần bảo đảm đã có hàng tối thiểu trong `public.profiles` (tương tự `SupabaseHabitRepository`).
  - Đã thêm migration `supabase/migrations/20261125_000004_meal_images_bucket_limits.sql` đặt `public = false`, `file_size_limit = 1048576` (1 MB) và `allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']` cho bucket `'meal-images'`, giữ nguyên 4 chính sách RLS theo UID. Nhờ Hà áp dụng migration này lên project Supabase của nhóm để thực thi giới hạn trực tiếp phía Storage.
