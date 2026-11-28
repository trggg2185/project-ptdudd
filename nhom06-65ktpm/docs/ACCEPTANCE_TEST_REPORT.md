# Báo cáo Tổng hợp Kiểm thử Nghiệm thu & Lỗi Còn lại — HealthyLife (Nhóm 06)

- **Phụ trách tổng hợp (Issue #12):** Nguyễn Đăng Đại (`@nddai0710`)
- **Review chéo:** Nguyễn Thế Trưởng (`@trggg2185`)
- **Ngày cập nhật số liệu:** `27/11/2026`
- **Cơ sở mã nguồn đo kiểm:** Nhánh `feature/nhom06/insights` (tách từ `nhom06-65ktpm` tại `d5a16f3`, bổ sung tiêu chí 1–2 của Issue #12 tại `82d6aa8` và `86f8e6a`).
- **Thư mục minh chứng ảnh demo:** [`docs/demo/README.md`](demo/README.md) (`demo/android/`, `demo/web/`).

> **Nguyên tắc ghi nhận trung thực:** Báo cáo chỉ công bố số liệu từ các lệnh và phép thử đã thực sự chạy. Những hạng mục chạy bằng mock/fixture/SQLite FFI được tách bạch rõ với kiểm thử trên **Android thật**, **Web trực tuyến** và **Firebase/Supabase cloud**.

---

## 1. Tóm tắt kết quả kiểm chứng thực tế đã chạy

| Hạng mục kiểm tra | Lệnh thực thi (`nhom06-65ktpm/src`) | Kết quả thực tế | Ghi chú phạm vi |
| --- | --- | --- | --- |
| Phân tích tĩnh (Static Analysis) | `flutter analyze --no-pub` | **Đạt — 0 issues** (`1.4s`) | Toàn bộ `lib/` và `test/` trong `src/`. |
| Kiểm thử tự động Unit & Widget | `flutter test --no-pub` | **Đạt — 189/189 ca** (`0` thất bại, `0` bỏ qua) | Chạy trên **28 tệp test**; dùng mock/fixture, SQLite FFI và HTTP loopback cục bộ (không gọi Firebase/Supabase cloud). |
| Biên dịch Web | `flutter build web --no-pub` | **Đạt** (`√ Built build\web`, `37.5s`) | Xác nhận biên dịch Web không lỗi trên mã hiện hành. |
| Biên dịch Android Debug APK | `flutter build apk --debug --no-pub` | **Đạt** (`√ Built build\app\outputs\flutter-apk\app-debug.apk`, `34.8s`) | Xác nhận biên dịch APK debug cho cả `lib/main.dart` và bản xem trước `weekly_insights_demo_main.dart`. |
| Kiểm thử tích hợp (`integration_test/`) | `flutter test integration_test` | **Chưa có kịch bản (`0/0`)** | Thư mục `src/integration_test/` hiện chỉ có `.gitkeep`. |
| Demo & ảnh chụp Android | `adb -s emulator-5554` (`Android 17 / API 37`) | **Đã chụp `3` ảnh trên Android Emulator; `0` ảnh điện thoại vật lý** | Đã chụp màn hình đăng nhập chính (`01_auth_login_emulator.png`) và 2 màn hình Dashboard 1 cột (`07`, `08`, dữ liệu fixture mẫu). Các màn hình sau đăng nhập, GPS ngoài trời và camera phần cứng vẫn cần **điện thoại Android thật**. |
| Demo & ảnh chụp Web (Chrome) | Chrome `158.0.8127.38` (`1280px`) | **Đã chụp `2` ảnh Web; còn `4` ảnh sau đăng nhập** | Đã chụp màn hình đăng nhập chính (`01_auth_login_web.png`) và Dashboard 2 cột (`06_insights_dashboard_2col.png`, dữ liệu fixture mẫu). Các màn hình sau đăng nhập (`02..05`) chờ phiên đăng nhập tài khoản thử trên Chrome. |

---

## 2. Số ca kiểm thử tự động đạt / tổng theo từng module (Issue #1–#12)

| Issue | Module | Phụ trách | Số tệp test | Đạt / Tổng | Tệp test chi tiết | Phạm vi đã kiểm chứng & giới hạn |
| --- | --- | --- | ---: | ---: | --- | --- |
| **#1** | `auth` | `@trggg2185` | 2 | **11 / 11** | `auth_flow_test.dart` (6), `firebase_access_token_test.dart` (5) | Form đăng nhập/đăng ký/đặt lại mật khẩu, Google bị hủy, hết phiên, trạng thái claim, đổi tài khoản khi lấy JWT. Luồng email đã thử Chrome thật ở PR #1; Google Sign-In Android thật còn cần SHA-1 từng máy. |
| **#2** | `profile` | `@trggg2185` | 3 | **11 / 11** | `profile_domain_test.dart` (7), `profile_page_test.dart` (3), `supabase_profile_repository_test.dart` (1) | Xác nhận 18+, dị ứng, ca đêm `22:00–06:00`, lặp tuần, ngày ngoại lệ, DST, lịch thủ công và adapter Supabase giả lập. |
| **#3** | `planner` | `@trggg2185` | 0 | **0 / 0** *(Chưa tích hợp)* | *(chưa merge vào `nhom06-65ktpm`)* | Thư mục `lib/features/planner/` trên nhánh nhóm mới có khung `.gitkeep`. |
| **#4** | `habits` | `@pvduc05` | 4 | **36 / 36** | `habit_frequency_test.dart` (5), `habit_pages_test.dart` (10), `habit_repository_test.dart` (8), `streak_calculator_test.dart` (13) | CRUD thói quen, tần suất, ngày nghỉ không phá streak, sửa lịch áp dụng từ ngày sau, không đếm trùng ngày địa phương. UI hiện lưu trực tuyến Supabase. |
| **#5** | `sleep` | `@pvduc05` | 3 | **24 / 24** | `sleep_pages_test.dart` (10), `sleep_repository_test.dart` (5), `sleep_schedule_analyzer_test.dart` (9) | Nhập giờ ngủ qua nửa đêm & ca đêm ban ngày, chặn tương lai/chồng lấn/>24h, khoảng ngủ mong muốn, responsive 1 cột (390px) / 2 cột (1280px), Semantics & phím tắt, xử lý conflict qua `SyncTransport` giả lập. Migration `20261125000005` chưa chạy lên cloud. |
| **#6** | `notifications` | `@pvduc05` | 0 | **0 / 0** *(Chưa tích hợp)* | *(chưa merge vào `nhom06-65ktpm`)* | Thư mục `lib/features/notifications/` trên nhánh nhóm mới có khung `.gitkeep`. |
| **#7** | `core` (SQLite & Sync) | `@HanHoangHa` | 2 | **14 / 14** | `local_database_test.dart` (8), `local_sync_worker_test.dart` (6) | Hàng đợi SQLite FFI phân vùng theo `owner_uid`, retry cùng UUID idempotent, coalesce, phát hiện conflict `base_version`, cô lập khi đổi tài khoản. API/RLS Supabase cơ bản đã kiểm tra ở đợt #7 bằng 2 tài khoản thử. |
| **#8** | `activity` (GPS) | `@HanHoangHa` | 2 | **13 / 13** | `activity_page_test.dart` (3), `activity_session_tracker_test.dart` (10) | `Start/Pause/Resume/Stop`, bỏ qua điểm sai số `> 30m`, Haversine không cộng lúc Pause, dừng khi ra nền, fallback nhập tay, tùy chọn lưu tuyến. Chưa có biên bản đo sai số GPS ngoài trời trên Android thật. |
| **#9** | `privacy` (3 tài khoản & xóa dữ liệu) | `@HanHoangHa` | 0 | **0 / 0** *(Chưa tích hợp)* | *(chưa thực hiện / chưa merge)* | Cần kiểm thử truy cập chéo 3 tài khoản A/B/C trên toàn bộ bảng/bucket thật và quy trình xóa tài khoản/ảnh/tuyến đường. |
| **#10** | `recommendations` | `@nddai0710` | 4 | **35 / 35** | `catalog_fixture_test.dart` (4), `catalog_hard_filter_test.dart` (13), `recommendation_engine_test.dart` (6), `recommendation_acceptance_test.dart` (12) | Danh mục 10 môn tập + 10 món ăn có nguồn WHO đồng bộ Fixture/JSON/SQL, lọc cứng 18+/chuyên môn/dị ứng/thành phần rõ/thiết bị, xếp hạng có giải thích và không nới ràng buộc. Chưa nối `AuthGate`/Supabase trực tiếp. |
| **#11** | `nutrition` | `@nddai0710` | 6 | **34 / 34** | `meal_nutrition_flow_test.dart` (4), `meal_photo_processing_test.dart` (7), `meal_resilience_offline_test.dart` (9), `meal_runtime_adapters_test.dart` (2), `supabase_meal_photo_retry_test.dart` (7), `meal_ai_safety_boundary_test.dart` (5) | Đổi món, xác nhận tên món, validate magic bytes/MIME/kích thước, xóa EXIF nhị phân JPEG/PNG/WebP, nén ảnh, hàng đợi ảnh SQLite bền vững qua restart, giữ ảnh chờ khi 429/5xx/lỗi ghi SQLite sau upload 200, loại ảnh riêng khi 413/415/409 chung, không suy calo/dị nguyên từ ảnh. Migration `20261125000004` chưa áp dụng lên cloud; chưa chụp demo Android thật. |
| **#12** | `insights` (Dashboard) | `@nddai0710` | 2 | **11 / 11** | `weekly_insights_aggregator_test.dart` (5), `weekly_insights_dashboard_test.dart` (6) | Tổng hợp tỷ lệ hoàn thành, streak xuyên tuần, thời lượng tập và giấc ngủ tự ghi theo tuần (Mon–Sun); phân biệt `Chưa ghi nhận` vs `Không hoàn thành`; hiển thị nguồn nhập tay/GPS/camera; kiểm tra quét toàn cây widget không gọi là *"điểm sức khỏe"*; responsive 390px/1280px; cô lập & xóa cache khi đổi `ownerUid`. Chưa gắn vào `AuthGate` (chờ nhóm trưởng tích hợp). |
| **Tổng** | **9/12 module có test** | **4 thành viên** | **28** | **189 / 189** | **100% test tự động đạt** | **3 module (#3, #6, #9) chưa tích hợp; kiểm thử Android thật, Web demo có ảnh và 2 migration cloud đang chờ hoàn tất.** |

---

## 3. Bảng chi tiết Test Cases nghiệm thu (theo Mục 10.2 Đề cương)

Quy ước trạng thái:
- **Đạt (Tự động):** Đã xác minh bằng `flutter test --no-pub` (unit/widget/SQLite FFI/HTTP cục bộ).
- **Đạt một phần:** Logic tự động đã đạt, còn thiếu bước xác minh trên thiết bị thật / trình duyệt có đăng nhập / Supabase cloud.
- **Chờ thực hiện:** Đã có mã nguồn/hướng dẫn nhưng chưa chạy kiểm thử thủ công trên máy thật hoặc cloud.
- **Chưa tích hợp:** Thuộc issue chưa merge vào nhánh nhóm `nhom06-65ktpm`.

| Mã ca | Hạng mục / Issue | Kịch bản kiểm thử nghiệm thu | Loại kiểm thử | Trạng thái | Bằng chứng / Ghi chú |
| --- | --- | --- | --- | --- | --- |
| `TC-01` | Auth (#1) | Đăng nhập sai mật khẩu giữ ở màn hình login, ẩn chi tiết server; quên mật khẩu dùng phản hồi trung tính; hủy Google không crash. | Unit/Widget + Chrome thật | **Đạt một phần** | `auth_flow_test.dart` (6/6) đạt; luồng email đã xác minh trên Chrome ở PR #1; Google Android thật cần SHA-1 máy thử. |
| `TC-02` | Auth / JWT (#1) | Chặn request Supabase khi thiếu claim `role: authenticated`, đổi tài khoản giữa chừng hoặc `sub` không khớp phiên. | Unit + Chrome thật | **Đạt (Tự động)** | `firebase_access_token_test.dart` (5/5) đạt; đã xác minh trên Firebase–Supabase project nhóm ở PR #1. |
| `TC-03` | Profile (#2) | Bắt buộc 18+, múi giờ IANA; dị ứng chưa xác nhận khóa gợi ý món; hỗ trợ ca đêm `22:00–06:00`, lặp tuần, ngày ngoại lệ, DST và lịch thủ công. | Unit/Widget | **Đạt (Tự động)** | `profile_domain_test.dart` (7/7), `profile_page_test.dart` (3/3), `supabase_profile_repository_test.dart` (1/1). |
| `TC-04` | Gợi ý (#10) | Loại mọi món chứa dị nguyên/nguyên liệu cần tránh hoặc `!ingredients_clear`; không có ứng viên thì trả trống, không nới ràng buộc. | Unit/Widget | **Đạt (Tự động)** | `catalog_hard_filter_test.dart` (13/13), `recommendation_acceptance_test.dart` (12/12). |
| `TC-05` | Gợi ý (#10) | Loại bài tập thiếu thiết bị / vượt thời lượng / vi phạm giới hạn vận động; hiển thị lý do cụ thể & lựa chọn thay thế; danh mục có nguồn WHO đồng bộ Fixture/JSON/SQL. | Unit/Widget | **Đạt (Tự động)** | `catalog_fixture_test.dart` (4/4), `recommendation_engine_test.dart` (6/6). |
| `TC-06` | Planner (#3) | Xếp lịch ca đêm `22:00–06:00`, lịch bận chồng nhau, thiếu khoảng trống, mục đã khóa, đổi ca/múi giờ; không xếp chồng và không sửa lịch đã hoàn thành. | Unit/Widget | **Chưa tích hợp** | Chờ PR Issue #3 (`feature/nhom06/planner`) hoàn thiện review và merge vào `nhom06-65ktpm`. |
| `TC-07` | Habits (#4) | Ngày nghỉ/chưa tới hạn không phá streak; sửa lịch lặp chỉ có hiệu lực từ ngày tiếp theo; mỗi ngày địa phương chỉ có một kết quả check-in. | Unit/Widget | **Đạt (Tự động)** | `habit_frequency_test.dart` (5/5), `streak_calculator_test.dart` (13/13), `habit_repository_test.dart` (8/8), `habit_pages_test.dart` (10/10). |
| `TC-08` | Sleep (#5) | Giấc ngủ qua nửa đêm (`23:30 → 07:00`) và ngủ ban ngày ca đêm (`07:45 → 14:45`); chặn tương lai/chồng lấn/>24h; ngày chưa ghi hiển thị trung tính `—`. | Unit/Widget | **Đạt một phần** | `sleep_schedule_analyzer_test.dart` (9/9), `sleep_repository_test.dart` (5/5), `sleep_pages_test.dart` (10/10); migration DB `20261125000005` chưa chạy lên cloud. |
| `TC-09` | Sleep UI (#5) | Responsive 1 cột Android (`390px`) và 2 cột Web (`1280px`), đầy đủ `Semantics` và phím tắt bàn phím. | Widget + Thiết bị thật | **Đạt một phần** | `sleep_pages_test.dart` đạt; chờ ảnh chụp xác nhận trên Android thật & Chrome Web. |
| `TC-10` | Notifications (#6) | Nhắc theo lịch đã duyệt, giờ yên lặng, sửa/xóa lịch hủy nhắc cũ, đăng xuất không nhắc tài khoản cũ, xử lý tắt quyền & khởi động lại thiết bị. | Unit + Android thật | **Chưa tích hợp** | Chờ triển khai và merge Issue #6. |
| `TC-11` | GPS Logic (#8) | `Start/Pause/Resume/Stop`, bỏ qua điểm sai số `> 30m`, Haversine không cộng quãng đường lúc Pause, dừng GPS khi ra nền, fallback nhập tay, tùy chọn lưu tuyến. | Unit/Widget | **Đạt (Tự động)** | `activity_session_tracker_test.dart` (10/10), `activity_page_test.dart` (3/3). |
| `TC-12` | GPS Android thật (#8) | Chạy phiên ngoài trời trên điện thoại Android thật: bật Location, Pause ≥ 30 giây, đưa app ra nền xác nhận GPS dừng, từ chối quyền xác nhận nhập tay, ghi sai số quan sát. | Android thật | **Chờ thực hiện** | Chưa có thiết bị Android kết nối; chưa có số liệu sai số thực địa. |
| `TC-13` | Nutrition / Camera (#11) | Đổi món từ gợi ý đã lọc dị ứng, bắt buộc xác nhận tên món; validate magic bytes/MIME/size (≤10MB gốc, ≤1MB upload); xóa EXIF nhị phân JPEG/PNG/WebP. | Unit/Widget | **Đạt (Tự động)** | `meal_nutrition_flow_test.dart` (4/4), `meal_photo_processing_test.dart` (7/7), `meal_runtime_adapters_test.dart` (2/2). |
| `TC-14` | Nutrition Offline & Retry (#11) | Từ chối quyền camera/ảnh lỗi vẫn nhập tay; mất mạng lưu nhật ký + ảnh chờ vào SQLite bền vững qua restart; retry giữ ảnh khi `429`/`5xx`/lỗi ghi SQLite sau `200`, chỉ bỏ ảnh riêng khi `413`/`415`/`409` chung. | Unit/Widget + HTTP cục bộ | **Đạt một phần** | `meal_resilience_offline_test.dart` (9/9), `supabase_meal_photo_retry_test.dart` (7/7); còn cần kiểm thử camera/ngắt mạng trực tiếp trên Android thật và áp dụng migration `20261125000004` trên cloud. |
| `TC-15` | Nutrition AI Safety (#11) | Không suy ra calo hoặc khẳng định không dị nguyên từ ảnh; AI mở rộng tắt mặc định và không tự ghi đè tên món người dùng. | Unit/Widget | **Đạt (Tự động)** | `meal_ai_safety_boundary_test.dart` (5/5). |
| `TC-16` | Sync / SQLite (#7) | Offline rồi online gửi bằng cùng operation UUID (idempotent), coalesce sửa offline, phát hiện xung đột `base_version`, đổi tài khoản không đẩy hàng đợi tài khoản cũ. | Unit (SQLite FFI) | **Đạt một phần** | `local_database_test.dart` (8/8), `local_sync_worker_test.dart` (6/6); còn cần nối hoàn chỉnh vào UI các module ngoài `nutrition` và thử integration trực tiếp với Supabase. |
| `TC-17` | Bảo mật 3 tài khoản (#9) | Tài khoản A/B độc lập, tài khoản C thử đọc/sửa/xóa ID bản ghi và URL ảnh của A trên Database/Storage thật; kiểm tra xóa ảnh, xóa tài khoản và dọn cache khi đăng xuất. | Supabase Cloud + E2E | **Chưa tích hợp** | Đã có kiểm thử API 2 tài khoản ở đợt #7 (`src/README.md`); bài kiểm thử đầy đủ 3 tài khoản A/B/C và xóa tài khoản thuộc Issue #9 (chưa thực hiện). |
| `TC-18` | Dashboard tổng hợp (#12) | Tổng hợp tỷ lệ hoàn thành, streak xuyên tuần, thời lượng tập (tách GPS vs nhập tay) và giấc ngủ tự ghi theo tuần (Mon–Sun); hỗ trợ ca đêm, khử trùng lặp, cô lập `ownerUid`. | Unit/Integration (Repo) | **Đạt (Tự động)** | `weekly_insights_aggregator_test.dart` (5/5) gồm kiểm thử kết nối `CompositeWeeklyInsightsSource` với các repo `#4`, `#5`, `#8`, `#11`. |
| `TC-19` | Dashboard minh bạch (#12) | Phân biệt rõ `Chưa ghi nhận` với `Không hoàn thành` (tuần trống không ép 0% hay 0h ngủ); hiển thị nguồn nhập tay/thiết bị; quét toàn cây widget xác nhận tuyệt đối không gọi là *"điểm sức khỏe"*. | Unit/Widget | **Đạt (Tự động)** | `weekly_insights_dashboard_test.dart` (6/6). |
| `TC-20` | Dashboard Responsive & Session (#12) | Bố cục 1 cột Android (`390px`, không overflow) và 2 cột Web (`1280px`), điều hướng tuần, nút `Thử lại` khi lỗi và xóa cache khi đổi `ownerUid`. | Widget + Emulator/Web | **Đạt một phần** | `weekly_insights_dashboard_test.dart` đạt; đã chụp minh chứng 1 cột trên Android Emulator (`07`, `08`) và 2 cột trên Chrome Web (`06`) bằng fixture mẫu; chờ nhóm trưởng gắn `WeeklyInsightsPage` vào `AuthGate`. |
| `TC-21` | Chất lượng & Build (#12) | `flutter analyze --no-pub` không lỗi; `flutter test --no-pub` đạt 100%; `flutter build web --no-pub` và `flutter build apk --debug --no-pub` thành công. | CLI Build/Test | **Đạt** | Đã chạy thực tế ngày `27/11/2026`: `0 issues`, `189/189` test đạt, `build/web` và `app-debug.apk` đều thành công. |
| `TC-22` | Demo Android thật & Web (#12) | Chụp đủ bộ ảnh minh chứng chạy thực tế trên điện thoại Android thật (`docs/demo/android/`) và trình duyệt Web Chrome (`docs/demo/web/`). | Manual E2E | **Đạt một phần** | Đã có **5 ảnh thực tế** (`3` ảnh Android Emulator + `2` ảnh Chrome Web trong [`docs/demo/README.md`](demo/README.md)); còn thiếu ảnh các màn hình sau đăng nhập tài khoản thử và kiểm chứng GPS/camera trên **điện thoại Android vật lý**. |

---

## 4. Danh sách lỗi, vướng mắc và giới hạn còn lại

| Mã | Mức độ | Mô tả lỗi / giới hạn còn lại | Ảnh hưởng | Phụ trách / Phối hợp | Hướng xử lý tiếp theo |
| --- | --- | --- | --- | --- | --- |
| `DEF-01` | **P1** | **Bucket `meal-images` trên Supabase cloud chưa áp dụng giới hạn dung lượng/MIME:** Truy vấn chỉ đọc của nhóm trưởng lúc review PR #20 xác nhận `public = false` đã đúng, nhưng `file_size_limit` và `allowed_mime_types` vẫn là `null` do migration `20261125000004_meal_images_bucket_limits.sql` chưa chạy lên project cloud `vspyxavkdqqlpxodvqvb`. | Tầng Storage server chưa tự chặn tệp > 1 MiB hoặc MIME ngoài JPEG/PNG/WebP nếu client gọi trực tiếp API. | `@HanHoangHa` / `@trggg2185` (phối hợp `@nddai0710`) | Áp dụng migration `20261125000004` lên project Supabase nhóm, sau đó chạy lại phép thử upload tệp sai định dạng / > 1 MiB. |
| `DEF-02` | **P1** | **Migration ràng buộc giấc ngủ `20261125000005` chưa áp dụng lên Supabase cloud:** Ràng buộc tối đa 24h, trigger chống tương lai/chồng lấn `sleep_logs` và RPC nguyên tử `upsert_sleep_window` mới có trong file migration cục bộ. | `SupabaseSleepRepository` đang dùng nhánh fallback compare-and-swap cho `sleep_window` và DB cloud chưa chặn bản ghi chồng lấn/tương lai ở tầng SQL. | `@HanHoangHa` / `@pvduc05` | Review và áp dụng migration `20261125000005` lên Supabase cloud, kiểm tra RPC với JWT thật. |
| `DEF-03` | **P1** | **Chưa tích hợp đầy đủ luồng chính và còn 3 issue chưa merge vào `nhom06-65ktpm`:** `planner` (#3), `notifications` (#6) và kiểm thử 3 tài khoản/xóa dữ liệu (#9) chưa merge; `recommendations` (#10) và `insights` (#12) đã sẵn sàng widget độc lập nhưng chưa gắn vào `AuthGate`/`main.dart`. | Chưa chạy được trọn vẹn hành trình khép kín `đăng nhập → hồ sơ → gợi ý → duyệt lịch → nhắc/ghi nhận → tổng kết tuần` trên bản build chính. | `@trggg2185` (tích hợp `AuthGate` & #3), `@pvduc05` (#6), `@HanHoangHa` (#9) | Sau khi PR các issue được review & merge, nhóm trưởng nối `RecommendationPreviewView` và `WeeklyInsightsPage` vào `AuthGate` cùng `CompositeWeeklyInsightsSource`. |
| `DEF-04` | **P2** | **Đồng bộ ngoại tuyến SQLite và UI xử lý xung đột chưa đồng bộ toàn app:** `LocalSyncWorker` đã gắn vào `nutrition` (Android), nhưng `habits`, `sleep`, `activity` chưa gắn hàng đợi offline SQLite kèm retry scheduler tự động và dialog chọn bản (`keepLocalChanges` / `acceptServerChange`) trên UI; Web nghiệm thu trực tuyến (chưa có adapter offline). | Khi mất mạng trên Android, thao tác tạo/sửa ở `habits`, `sleep`, `activity` vẫn yêu cầu kết nối mạng. | `@HanHoangHa` phối hợp `@pvduc05`, `@trggg2185` | Tích hợp `LocalSyncWorker` + UI giải quyết xung đột theo phạm vi ưu tiên sau khi hoàn tất luồng chính. |
| `DEF-05` | **P2** | **Thiếu kiểm thử tích hợp tự động (`integration_test/`) và minh chứng thiết bị vật lý/sau đăng nhập:** Chưa có kịch bản trong `src/integration_test/`; mới chụp được `5` ảnh (màn hình đăng nhập & Dashboard fixture trên Android Emulator + Chrome Web), chưa có ảnh các màn hình sau đăng nhập và chưa đo GPS ngoài trời / camera trên **điện thoại Android vật lý**. | Chưa thể khép hoàn toàn tiêu chí nghiệm thu thực địa của đề cương mục 10.2 và Issue #12 trước khi nộp bài cho giảng viên. | Cả nhóm (chủ trì tổng hợp `@nddai0710`) | Đăng nhập tài khoản thử trên Chrome (`localhost:5000`) và cắm điện thoại Android vật lý (bật Location, Camera, tắt/bật mạng) để bổ sung ảnh sau đăng nhập và số liệu sai số GPS vào `docs/demo/` và báo cáo này. |

---

## 5. Phạm vi tính năng mở rộng (AI / Health Connect)

Theo đúng yêu cầu Đề cương mục 3.3 và Issue #12:
- **AI đề xuất nhãn món ăn** và **Health Connect đọc bước chân** **chưa triển khai** ở bản cốt lõi vì các hạng mục cốt lõi (`DEF-01`–`DEF-05`, đặc biệt `#3`, `#6`, `#9` và demo Android thật) chưa hoàn tất nghiệm thu.
- Module `nutrition` chỉ giữ giao diện mở rộng tùy chọn (`OptionalMealLabelSuggester`, mặc định tắt) để bảo đảm không ảnh hưởng luồng cốt lõi.
