# Module Giấc ngủ & Lịch sinh hoạt responsive (Issue #5)

Phụ trách: Phương Văn Đức (`@pvduc05`) — Review chéo: Hàn Hoàng Hà (`@HanHoangHa`).

## Phạm vi triển khai

- **Nhập giờ ngủ/thức và mức tỉnh táo tự đánh giá (`SleepLogFormPage`):**
  - Nhập trực tiếp bằng bàn phím (`Giờ 0–23`, `Phút 0–59`) hoặc chọn bằng đồng hồ (`TimePicker`).
  - Tự động suy luận qua nửa đêm (+1 ngày) khi giờ thức nhỏ hơn giờ ngủ (ví dụ `23:30 → 07:00`), đồng thời hỗ trợ ngủ ban ngày cho người làm ca đêm (ví dụ `07:45 → 14:45`) và tùy chọn chọn ngày thức thủ công.
  - Chọn mức tỉnh táo tự đánh giá theo thang 1–5 (`AlertnessLevel`) và ghi chú.
  - Chặn giờ thức <= giờ ngủ, giấc ngủ vượt quá 24 giờ, giấc ngủ trong tương lai và chồng lấn với nhật ký đã lưu.
- **Khoảng ngủ mong muốn linh hoạt (`SleepWindowDialog`):**
  - Không áp đặt mốc 22:00 cho mọi người; hỗ trợ cả khung ngủ qua nửa đêm lẫn khung ngủ ban ngày cho ca đêm (`07:30 – 15:00`), tương thích định dạng `sleep_start`/`sleep_end` (phút từ 00:00) trong `profiles.living_conditions['healthylife_profile']` của Issue #2.
- **Lịch sinh hoạt 24 giờ responsive (`ResponsiveRoutineTimeline` & `SleepPage`):**
  - Android / màn hình hẹp (`< 760px`): bố cục 1 cột kèm thanh chuyển đổi *Nhật ký ngủ* / *Lịch sinh hoạt 24h*.
  - Web / màn hình rộng (`>= 760px`): bố cục 2 cột song song (Tổng quan & Nhật ký | Lịch sinh hoạt 24 giờ).
  - Tự động tách đoạn qua mốc `00:00` cho cả ca đêm (`22:00–06:00`) lẫn giấc ngủ qua nửa đêm (`23:30–07:00`), cảnh báo nếu khoảng ngủ mong muốn giao với ca làm.
  - Đầy đủ trạng thái **đang tải (loading)**, **trống (empty)**, **lỗi (error + nút Thử lại)**.
- **Minh bạch nghiệp vụ:**
  - Không suy ra giấc ngủ thật từ việc không dùng điện thoại; không khẳng định đo giấc ngủ bằng cảm biến.
  - Ngày chưa ghi nhận trong biểu đồ 7 ngày hiển thị trung tính (`—`), không xem là thất bại và không kéo giảm trung bình.
- **Truy cập (Accessibility) và bàn phím:**
  - Nhãn `Semantics` đầy đủ cho nút, ô nhập giờ/phút, mức tỉnh táo, live region thông báo lỗi/tải.
  - Phím tắt trên màn hình chính: `Alt + N` (thêm nhật ký), `Alt + W` (khoảng ngủ mong muốn), `Alt + R` (tải lại), `Alt + ←/→` (chuyển ngày trên lịch sinh hoạt).

## Cách chạy và kiểm thử

Từ thư mục `nhom06-65ktpm/src`:

```bash
flutter pub get
flutter analyze
flutter test test/features/sleep
flutter test
```

## Giới hạn hiện tại

- `SupabaseSleepRepository` ánh xạ trực tiếp bảng `public.sleep_logs`, `public.profiles.living_conditions` và `public.availability_blocks`, nhưng các ca kiểm thử trong `test/features/sleep/` chạy cục bộ bằng `InMemorySleepRepository` và fixture (không kiểm chứng RLS/mạng trên Supabase cloud).
- Màn hình **Mở nhật ký ngủ** trên app chính yêu cầu phiên Firebase đã có claim `role: authenticated` để đồng bộ với Supabase; việc nối hàng đợi offline SQLite `LocalSyncWorker` vào từng repository sẽ thực hiện trong bước tích hợp chung.
