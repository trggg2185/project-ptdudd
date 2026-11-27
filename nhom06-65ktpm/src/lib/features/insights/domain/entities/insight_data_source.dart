/// Nguồn ghi nhận dữ liệu hiển thị trên Dashboard & tổng kết tuần (Issue #12).
///
/// Luôn phân biệt rõ nguồn nhập tay / tự khai báo với dữ liệu thu từ thiết bị
/// (GPS trong phiên, ảnh chụp/chọn từ camera/thư viện) để trung thực về phạm vi đo đạc.
enum InsightDataSource {
  manualInput('manual_input', 'Nhập tay'),
  selfReported('self_reported', 'Tự khai báo'),
  deviceGps('device_gps', 'Thiết bị (GPS trong phiên)'),
  cameraOrGallery('camera_or_gallery', 'Camera / Thư viện ảnh');

  const InsightDataSource(this.code, this.label);

  final String code;
  final String label;
}
