# Module `insights` — Dashboard tổng kết tuần, kiểm thử nghiệm thu & báo cáo/demo (Issue #12)

- **Người phụ trách:** Nguyễn Đăng Đại (`@nddai0710`)
- **Review chéo:** Nguyễn Thế Trưởng (`@trggg2185`)
- **Nhánh phát triển:** `feature/nhom06/insights` (base PR nội bộ: `nhom06-65ktpm`)
- **Phụ thuộc phối hợp:** Issue `#4` (`HabitRepository`, `StreakCalculator`), Issue `#5` (`SleepRepository`, `SleepScheduleAnalyzer`), Issue `#8` (`ActivityRepository`) và Issue `#11` (`MealLogRepository`).
- **Tài liệu nghiệm thu liên quan:**
  - [Báo cáo tổng hợp kiểm thử nghiệm thu & lỗi còn lại](../../../../docs/ACCEPTANCE_TEST_REPORT.md)
  - [Minh chứng đóng góp thực tế theo lịch sử Git & PR](../../../../docs/CONTRIBUTION_EVIDENCE.md)
  - [Bộ ảnh minh chứng demo Android & Web](../../../../docs/demo/README.md)

---

## 1. Cấu trúc mã nguồn

```text
nhom06-65ktpm/
├── docs/
│   ├── ACCEPTANCE_TEST_REPORT.md                 # Bảng tổng hợp 189/189 test, 22 kịch bản TC và 5 lỗi/giới hạn còn lại
│   ├── CONTRIBUTION_EVIDENCE.md                  # Minh chứng commit, 8 PR đã merge và phân bổ kiểm thử theo thành viên
│   └── demo/
│       ├── README.md                             # Danh mục ảnh demo & hướng dẫn chụp thực tế
│       ├── android/                              # 3 ảnh chụp từ Android Emulator API 37 (Auth + Dashboard 1 cột)
│       └── web/                                  # 2 ảnh chụp từ Chrome Web 1280px (Auth + Dashboard 2 cột)
└── src/
    ├── lib/features/insights/
    │   ├── data/
    │   │   ├── fixtures/
    │   │   │   └── sample_weekly_insights_fixture.dart          # Fixture tuần mẫu & FixtureWeeklyInsightsSource (mock)
    │   │   └── repositories/
    │   │       └── composite_weekly_insights_source.dart        # Adapter tổng hợp trực tiếp từ các repo #4, #5, #8, #11
    │   ├── domain/
    │   │   ├── entities/
    │   │   │   ├── insight_data_source.dart                     # Nhãn nguồn dữ liệu (Nhập tay, Tự khai báo, GPS, Camera)
    │   │   │   └── weekly_insights_summary.dart                 # Mô hình tổng kết tuần & tuyên bố phi y khoa
    │   │   ├── repositories/
    │   │   │   └── weekly_insights_source.dart                  # Interface nguồn dữ liệu đầu vào theo tuần
    │   │   ├── services/
    │   │   │   ├── insights_display_formatter.dart              # Định dạng nhãn nguồn, ghi chú trung tính & chặn "điểm sức khỏe"
    │   │   │   └── weekly_insights_aggregator.dart              # Bộ tổng hợp tuần thuần Dart (Mon–Sun)
    │   │   └── usecases/
    │   │       └── get_weekly_insights_usecase.dart             # Use case lấy bản tổng kết tuần theo ownerUid
    │   ├── presentation/
    │   │   ├── controllers/
    │   │   │   └── weekly_insights_controller.dart              # ChangeNotifier điều hướng tuần, chống race condition, xóa cache khi đổi UID
    │   │   ├── pages/
    │   │   │   ├── weekly_insights_demo_main.dart               # Điểm chạy xem trước độc lập (mock fixture, không chạm main.dart)
    │   │   │   └── weekly_insights_page.dart                    # Màn hình độc lập sẵn sàng gắn vào AuthGate
    │   │   └── widgets/
    │   │       └── weekly_insights_dashboard_view.dart          # Dashboard responsive 1 cột (<760px) / 2 cột (>=760px)
    │   └── README.md
    └── test/features/insights/
        ├── weekly_insights_aggregator_test.dart                 # 5 unit/integration tests bộ tổng hợp & CompositeWeeklyInsightsSource
        └── weekly_insights_dashboard_test.dart                  # 6 unit/widget tests formatter, UI responsive, chống "điểm sức khỏe" & đổi UID
```

