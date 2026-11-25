import 'dart:math' as math;

import '../entities/activity_session.dart';

class ActivitySessionTracker {
  ActivitySessionTracker({this.maximumAccuracyMeters = 30});

  final double maximumAccuracyMeters;
  ActivityStatus status = ActivityStatus.idle;
  DateTime? startedAt;
  DateTime? pausedAt;
  final List<GpsPoint> route = [];
  double estimatedDistanceMeters = 0;
  Duration pausedDuration = Duration.zero;

  void start(DateTime now) {
    status = ActivityStatus.recording;
    startedAt = now;
    pausedAt = null;
    pausedDuration = Duration.zero;
    estimatedDistanceMeters = 0;
    route.clear();
  }

  void pause(DateTime now) {
    if (status != ActivityStatus.recording) return;
    status = ActivityStatus.paused;
    pausedAt = now;
  }

  void resume(DateTime now) {
    if (status != ActivityStatus.paused || pausedAt == null) return;
    pausedDuration += now.difference(pausedAt!);
    pausedAt = null;
    status = ActivityStatus.recording;
  }

  GpsPoint? addPoint(GpsPoint point) {
    if (status != ActivityStatus.recording) return null;
    final accuracy = point.accuracyMeters;
    if (accuracy != null && accuracy > maximumAccuracyMeters) return null;

    if (route.isNotEmpty) {
      final previous = route.last;
      final distance = haversineMeters(previous, point);
      if (distance < 2) return null;
      estimatedDistanceMeters += distance;
    }
    route.add(point);
    return point;
  }

  Duration durationAt(DateTime now) {
    final baseStartedAt = startedAt;
    if (baseStartedAt == null) return Duration.zero;
    var excluded = pausedDuration;
    if (status == ActivityStatus.paused && pausedAt != null) {
      excluded += now.difference(pausedAt!);
    }
    final elapsed = now.difference(baseStartedAt) - excluded;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  void stop() {
    if (status == ActivityStatus.idle) return;
    status = ActivityStatus.stopped;
  }

  static double haversineMeters(GpsPoint from, GpsPoint to) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _degreesToRadians(from.latitude);
    final lat2 = _degreesToRadians(to.latitude);
    final deltaLat = lat2 - lat1;
    final deltaLon = _degreesToRadians(to.longitude - from.longitude);
    final haversine =
        math.pow(math.sin(deltaLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLon / 2), 2);
    final centralAngle =
        2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
    return earthRadiusMeters * centralAngle;
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;
}
