# Minh chứng ảnh demo Android và Web — HealthyLife (Nhóm 06)

Thư mục này lưu ảnh chụp màn hình nghiệm thu thực tế trên **Android** (`android/`) và **trình duyệt Web** (`web/`) phục vụ **Issue #12** và báo cáo cuối kỳ.

> **Nguyên tắc bảo mật và trung thực (`src/AGENTS.md`):**
> - Chỉ dùng **tài khoản thử** và **dữ liệu mẫu/kiểm thử**; **không** chụp lộ email cá nhân thật, mật khẩu, JWT/token, ảnh nhạy cảm, tọa độ GPS thật nơi ở hoặc dữ liệu sức khỏe thật.
> - Phân biệt trung thực giữa ảnh chụp từ **Android Emulator** với **điện thoại Android thật** (phần GPS ngoài trời và camera phần cứng bắt buộc xác minh trên điện thoại vật lý), và ghi rõ ảnh nào chạy từ **dữ liệu fixture mẫu (mock)** so với **backend Firebase–Supabase thật**.
> - Không commit file nhị phân `.apk` / `.ipa` hoặc thư mục `build/` vào kho mã nguồn.

---

## 1. Danh mục ảnh đã chụp thực tế (`27/11/2026`)

### Android Emulator (`sdk gphone16k x86_64`, Android 17 / API 37 — `emulator-5554`)

| Tệp ảnh | Nguồn chạy | Mô tả nội dung đã xác minh |
| --- | --- | --- |
| [`android/01_auth_login_emulator.png`](android/01_auth_login_emulator.png) | `lib/main.dart` (Firebase + Supabase thật) | Màn hình đăng nhập HealthyLife trên Android Emulator (`Email`, `Mật khẩu`, `Đăng nhập`, `Tiếp tục với Google`, `Quên mật khẩu?`, `Tạo tài khoản mới`). |
| [`android/07_insights_dashboard_1col_emulator.png`](android/07_insights_dashboard_1col_emulator.png) | `weekly_insights_demo_main.dart` (*fixture mẫu mock*) | Dashboard Tổng kết tuần bố cục **1 cột Android**: banner lưu ý phi y khoa, bộ chọn tuần, thẻ Thói quen & Streak (tách riêng `Hoàn thành`, `Bỏ qua có lý do`, `Không hoàn thành`, `Chưa ghi nhận`), thẻ Thời lượng tập (tách nguồn GPS vs Nhập tay). |
| [`android/08_insights_breakdown_1col_emulator.png`](android/08_insights_breakdown_1col_emulator.png) | `weekly_insights_demo_main.dart` (*fixture mẫu mock*) | Phần dưới Dashboard trên Android: chi tiết 7 ngày theo từng thói quen (`Ngày nghỉ / Tạm dừng`, `Không hoàn thành`, `Chưa ghi nhận (hôm nay)`) và ghi chú tổng kết tuần trung tính. |

### Web (Google Chrome `158.0.8127.38`, viewport desktop `1280px`)

| Tệp ảnh | Nguồn chạy | Mô tả nội dung đã xác minh |
| --- | --- | --- |
| [`web/01_auth_login_web.png`](web/01_auth_login_web.png) | `lib/main.dart` (Firebase + Supabase thật, `localhost:5000`) | Màn hình đăng nhập HealthyLife trên Chrome Web, hiển thị đầy đủ tiếng Việt, không lỗi bố cục. |
| [`web/06_insights_dashboard_2col.png`](web/06_insights_dashboard_2col.png) | `weekly_insights_demo_main.dart` (*fixture mẫu mock*) | Dashboard Tổng kết tuần bố cục **2 cột Web (`1280×1150`)**: đầy đủ 4 thẻ chỉ số có ghi rõ nguồn (`Nhập tay`, `Thiết bị (GPS trong phiên)`, `Tự khai báo`, `Camera / Thư viện ảnh`), bảng 7 ngày theo từng thói quen và ghi chú tổng kết tuần. |

---

## 2. Ảnh còn chờ bổ sung (sau đăng nhập tài khoản thử & trên điện thoại Android thật)

| Nền tảng | Tệp ảnh còn thiếu | Trạng thái | Điều kiện để chụp |
| --- | --- | --- | --- |
| **Android thật (thiết bị vật lý)** | `android/02_profile_schedule.png`, `03_habits_streak.png`, `04_sleep_routine_1col.png`, `05_activity_gps_or_manual.png`, `06_nutrition_camera_offline.png` | **Chờ thiết bị Android thật & đăng nhập tài khoản thử** | Cắm điện thoại Android thật (API 24+, Google Play, bật USB debugging), đăng nhập tài khoản thử có claim `role: authenticated`, thử GPS ngoài trời & Camera/offline SQLite. |
| **Web (Chrome sau đăng nhập)** | `web/02_profile_schedule.png`, `03_habits_streak.png`, `04_sleep_routine_2col.png`, `05_nutrition_online.png` | **Chờ đăng nhập tài khoản thử trên Chrome** | Chạy `flutter run -d chrome --web-port=5000`, đăng nhập tài khoản thử có claim `role: authenticated` rồi chụp lần lượt các màn hình đã tích hợp. |

---

## 3. Lệnh chạy lại để chụp bổ sung

Tất cả lệnh chạy từ thư mục `nhom06-65ktpm/src`:

### A. Chạy bản tích hợp chính trên Web (Chrome)

```powershell
cd nhom06-65ktpm/src
flutter pub get
flutter run -d chrome --web-port=5000
```

### B. Chạy bản tích hợp chính trên Android thật hoặc Emulator

```powershell
cd nhom06-65ktpm/src
flutter devices
flutter run -d <device-id>
```

### C. Xem trước độc lập Dashboard Tổng kết tuần (`insights`, dữ liệu fixture mẫu)

```powershell
cd nhom06-65ktpm/src
# Trên Web (Chrome):
flutter run -d chrome --web-port=5001 -t lib/features/insights/presentation/pages/weekly_insights_demo_main.dart
# Trên Android:
flutter run -d <device-id> -t lib/features/insights/presentation/pages/weekly_insights_demo_main.dart
```

Khi chụp bản dùng dữ liệu mẫu từ `weekly_insights_demo_main.dart`, luôn giữ nhãn chú thích *"Dữ liệu fixture mẫu (mock)"*, không gộp nhầm với dữ liệu cloud thật.