---

## 2. Nguyên tắc nghiệp vụ và minh bạch đã áp dụng

1. **Tổng hợp tuần chuẩn xác (`WeeklyInsightsAggregator` + `CompositeWeeklyInsightsSource`):**
   - Khung tuần chuẩn hóa **Thứ Hai – Chủ Nhật** theo ngày địa phương; tái sử dụng `StreakCalculator` (`#4`) và `SleepScheduleAnalyzer` (`#5`).
   - `CompositeWeeklyInsightsSource` tải lịch sử log thói quen tới `referenceDate` để bảo toàn **streak xuyên nhiều tuần**, và mở rộng biên truy vấn giấc ngủ `[weekStart - 1 .. weekEnd + 1]` để không mất đêm ngủ Chủ Nhật → Thứ Hai.
   - Cô lập chặt theo `ownerUid`, khử trùng lặp bản ghi, bỏ qua log tương lai, xử lý ngày trước `habit.createdAt` là `notApplicable`, và hỗ trợ cả giấc ngủ qua nửa đêm lẫn giấc ngủ ban ngày cho người làm ca đêm.
2. **Phân biệt rõ "Chưa ghi nhận" với "Không hoàn thành":**
   - Tách riêng 4 trạng thái thói quen: **Hoàn thành**, **Bỏ qua có lý do** (không phá streak), **Không hoàn thành** (tự đánh dấu thất bại rõ ràng) và **Chưa ghi nhận** (`unlogged` / `pendingToday`).
   - Tuần chưa có dữ liệu hiển thị trạng thái **Chưa ghi nhận**, tuyệt đối không ép thành `0%` hay `0 giờ ngủ`; trung bình giấc ngủ chỉ chia trên số ngày thực sự đã tự khai báo.
3. **Hiển thị nguồn dữ liệu & không gọi là "điểm sức khỏe":**
   - Mọi thẻ tổng kết đều ghi tường minh nguồn dữ liệu: `Nhập tay`, `Tự khai báo (không đo bằng cảm biến hay thời gian tắt màn hình)`, `Thiết bị (GPS trong phiên)`, `Camera / Thư viện ảnh`, và `Nguồn chưa xác định (bản ghi cũ)` cho các bản ghi vận động cũ có `estimated_distance_meters = 0`, `route_saved = false` trước migration.
   - Migration [`20261128000007_activity_input_source.sql`](../../../supabase/migrations/20261128000007_activity_input_source.sql) bổ sung cột nullable `input_source` (`'manual'` / `'gps'`) trên `public.activity_sessions` để lưu tường minh nguồn cho bản ghi mới (có fallback nếu cloud chưa áp dụng migration).
   - Có biểu ngữ lưu ý phi y khoa ở đầu màn hình và hàm bảo vệ `InsightsDisplayFormatter.containsForbiddenHealthScoreClaim`; widget test quét toàn bộ cây văn bản trên màn hình xác nhận không có tuyên bố *"điểm sức khỏe"* hay *"chấm điểm sức khỏe"*.
4. **Responsive, an toàn phiên & không chạm `main.dart`:**
   - Tự chuyển bố cục **1 cột** trên màn hình hẹp (`< 760px`, Android) và **2 cột** trên màn hình rộng (`>= 760px`, Web).
   - `WeeklyInsightsController` dùng `_loadToken` chống phản hồi bất đồng bộ đến trễ và gọi `updateOwner` để xóa sạch dữ liệu phiên cũ ngay khi đổi tài khoản.

