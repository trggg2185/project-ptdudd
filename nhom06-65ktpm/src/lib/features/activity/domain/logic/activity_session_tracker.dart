import 'dart:math' as math;

import '../entities/activity_session.dart';

class ActivitySessionTracker {
  ActivitySessionTracker({this.maximumAccuracyMeters = 30});

  final double maximumAccuracyMeters;
  ActivityStatus status = ActivityStatus.idle;
  DateTime? startedAt;
  DateTime? pausedAt;
  DateTime? stoppedAt;
  final List<GpsPoint> route = [];
  double estimatedDistanceMeters = 0;
  Duration pausedDuration = Duration.zero;
  bool _skipNextSegmentDistance = false;

  void start(DateTime now) {
    status = ActivityStatus.recording;
    startedAt = now;
    pausedAt = null;
    stoppedAt = null;
    pausedDuration = Duration.zero;
    estimatedDistanceMeters = 0;
    route.clear();
    _skipNextSegmentDistance = false;
  }

  void pause(DateTime now) {
    if (status != ActivityStatus.recording) return;
    status = ActivityStatus.paused;
    pausedAt = now;
    _skipNextSegmentDistance = true;
  }

  void resume(DateTime now) {
    if (status != ActivityStatus.paused || pausedAt == null) return;
    pausedDuration += now.difference(pausedAt!);
    pausedAt = null;
    status = ActivityStatus.recording;
    _skipNextSegmentDistance = true;
  }

  void breakSegment() => _skipNextSegmentDistance = true;

  GpsPoint? addPoint(GpsPoint point) {
    if (status != ActivityStatus.recording) return null;
    final accuracy = point.accuracyMeters;
    if (accuracy != null && accuracy > maximumAccuracyMeters) return null;

    if (route.isNotEmpty && !_skipNextSegmentDistance) {
      final previous = route.last;
      final distance = haversineMeters(previous, point);
      if (distance < 2) return null;
      estimatedDistanceMeters += distance;
    }
    _skipNextSegmentDistance = false;
    route.add(point);
    return point;
  }

  Duration durationAt(DateTime now) {
    if (status == ActivityStatus.idle) return Duration.zero;
    final baseStartedAt = startedAt;
    if (baseStartedAt == null) return Duration.zero;
    var excluded = pausedDuration;
    if (status == ActivityStatus.stopped && stoppedAt != null) {
      now = stoppedAt!;
    }
    if (status == ActivityStatus.paused && pausedAt != null) {
      excluded += now.difference(pausedAt!);
    }
    final elapsed = now.difference(baseStartedAt) - excluded;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  void stop(DateTime now) {
    if (status == ActivityStatus.idle) return;
    if (status == ActivityStatus.paused && pausedAt != null) {
      pausedDuration += now.difference(pausedAt!);
      pausedAt = null;
    }
    stoppedAt = now;
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
