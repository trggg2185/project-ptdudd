# Module Nhắc lịch cục bộ, Giờ yên lặng & Xử lý đổi tài khoản (Issue #6)

Phụ trách: Phương Văn Đức (`@pvduc05`) — Review chéo: Hàn Hoàng Hà (`@HanHoangHa`).

## Phạm vi triển khai

- **Chỉ đặt nhắc từ lịch đã duyệt (`approved`):**
  - `ReminderSchedulerEngine.reconcile()` lọc chặt chỉ tạo nhắc khi cả `plans.status == 'approved'` lẫn `plan_items.status == 'approved'`.
  - Các mục lịch nháp (`draft`), đã hoàn thành (`completed`), đã bỏ qua (`skipped`) hoặc lịch đã hủy (`cancelled`) tuyệt đối không tạo nhắc và được hiển thị tách biệt trên `NotificationsPage`.
- **Hủy nhắc cũ khi sửa/xóa/bỏ qua lịch & chống trùng Local/FCM (foreground, background, terminated):**
  - Mỗi cặp `(ownerUid, itemId)` dùng ID thông báo 31-bit xác định ổn định (`FNV-1a`), tự động hủy ID cũ khi đổi giờ, xóa mục, bỏ qua mục hoặc tắt nhắc lịch.
  - `FirebaseMessagingGateway` (tích hợp `firebase_messaging` v17) nối vào `NotificationAccountCoordinator`: tự động gọi `registerDeviceToken()` khi phiên có quyền `role: authenticated`, lắng nghe xoay vòng token (`onRegistered`, đồng thời thu hồi token cũ), xử lý `FirebaseMessaging.onMessage` (foreground) và đăng ký top-level `@pragma('vm:entry-point')` `FirebaseMessaging.onBackgroundMessage(healthyLifeFcmBackgroundHandler)` trong `main.dart` cho chế độ **background / terminated**.
  - Chống trùng xuyên isolate hai lớp (`FcmBackgroundMessageProcessor` + `SqliteNotificationBackgroundStateStore` trên `healthylife.db`): chia sẻ trạng thái `active_owner_uid`, cấu hình giờ yên lặng và bảng khóa `notification_dedupe_entries` (TTL 15 phút) giữa UI isolate và background isolate, đồng thời đối chiếu `pendingNotifications()` trên thiết bị để ưu tiên Local Notification và không phát đúp FCM.
- **Hợp đồng payload FCM phía server (Data-Only, bắt buộc):**
  - Server **chỉ được gửi data-only FCM payload** (tuyệt đối **không** gửi khối `notification` công khai/nhạy cảm) để Android luôn định tuyến qua `healthyLifeFcmBackgroundHandler` (ở background/terminated) và `onMessage` (ở foreground), bảo đảm mọi thông báo đều đi qua kiểm tra `owner_uid`, trạng thái `approved`, giờ yên lặng, bộ chống trùng Local ↔ FCM và khóa `NotificationVisibility.private`.
  - Chỉ cho phép các trường siêu dữ liệu kỹ thuật trong `data`: `owner_uid`, `plan_id`, `item_id`, `item_type`, `dedupe_key`, `scheduled_at`, `plan_status`, `item_status`. **Cấm** đính kèm chỉ số cơ thể (`kg`, `BMI`, `kcal`), dị ứng, bệnh lý, thuốc hoặc tọa độ GPS trong payload FCM.
  - Nếu có thông báo lỡ vi phạm hợp đồng gửi kèm khối `notification` ở nền (`message.notification != null`), handler sẽ bỏ qua không gọi `showImmediate()` để tránh phát đúp.
- **Tạm hoãn (Snooze) & Giờ yên lặng (Quiet Hours):**
  - Hỗ trợ khung giờ yên lặng qua nửa đêm (`22:00 – 07:00`) lẫn khung ban ngày cho người làm ca đêm (`08:00 – 15:00`) theo múi giờ IANA chuẩn (`package:timezone`).
  - Lời nhắc thường hoặc lời nhắc tạm hoãn (`+5 / +10 / +15 / +30 phút`) rơi vào giờ yên lặng được tự động lùi ra ngay sau giờ kết thúc yên lặng (bảo toàn chuyển đổi DST).