---

## 3. Cách chạy kiểm tra và xem trước phần thay đổi

Từ thư mục gốc repository (`project-ptdudd/`):

### A. Chạy phân tích tĩnh và kiểm thử tự động

```powershell
cd nhom06-65ktpm/src
flutter pub get
flutter analyze --no-pub
flutter test test/features/insights/ --no-pub
```

Chạy toàn bộ bộ test của dự án:

```powershell
flutter test --no-pub
```

### B. Chạy xem trước Dashboard độc lập (dữ liệu fixture mẫu — mock)

```powershell
cd nhom06-65ktpm/src
# Trên Web (Chrome):
flutter run -d chrome --web-port=5001 -t lib/features/insights/presentation/pages/weekly_insights_demo_main.dart
# Trên Android Emulator hoặc điện thoại Android:
flutter devices
flutter run -d <device-id> -t lib/features/insights/presentation/pages/weekly_insights_demo_main.dart
```

### C. Xuất lại báo cáo Word theo mẫu từ Markdown

Từ thư mục gốc repository (`project-ptdudd/`):

```powershell
python -X utf8 nhom06-65ktpm/docs/build_healthylife_report.py
```

---

## 4. Phạm vi đã kiểm tra và chưa kiểm tra

- **Đã kiểm tra thực tế (`27/11/2026`):**
  - `flutter analyze --no-pub`: **0 issues**.
  - `flutter test --no-pub`: **189/189 ca đạt** (gồm **11/11** ca riêng của `test/features/insights/`).
  - `flutter build web --no-pub` và `flutter build apk --debug --no-pub`: **thành công**.
  - Chụp và kiểm tra trực quan **5 ảnh demo** (3 ảnh trên Android Emulator API 37 + 2 ảnh trên Chrome Web `1280px`) tại [`docs/demo/README.md`](../../../../docs/demo/README.md).
  - `python -X utf8 nhom06-65ktpm/docs/build_healthylife_report.py`: **PASS** (`11 sections, 4 members, Unicode and page settings verified`).
- **Chưa kiểm tra / chờ phối hợp:**
  - Chưa gắn `WeeklyInsightsPage` vào `lib/main.dart` / `AuthGate` (thuộc quyền tích hợp điều hướng chung của nhóm trưởng `@trggg2185`).
  - Chưa kiểm thử đọc trực tiếp dữ liệu tổng hợp từ Supabase cloud thật qua tài khoản đăng nhập.
  - Chưa thực hiện kiểm thử & chụp minh chứng trên **điện thoại Android vật lý** (hiện mới có ảnh trên Android Emulator `emulator-5554` và Chrome Web).
  - Các tính năng mở rộng **AI / Health Connect** chưa triển khai vì các phần cốt lõi (`#3`, `#6`, `#9`, 2 migration cloud và nghiệm thu thiết bị thật) chưa hoàn tất toàn bộ.

---

## 5. Đề xuất phối hợp tích hợp vào `AuthGate` (dành cho `@trggg2185`)

Khi nhóm trưởng nối Dashboard vào màn hình sau đăng nhập trong `lib/main.dart` / `AuthGate`, có thể dùng trực tiếp `WeeklyInsightsPage` và `CompositeWeeklyInsightsSource` với các repository sẵn có:

```dart
insightsPageBuilder: (session) => WeeklyInsightsPage(
  ownerUid: session.uid,
  useCase: GetWeeklyInsightsUseCase(
    source: CompositeWeeklyInsightsSource(
      habitRepository: SupabaseHabitRepository(),
      sleepRepository: SupabaseSleepRepository(),
      activityRepository: resolveActivityRepository(),
      // Tùy chọn: truyền MealLogRepository đã tích hợp cho session hiện tại
    ),
  ),
),
```
