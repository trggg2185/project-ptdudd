class GpsPoint {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime recordedAt;

  const GpsPoint({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    required this.recordedAt,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': accuracyMeters,
    'recordedAt': recordedAt.toIso8601String(),
  };

  factory GpsPoint.fromJson(Map<String, dynamic> json) => GpsPoint(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
    recordedAt: DateTime.parse(json['recordedAt'] as String),
  );
}

enum ActivityStatus { idle, recording, paused, stopped }

enum ActivityInputSource { manual, gps }

class ActivitySession {
  final String id;
  final String ownerUid;
  final String activityName;
  final int durationSeconds;
  final double estimatedDistanceMeters;
  final String feeling;
  final bool routeSaved;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<GpsPoint> route;
  final ActivityInputSource? inputSource;

  const ActivitySession({
    required this.id,
    required this.ownerUid,
    required this.activityName,
    required this.durationSeconds,
    required this.estimatedDistanceMeters,
    required this.feeling,
    required this.routeSaved,
    required this.startedAt,
    required this.endedAt,
    required this.route,
    this.inputSource,
  });

  /// Phân giải nguồn ghi nhận vận động: ưu tiên [inputSource] tường minh
  /// (phân biệt chính xác phiên GPS 0 m không lưu tuyến với phiên nhập tay);
  /// chỉ suy luận ngược cho bản ghi cũ không có [inputSource].
  ActivityInputSource get resolvedSource {
    final explicit = inputSource;
    if (explicit != null) return explicit;
    if (route.isNotEmpty || routeSaved || estimatedDistanceMeters > 0) {
      return ActivityInputSource.gps;
    }
    return ActivityInputSource.manual;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerUid': ownerUid,
    'activityName': activityName,
    'durationSeconds': durationSeconds,
    'estimatedDistanceMeters': estimatedDistanceMeters,
    'feeling': feeling,
    'routeSaved': routeSaved,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'route': route.map((point) => point.toJson()).toList(),
    'inputSource': resolvedSource.name,
  };
}