- **Xử lý đổi múi giờ, khởi động lại thiết bị, tắt quyền & đổi tài khoản (toàn app):**
  - **Điều phối toàn app (`_HealthyLifeAppState` + `AuthGate.onSessionAuthorized`):** `WidgetsBindingObserver` được gắn ngay ở cấp ứng dụng (`main.dart`) nên tự động kích hoạt đăng ký FCM, thử lại hàng đợi thu hồi token và khôi phục lịch nhắc sau boot/đổi quyền/đổi múi giờ **mà không cần người dùng mở `NotificationsPage`**.
  - **Đổi múi giờ:** phát hiện lệch múi giờ thiết bị và khi đổi múi giờ IANA trong cấu hình (hoặc đổi múi giờ hệ thống) sẽ tự động hủy toàn bộ nhắc cũ và đặt lại toàn bộ theo múi giờ mới.
  - **Khởi động lại thiết bị:** khai báo `RECEIVE_BOOT_COMPLETED`, `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` trong `AndroidManifest.xml`, kèm tự đối chiếu khôi phục toàn app (`NotificationAccountCoordinator.handleAppResumed()`) khi mở lại ứng dụng nếu OEM chặn chạy nền.
  - **Tắt quyền thông báo:** không crash; hiển thị biểu ngữ hướng dẫn cấp quyền (`POST_NOTIFICATIONS` trên Android 13+) và vẫn giữ danh sách lịch trong app hoạt động bình thường.
  - **Đăng xuất / đổi tài khoản Firebase & hàng đợi retry offline:** `NotificationAccountCoordinator` nối trực tiếp vào `AuthGate` (`onSessionAuthorized`, `onBeforeSignOut`, `onAccountChanged`) để lập tức hủy toàn bộ thông báo cục bộ đang chờ, xóa bộ nhớ chống trùng/snooze, gọi `deleteToken()` trên FCM và vô hiệu hóa (`is_active = false`) các `device_tokens` của tài khoản cũ trong mọi trường hợp (bấm đăng xuất, đổi tài khoản `A → B`, hoặc đăng xuất Firebase từ bên ngoài). Nếu bước vô hiệu hóa Supabase gặp lỗi mạng khi offline, tác vụ được lưu vào hàng đợi `pendingDeactivations` phân vùng chặt theo `ownerUid` (đảm bảo không gửi cập nhật sang phiên người dùng khác vi phạm RLS) và tự động retry khi ứng dụng resume hoặc đúng tài khoản đó kết nối lại.
- **Màn hình khóa tuyệt đối không lộ thông tin sức khỏe:**
  - `ScheduledReminder`, `FlutterLocalNotificationsGateway` và cầu nối FCM foreground luôn khóa cứng ở chế độ `NotificationVisibility.private` và chỉ đẩy nội dung trung tính từ `NotificationPrivacyFormatter` (*"HealthyLife — Bạn có một hoạt động theo lịch đã duyệt. Mở ứng dụng để xem chi tiết."*) ra hệ thống thông báo — không cung cấp tùy chọn chuyển sang `public`.
  - Bộ lọc kiểm tra nhạy cảm chặn các chỉ số cơ thể (`kg`, `BMI`, `kcal`), dị ứng, bệnh lý, thuốc và tọa độ GPS không lọt ra thông báo công khai hay payload.

## Ánh xạ bảng Supabase

Sử dụng trực tiếp các bảng đã triển khai trong `20261121_000001_initial_healthy_life_schema.sql` (không cần migration mới):
- `public.reminder_preferences`: `owner_uid`, `quiet_hours_start`, `quiet_hours_end`, `reminders_enabled`, `timezone`, `version` (có kiểm tra xung đột optimistic theo `version`).
- `public.plans` & `public.plan_items`: đọc trạng thái phê duyệt và thời điểm mục lịch.
- `public.device_tokens`: đăng ký token FCM theo `(owner_uid, token)` khi phiên có quyền dữ liệu / `onTokenRefresh` và đặt `is_active = false` khi đăng xuất (kèm hàng đợi retry theo `owner_uid`).

