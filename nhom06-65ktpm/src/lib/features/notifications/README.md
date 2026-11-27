# Module Nhắc lịch cục bộ, Giờ yên lặng & Xử lý đổi tài khoản (Issue #6)

Phụ trách: Phương Văn Đức (`@pvduc05`) — Review chéo: Hàn Hoàng Hà (`@HanHoangHa`).

## Phạm vi triển khai

- **Chỉ đặt nhắc từ lịch đã duyệt (`approved`):**
  - `ReminderSchedulerEngine.reconcile()` lọc chặt chỉ tạo nhắc khi cả `plans.status == 'approved'` lẫn `plan_items.status == 'approved'`.
  - Các mục lịch nháp (`draft`), đã hoàn thành (`completed`), đã bỏ qua (`skipped`) hoặc lịch đã hủy (`cancelled`) tuyệt đối không tạo nhắc và được hiển thị tách biệt trên `NotificationsPage`.
- **Hủy nhắc cũ khi sửa/xóa/bỏ qua lịch & chống trùng Local/FCM:**
  - Mỗi cặp `(ownerUid, itemId)` dùng ID thông báo 31-bit xác định ổn định (`FNV-1a`), tự động hủy ID cũ khi đổi giờ, xóa mục, bỏ qua mục hoặc tắt nhắc lịch.
  - `NotificationDeduplicator` phân vùng theo `ownerUid` với khóa `dedupeKey` và cửa sổ TTL 15 phút, chặn phát trùng giữa Local Notification và FCM cho cùng một khung giờ.
- **Tạm hoãn (Snooze) & Giờ yên lặng (Quiet Hours):**
  - Hỗ trợ khung giờ yên lặng qua nửa đêm (`22:00 – 07:00`) lẫn khung ban ngày cho người làm ca đêm (`08:00 – 15:00`) theo múi giờ IANA chuẩn (`package:timezone`).
  - Lời nhắc thường hoặc lời nhắc tạm hoãn (`+5 / +10 / +15 / +30 phút`) rơi vào giờ yên lặng được tự động lùi ra ngay sau giờ kết thúc yên lặng (bảo toàn chuyển đổi DST).
- **Xử lý đổi múi giờ, khởi động lại thiết bị, tắt quyền & đổi tài khoản:**
  - **Đổi múi giờ:** phát hiện lệch múi giờ thiết bị và khi đổi múi giờ IANA trong cấu hình sẽ tự động hủy toàn bộ nhắc cũ và đặt lại toàn bộ theo múi giờ mới.
  - **Khởi động lại thiết bị:** khai báo `RECEIVE_BOOT_COMPLETED`, `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` trong `AndroidManifest.xml`, kèm cơ chế tự đối chiếu khôi phục (`refreshOnAppResumed`) khi mở lại ứng dụng nếu OEM chặn chạy nền.
  - **Tắt quyền thông báo:** không crash; hiển thị biểu ngữ hướng dẫn cấp quyền (`POST_NOTIFICATIONS` trên Android 13+) và vẫn giữ danh sách lịch trong app hoạt động bình thường.
  - **Đăng xuất / đổi tài khoản Firebase:** `NotificationAccountCoordinator` nối trực tiếp vào `AuthGate` (`onBeforeSignOut`, `onAccountChanged`) để lập tức hủy toàn bộ thông báo cục bộ đang chờ, xóa bộ nhớ chống trùng/snooze của tài khoản cũ và vô hiệu hóa (`is_active = false`) các `device_tokens` của tài khoản cũ trên Supabase.
- **Màn hình khóa không lộ thông tin sức khỏe:**
  - `NotificationPrivacyFormatter` mặc định phát nội dung trung tính (*"HealthyLife — Bạn có một hoạt động theo lịch đã duyệt. Mở ứng dụng để xem chi tiết."*) kết hợp `NotificationVisibility.private` trên Android.
  - Bộ lọc kiểm tra nhạy cảm chặn các chỉ số cơ thể (`kg`, `BMI`, `kcal`), dị ứng, bệnh lý, thuốc và tọa độ GPS không lọt ra thông báo công khai hay payload.

## Ánh xạ bảng Supabase

Sử dụng trực tiếp các bảng đã triển khai trong `20261121_000001_initial_healthy_life_schema.sql` (không cần migration mới):
- `public.reminder_preferences`: `owner_uid`, `quiet_hours_start`, `quiet_hours_end`, `reminders_enabled`, `timezone`, `version` (có kiểm tra xung đột optimistic theo `version`).
- `public.plans` & `public.plan_items`: đọc trạng thái phê duyệt và thời điểm mục lịch.
- `public.device_tokens`: đăng ký token theo `(owner_uid, token)` và đặt `is_active = false` khi đăng xuất.

## Cách chạy và kiểm thử cục bộ

Từ thư mục `nhom06-65ktpm/src`:

```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub test/features/notifications
flutter test --no-pub
```

## Hướng dẫn kiểm thử trên thiết bị Android thật & Giới hạn thực tế

Các kiểm thử tự động trong `test/features/notifications/` chạy cục bộ bằng `InMemoryNotificationRepository` và `InMemoryLocalNotificationGateway` (**chưa** thay thế cho kiểm chứng trên máy Android thật và Supabase cloud). Khi thử trên Android thật (API 24–36):

1. Đăng nhập tài khoản có claim `role: authenticated` → mở **Mở nhắc lịch & giờ yên lặng**.
2. Kiểm tra xin quyền `POST_NOTIFICATIONS` (Android 13+), sau đó thử tắt quyền trong Cài đặt Android và xác nhận app hiển thị cảnh báo hướng dẫn mà không crash.
3. Bấm **Gửi thử thông báo riêng tư** khi khóa màn hình để xác nhận màn hình khóa chỉ hiện nội dung trung tính, không lộ dữ liệu sức khỏe.
4. Thử đặt giờ yên lặng (cả `22:00 – 07:00` và `08:00 – 15:00`), thử tạm hoãn (Snooze), đổi múi giờ máy, khởi động lại điện thoại và đăng xuất/đăng nhập tài khoản khác để xác nhận không nhận nhắc của tài khoản cũ.

**Giới hạn thực tế của thiết bị đã ghi nhận:**
- Cơ chế tiết kiệm pin / Doze mode của một số hãng Android (Xiaomi/MIUI, Oppo/ColorOS, Huawei, Samsung) có thể làm trễ thông báo `inexactAllowWhileIdle` vài phút hoặc chặn receiver `BOOT_COMPLETED` nếu người dùng bật hạn chế chạy nền sâu; ứng dụng tự đối chiếu khôi phục nhắc khi người dùng mở lại app.
- Trình duyệt Web không hỗ trợ hẹn giờ thông báo nền khi đóng tab; trên Web người dùng vẫn quản lý cấu hình và danh sách nhắc trong ứng dụng bình thường.
- Chưa smoke-test trực tiếp `reminder_preferences`/`device_tokens` RLS hai tài khoản trên Supabase cloud trong phạm vi kiểm thử cục bộ này.
