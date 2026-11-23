/// Tiện ích xử lý chuẩn hóa ngày giờ, múi giờ địa phương cho thói quen và streak.
class DateHelper {
  /// Chuẩn hóa DateTime về đầu ngày địa phương (00:00:00.000).
  static DateTime normalize(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  /// Kiểm tra hai thời điểm có thuộc cùng một ngày lịch địa phương hay không.
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Kiểm tra ngày [target] có trước ngày [reference] (mặc định là hôm nay) hay không.
  static bool isPastDay(DateTime target, [DateTime? reference]) {
    final ref = normalize(reference ?? DateTime.now());
    final normTarget = normalize(target);
    return normTarget.isBefore(ref);
  }

  /// Kiểm tra ngày [target] có sau ngày [reference] (mặc định là hôm nay) hay không.
  static bool isFutureDay(DateTime target, [DateTime? reference]) {
    final ref = normalize(reference ?? DateTime.now());
    final normTarget = normalize(target);
    return normTarget.isAfter(ref);
  }

  /// Định dạng chuỗi YYYY-MM-DD.
  static String formatIsoDate(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Tên thứ tiếng Việt (1 = Thứ 2, ..., 7 = Chủ nhật).
  static String weekdayToVietnamese(int weekday, {bool short = false}) {
    switch (weekday) {
      case DateTime.monday:
        return short ? 'T2' : 'Thứ Hai';
      case DateTime.tuesday:
        return short ? 'T3' : 'Thứ Ba';
      case DateTime.wednesday:
        return short ? 'T4' : 'Thứ Tư';
      case DateTime.thursday:
        return short ? 'T5' : 'Thứ Năm';
      case DateTime.friday:
        return short ? 'T6' : 'Thứ Sáu';
      case DateTime.saturday:
        return short ? 'T7' : 'Thứ Bảy';
      case DateTime.sunday:
        return short ? 'CN' : 'Chủ Nhật';
      default:
        return '';
    }
  }

  /// Định dạng hiển thị tiếng Việt: "Thứ Hai, 21/11/2026"
  static String formatVietnameseDate(DateTime dateTime) {
    final weekdayStr = weekdayToVietnamese(dateTime.weekday);
    final d = dateTime.day.toString().padLeft(2, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final y = dateTime.year.toString();
    return '$weekdayStr, $d/$m/$y';
  }
}
