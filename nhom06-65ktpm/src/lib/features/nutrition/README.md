# Module `nutrition` — Nhật ký bữa ăn và camera với ảnh riêng tư (Issue #11)

- **Người phụ trách:** Nguyễn Đăng Đại (`@nddai0710`)
- **Review chéo:** Nguyễn Thế Trưởng (`@trggg2185`)
- **Nhánh phát triển:** `feature/nhom06/nutrition` (base PR nội bộ: `nhom06-65ktpm`)
- **Phụ thuộc phối hợp:** Issue #7 (`LocalDatabase`, `public.meal_logs`, bucket riêng tư `meal-images`) và Issue #10 (`GetRecommendationsUseCase`, `MealCatalogItem`, `RecommendationProfile`).
- Sau khi đăng nhập bằng tài khoản có quyền dữ liệu, chọn **Mở nhật ký bữa ăn**. Gợi ý dùng hồ sơ hiện tại và chờ xác nhận dị ứng. Bạn vẫn có thể nhập tay nếu hồ sơ chưa đủ hoặc ảnh bị lỗi.
- Trên Android, chụp hoặc chọn ảnh bằng `image_picker`. Ảnh được đổi kích thước và nén trên thiết bị. SQLite giữ nhật ký và ảnh đã xử lý theo UID khi mất kết nối. Chọn **Đồng bộ nhật ký** hoặc **Thử đồng bộ … ảnh đang chờ** để gửi lại.
- Trên Web, ứng dụng tải và lưu nhật ký trên Supabase. Khi mất mạng form giữ nội dung đang nhập để thử lại. Trình duyệt có thể cung cấp trình chọn tệp thay cho camera.
- Mở ảnh từ nhật ký bằng URL ký ngắn hạn. Ảnh nằm trong bucket riêng tư.

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
2. **Validate ở app + giới hạn phía Storage, nén và xóa EXIF trước upload (`MealPhotoValidator`, `DefaultMealPhotoProcessor`, `MealPhotoStorage`, `20261125000004_meal_images_bucket_limits.sql`)**:
   - Chỉ chấp nhận JPEG/PNG/WebP xác minh theo **magic bytes** và cấu trúc nhị phân hợp lệ (chặn tệp rỗng, tệp giả mạo đuôi `.jpg`, lệch MIME, ảnh hỏng).
   - Giới hạn ảnh gốc tối đa **10 MB**, ảnh sau xử lý/upload tối đa **1 MB**.
   - Xóa triệt để metadata EXIF/GPS/XMP/IPTC/Comment ở mức nhị phân cho JPEG (`APP1`/`APP13`/`COM`), PNG (`eXIf`/`tEXt`/`iTXt`/`zTXt`) và WebP (`EXIF`/`XMP ` + bit cờ `VP8X`), sau đó chạy nén lặp qua `MealPhotoCompressor` (nếu có) và xóa lại EXIF.
   - Adapter Storage (`SupabasePrivateMealPhotoStorage`) gọi lại `validateForUpload`, ép đường dẫn riêng tư `<owner_uid>/<log_id>.<ext>`, xử lý lỗi mất phản hồi HTTP thành `networkOffline` và chỉ chấp nhận nhánh đã tồn tại ở lần retry (`isRetry: true`) khi gặp lỗi trùng object xác định (`Duplicate`/`ResourceAlreadyExists`), không coi mọi HTTP `409 Conflict` hoặc lần upload đầu (`isRetry: false`) là đã upload.
   - Khi đồng bộ hàng đợi nhiều ảnh chờ (`retryPendingPhotoUploadsDetailed`), chỉ gỡ ảnh khỏi hàng đợi khi xác định đúng lỗi riêng của ảnh (`MealPhotoException`, `400`, `409` khác lỗi trùng object, `413`, `415`, `422`) để báo người dùng sửa và tiếp tục gửi các ảnh hợp lệ phía sau. Với lỗi mạng, `408`, `429`, mọi `5xx`, `401/403`, lỗi chưa phân loại hoặc lỗi ghi `image_path` vào SQLite sau khi upload `200`, hệ thống luôn giữ nguyên ảnh trong hàng đợi cho lần thử lại sau.
   - Phía Supabase Storage: đã bổ sung migration `supabase/migrations/20261125000004_meal_images_bucket_limits.sql` đặt `public = false`, `file_size_limit = 1048576` (1 MB) và `allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']` cho bucket `meal-images`, giữ nguyên 4 chính sách RLS theo UID.
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

### Kiểm thử Android thật và backend

- Trên Android thật, thử chụp/chọn ảnh, từ chối quyền, bỏ ảnh để lưu nhập tay, và ngắt mạng sau khi mở nhật ký. Mở lại với cùng tài khoản, kiểm tra bản ghi và gửi ảnh chờ. Dùng tài khoản thử thứ hai để xác nhận dữ liệu được cô lập.
- Migration [giới hạn bucket](../../../supabase/migrations/20261125000004_meal_images_bucket_limits.sql) đặt chế độ riêng tư, giới hạn 1 MiB và MIME JPEG, PNG, WebP. Sau khi áp dụng trên project nhóm, thử tệp sai định dạng hoặc vượt dung lượng và xác nhận Storage từ chối. Kiểm tra việc mở ảnh bằng URL ký ngắn hạn.
