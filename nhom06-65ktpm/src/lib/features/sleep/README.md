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

## Đồng bộ, xung đột và ràng buộc dữ liệu

- **Ghi/xóa nhật ký ngủ (`public.sleep_logs`):** `SupabaseSleepRepository` đi qua `SyncTransport` (`SupabaseSyncTransport` → RPC `apply_log_sync`) với `operation_id` UUID, `p_base_version` và `p_expected_owner_uid` thay vì `.upsert()` trực tiếp, giúp phát hiện xung đột phiên bản (`SleepConflictException`) khi hai thiết bị cùng chỉnh sửa bản ghi.
- **Tách lỗi lưu và tải lại (`SleepController`):** nếu lưu thành công nhưng bước tải lại danh sách gặp lỗi mạng, ứng dụng giữ bản ghi đã lưu, đóng form và hiển thị biểu ngữ cảnh báo nhẹ (`syncWarning`) kèm nút **Tải lại** thay vì báo sai rằng thao tác lưu đã thất bại.
- **Cập nhật khoảng ngủ mong muốn an toàn (`profiles.living_conditions`):** ưu tiên gọi RPC nguyên tử `upsert_sleep_window` (chỉ merge/xóa các khóa `sleep_start`, `sleep_end`, `sleep_label` bên trong `healthylife_profile`), đồng thời có fallback compare-and-swap (`updated_at` + `version`) nếu migration mới chưa được áp dụng lên cloud.
- **Ràng buộc nghiệp vụ ở tầng DB (chưa áp dụng lên cloud):** migration đề xuất [`20261125000005_sleep_constraints_and_window_merge.sql`](../../../supabase/migrations/20261125000005_sleep_constraints_and_window_merge.sql) bổ sung check tối đa 24 giờ, trigger chống bản ghi tương lai và chống chồng lấn khoảng ngủ theo `owner_uid`, cùng RPC `upsert_sleep_window` — chờ `@HanHoangHa` duyệt trước khi triển khai lên Supabase cloud.

## Cách chạy và kiểm thử

Từ thư mục `nhom06-65ktpm/src`:

```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub test/features/sleep
flutter test --no-pub
```

## Giới hạn hiện tại

- Các ca kiểm thử trong `test/features/sleep/` kiểm chứng `SupabaseSleepRepository` bằng `SyncTransport` giả lập cùng `InMemorySleepRepository` và fixture cục bộ; **chưa** kiểm chứng RPC/RLS/mạng trên Supabase cloud và **chưa** chạy migration `20261125000005` lên cloud.
- Màn hình **Mở nhật ký ngủ** trên app chính yêu cầu phiên Firebase đã có claim `role: authenticated` để đồng bộ với Supabase; việc gắn hàng đợi offline SQLite `LocalSyncWorker` vào UI thuộc bước tích hợp chung.