## Cách chạy và kiểm thử cục bộ

Từ thư mục `nhom06-65ktpm/src`:

```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub test/features/notifications
flutter test --no-pub
```

## Phạm vi kiểm chứng thực địa còn lại (trước khi đóng Issue #6)

Các kiểm thử tự động trong `test/features/notifications/` chạy cục bộ bằng `InMemoryNotificationRepository`, `InMemoryLocalNotificationGateway` và `InMemoryFcmMessagingGateway` (**chưa** thay thế cho kiểm chứng trên máy Android thật và Supabase/FCM cloud). Các hạng mục nghiệm thu thực địa dưới đây được tách rõ trên Issue #6 để thực hiện trước khi chuyển Issue #6 sang **Done**:

1. **Android thật (API 24–36):**
   - Đăng nhập tài khoản có claim `role: authenticated` → kiểm tra xin quyền `POST_NOTIFICATIONS` (Android 13+), tắt quyền trong Cài đặt Android (xác nhận không crash và giữ danh sách trong app).
   - Bấm **Gửi thử thông báo riêng tư** khi khóa màn hình để xác nhận màn hình khóa chỉ hiện nội dung trung tính, không lộ dữ liệu sức khỏe.
   - Kiểm tra giờ yên lặng (cả `22:00 – 07:00` và `08:00 – 15:00`), tạm hoãn (Snooze), đổi múi giờ máy, khởi động lại điện thoại thật (xác nhận `BOOT_COMPLETED` hoặc khôi phục toàn app khi mở lại) và ghi nhận sai lệch Doze/OEM nếu có.
2. **Supabase cloud RLS hai tài khoản (`A` và `B`):**
   - Smoke-test đọc/ghi `reminder_preferences` (kể cả kiểm tra xung đột `version`), đăng ký và vô hiệu hóa `device_tokens` theo đúng `owner_uid`, xác nhận tài khoản B không đọc/sửa được cấu hình hoặc token của tài khoản A.
3. **End-to-end FCM thật (foreground, background và terminated):**
   - Xác nhận nhận token/registration ID FCM thật ghi vào `public.device_tokens`, thử bắn payload FCM **data-only** trùng `dedupe_key` ở cả 3 trạng thái **foreground, background và terminated** để xác nhận chống trùng Local ↔ FCM (qua SQLite xuyên isolate + `pendingNotifications`) và màn hình khóa luôn hiển thị nội dung trung tính `NotificationVisibility.private`, rồi đăng xuất đổi tài khoản để xác nhận `unregister()` + `is_active = false` + xóa trạng thái nền của tài khoản cũ.

**Giới hạn thực tế của thiết bị đã ghi nhận:**
- Cơ chế tiết kiệm pin / Doze mode của một số hãng Android (Xiaomi/MIUI, Oppo/ColorOS, Huawei, Samsung) có thể làm trễ thông báo `inexactAllowWhileIdle` vài phút hoặc chặn receiver `BOOT_COMPLETED` nếu người dùng bật hạn chế chạy nền sâu; ứng dụng tự đối chiếu khôi phục nhắc toàn app khi người dùng mở lại app.
- Trình duyệt Web không hỗ trợ hẹn giờ thông báo nền khi đóng tab; trên Web người dùng vẫn quản lý cấu hình và danh sách nhắc trong ứng dụng bình thường.
- Hàng đợi retry thu hồi `device_tokens` hiện lưu trong bộ nhớ phiên chạy và phân vùng theo `owner_uid` để tôn trọng RLS; khi đổi sang tài khoản khác lúc offline, `deleteToken()` trên FCM giúp cắt nhận push ngay ở phía thiết bị trong khi bản ghi `device_tokens` của tài khoản cũ chờ chính chủ tài khoản đó đăng nhập lại để cập nhật `is_active = false` trên Supabase.
