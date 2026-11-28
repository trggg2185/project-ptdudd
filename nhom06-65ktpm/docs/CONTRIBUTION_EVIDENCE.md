# Minh chứng Đóng góp Thực tế theo Lịch sử Git & PR — HealthyLife (Nhóm 06)

- **Phụ trách tổng hợp (Issue #12):** Nguyễn Đăng Đại (`@nddai0710`)
- **Review chéo:** Nguyễn Thế Trưởng (`@trggg2185`)
- **Ngày tổng hợp:** `27/11/2026`
- **Phạm vi truy xuất:** Toàn bộ lịch sử trên nhánh nhóm `nhom06-65ktpm` từ commit khởi tạo đề tài HealthyLife (`1296468`, ngày `15/11/2026`) đến commit tích hợp mới nhất (`d5a16f3`, ngày `27/11/2026`), cộng phần công việc đang mở của Issue #12 trên nhánh `feature/nhom06/insights`.

> **Nguyên tắc minh bạch:** Bảng bên dưới ghi nhận số liệu khách quan từ lịch sử Git, PR đã merge và bộ kiểm thử tự động đã chạy (`189/189`). **Không** mặc định chia đều tỷ lệ `%` đóng góp khi chưa có cuộc họp xác nhận của cả 4 thành viên và khi 3 issue `#3`, `#6`, `#9` vẫn đang hoàn thiện.

---

## 1. Tổng hợp đóng góp theo từng thành viên

| Thành viên (MSSV) | GitHub / Tên commit | Issues phụ trách | Commit non-merge trên `nhom06-65ktpm` | PR đã merge vào `nhom06-65ktpm` | Vai trò review chéo đã thực hiện | Số ca test tự động đóng góp | Tỷ lệ `%` đóng góp |
| --- | --- | --- | ---: | --- | --- | ---: | --- |
| **Nguyễn Thế Trưởng** (`2351170626`) | `@trggg2185` (`HelloWorld2k5`) | `#1`, `#2`, `#3` | **11** | **PR #13** (`auth`), **PR #18** (`profile`) | Review & merge **PR #14** (`recommend`), **PR #15** (`habits`), **PR #20** (`nutrition`); tích hợp `main.dart`/`AuthGate` (`464d08b`, `d5a16f3`) | **22** (`auth` 11, `profile` 11) | *Chờ nhóm xác nhận* |
| **Phương Văn Đức** (`2351170585`) | `@pvduc05` (`pvduc05` / `zzDuczzz`) | `#4`, `#5`, `#6` | **7** | **PR #15** (`habits`), **PR #17** (`sleep`) | Review & merge **PR #16** (`data`), **PR #19** (`gps`) | **60** (`habits` 36, `sleep` 24) | *Chờ nhóm xác nhận* |
| **Hàn Hoàng Hà** (`2051063882`) | `@HanHoangHa` (`Hàn Hoàng Hà`) | `#7`, `#8`, `#9` | **6** | **PR #16** (`data`), **PR #19** (`gps`) | Review **PR #15** (`habits`), review & merge **PR #17** (`sleep`); phụ trách schema/RLS/Storage chung | **27** (`core` 14, `activity` 13) | *Chờ nhóm xác nhận* |
| **Nguyễn Đăng Đại** (`2351170578`) | `@nddai0710` (`nddai0710`) | `#10`, `#11`, `#12` | **17** *(+3 commit trên `feature/nhom06/insights`)* | **PR #14** (`recommend`), **PR #20** (`nutrition`) | Review & merge **PR #13** (`auth`), **PR #18** (`profile`); tổng hợp kiểm thử & báo cáo `#12` | **80** (`recommendations` 35, `nutrition` 34, `insights` 11) | *Chờ nhóm xác nhận* |
| **Tổng cộng** | **4 thành viên** | **12 issues** | **41** *(+3 trên nhánh `#12`)* | **8 PR đã merge** | **Đủ cặp review chéo Trưởng–Đại, Đức–Hà** | **189 / 189** | *Chốt trước khi nộp bài* |

---

## 2. Danh sách 8 Pull Request nội bộ đã review và merge vào `nhom06-65ktpm`

| PR | Commit merge | Ngày merge | Nhánh nguồn | Issue | Tác giả | Người review / merge | Tóm tắt sản phẩm đã tích hợp |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **#13** | `16e3d1f` | `2026-11-22` | `feature/nhom06/auth` | `#1` | `@trggg2185` | `@nddai0710` | Đăng nhập Firebase (Email/Google), kiểm tra claim `role: authenticated`, callback `accessToken` sang Supabase. |
| **#14** | `32e0d57` | `2026-11-22` | `feature/nhom06/recommend` | `#10` | `@nddai0710` | `@trggg2185` | Danh mục mẫu có nguồn WHO (Fixture/JSON/SQL), bộ lọc cứng dị ứng/thiết bị, xếp hạng có giải thích và 35 test. |
| **#15** | `96386e3` | `2026-11-23` | `feature/nhom06/habits` | `#4` | `@pvduc05` | `@HanHoangHa` / `@trggg2185` | CRUD thói quen, check-in hằng ngày, quy tắc streak bảo toàn ngày nghỉ/tạm dừng, lịch sử không đổi khi sửa quy tắc tương lai. |
| **#16** | `192d610` | `2026-11-23` | `feature/nhom06/data` | `#7` | `@HanHoangHa` | `@pvduc05` | Migration schema/RLS/Storage, RPC `apply_log_sync`, SQLite `LocalDatabase` và `LocalSyncWorker` có xử lý xung đột. |
| **#17** | `2d15df6` | `2026-11-26` | `feature/nhom06/sleep` | `#5` | `@pvduc05` | `@HanHoangHa` | Nhật ký ngủ qua nửa đêm & ca đêm, lịch sinh hoạt 24h responsive 1/2 cột, đồng bộ qua `apply_log_sync` và migration ràng buộc `sleep_logs`. |
| **#18** | `803a1eb` | `2026-11-26` | `feature/nhom06/profile` | `#2` | `@trggg2185` | `@nddai0710` | Hồ sơ 18+, xác nhận dị ứng, ca làm qua đêm `22:00–06:00`, lặp tuần, ngày ngoại lệ, DST và lịch thủ công. |
| **#19** | `e4da50e` | `2026-11-26` | `feature/nhom06/gps` | `#8` | `@HanHoangHa` | `@pvduc05` | Nhật ký vận động và phiên GPS `Start/Pause/Resume/Stop`, lọc điểm `> 30m`, Haversine, dừng khi ra nền và fallback nhập tay. |
| **#20** | `f0c44d5` | `2026-11-26` | `feature/nhom06/nutrition` | `#11` | `@nddai0710` | `@trggg2185` | Gợi ý/đổi món theo dị ứng, xóa EXIF nhị phân, nén ảnh, bucket riêng tư `meal-images`, hàng đợi ảnh SQLite bền vững qua restart và retry an toàn `409`/`413`/`429`/`5xx`. |

---

## 3. Công việc đang triển khai và chưa hoàn tất (tính đến `27/11/2026`)

1. **Issue #12 (`feature/nhom06/insights`, `@nddai0710`):** Đã hoàn thiện bộ tổng hợp tuần (`82d6aa8`), giao diện Dashboard phân biệt chưa ghi nhận / không hoàn thành + ghi nguồn dữ liệu (`86f8e6a`), báo cáo kiểm thử nghiệm thu + 5 ảnh demo Android Emulator/Web (`975bc81`), minh chứng đóng góp và tài liệu hướng dẫn chạy; chuẩn bị mở PR để `@trggg2185` review và nối vào `AuthGate`.
2. **Issues cốt lõi chưa merge vào `nhom06-65ktpm`:**
   - **Issue #3 (`planner`, `@trggg2185`):** Lập lịch tuần tự động & tích hợp luồng chính.
   - **Issue #6 (`notifications`, `@pvduc05`):** Nhắc lịch cục bộ, giờ yên lặng và hủy nhắc khi đổi tài khoản.
   - **Issue #9 (`privacy`, `@HanHoangHa`):** Kiểm thử truy cập chéo 3 tài khoản A/B/C trên toàn bộ bảng/bucket thật và quy trình xóa dữ liệu/tài khoản.
3. **Hạng mục cloud & thiết bị thật còn lại:** Áp dụng 2 migration `20261125000004` (`meal-images` limits) và `20261125000005` (`sleep_logs` constraints + `upsert_sleep_window`) lên Supabase cloud, viết `integration_test/` và bổ sung ảnh/số liệu đo GPS, camera trên **điện thoại Android vật lý**.

---

## 4. Quyết định về tính năng mở rộng (AI / Health Connect)

Tuân thủ tiêu chí Đề cương mục 3.3 và Issue #12 (**"AI/Health Connect chỉ làm khi cốt lõi đạt"**):
- **Không triển khai AI nhận diện món ăn** và **không triển khai Health Connect** ở thời điểm này vì các phần cốt lõi (`#3`, `#6`, `#9`, 2 migration cloud và nghiệm thu trên điện thoại Android thật) chưa hoàn tất 100%.
- Mã nguồn `nutrition` giữ sẵn giao diện mở rộng tùy chọn (`OptionalMealLabelSuggester`, mặc định tắt) để bảo đảm không làm ảnh hưởng độ ổn định hay tiến độ bàn giao bản cốt lõi.
