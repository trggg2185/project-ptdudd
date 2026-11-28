-- Lưu tường minh nguồn ghi nhận buổi vận động (nhập tay vs thiết bị GPS)
-- để phân biệt chính xác phiên GPS 0 m không lưu tuyến với phiên nhập tay mới,
-- đồng thời giữ NULL (nguồn chưa xác định) cho các bản ghi cũ trước migration.
alter table public.activity_sessions
  add column if not exists input_source text
    check (input_source in ('manual', 'gps'));
