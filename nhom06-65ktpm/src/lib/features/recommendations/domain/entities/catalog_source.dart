/// Thông tin nguồn tham khảo và trạng thái kiểm duyệt của mục danh mục.
/// Tương thích với các cột `source_name`, `source_url`, `source_version` trong Supabase.
class CatalogSource {
  final String name;
  final String url;
  final String version;
  final String reviewedAt;

  const CatalogSource({
    required this.name,
    required this.url,
    required this.version,
    required this.reviewedAt,
  });

  /// Kiểm tra nguồn kiểm duyệt có đủ tên, đường dẫn và phiên bản hay không.
  bool get isComplete =>
      name.trim().isNotEmpty &&
      url.trim().isNotEmpty &&
      version.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'source_name': name,
      'source_url': url,
      'source_version': version,
      'reviewed_at': reviewedAt,
    };
  }

  factory CatalogSource.fromMap(Map<String, dynamic> map) {
    return CatalogSource(
      name: (map['source_name'] ?? map['name'] ?? '') as String,
      url: (map['source_url'] ?? map['url'] ?? '') as String,
      version: (map['source_version'] ?? map['version'] ?? '') as String,
      reviewedAt: (map['reviewed_at'] ?? '') as String,
    );
  }
}
