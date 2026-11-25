import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/activity_session.dart';
import '../../domain/logic/activity_session_tracker.dart';
import '../../domain/repositories/activity_repository.dart';

class ActivityController extends ChangeNotifier {
  ActivityController({required this.repository, required this.ownerUid});

  final ActivityRepository repository;
  final String ownerUid;
  final ActivitySessionTracker tracker = ActivitySessionTracker();
  final List<ActivitySession> sessions = [];

  String activityName = 'Chạy bộ';
  String feeling = '';
  bool routeSaved = false;
  bool isLoading = false;
  String? errorMessage;
  String gpsStatus = 'GPS chưa bắt đầu';

  Future<void> loadSessions() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      sessions
        ..clear()
        ..addAll(await repository.getSessions(ownerUid: ownerUid));
    } catch (error) {
      errorMessage = 'Không thể tải nhật ký vận động: $error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void setActivityName(String value) {
    activityName = value;
    notifyListeners();
  }

  void setFeeling(String value) {
    feeling = value;
  }

  void setRouteSaved(bool value) {
    routeSaved = value;
    notifyListeners();
  }

  void setGpsStatus(String value) {
    gpsStatus = value;
    notifyListeners();
  }

  void startGps(DateTime now) {
    routeSaved = false;
    tracker.start(now);
    gpsStatus = 'Đang ghi GPS';
    errorMessage = null;
    notifyListeners();
  }

  void pauseGps(DateTime now) {
    tracker.pause(now);
    gpsStatus = 'GPS đã tạm dừng';
    notifyListeners();
  }

  void resumeGps(DateTime now) {
    tracker.resume(now);
    gpsStatus = 'Đang ghi GPS';
    notifyListeners();
  }

  void addGpsPoint(GpsPoint point) {
    final accepted = tracker.addPoint(point);
    if (accepted == null) return;
    notifyListeners();
  }

  void stopGps(DateTime now) {
    tracker.stop(now);
    gpsStatus = 'Đã dừng GPS';
    notifyListeners();
  }

  void resetGps() {
    tracker.status = ActivityStatus.idle;
    tracker.startedAt = null;
    tracker.pausedAt = null;
    tracker.stoppedAt = null;
    tracker.pausedDuration = Duration.zero;
    tracker.route.clear();
    tracker.estimatedDistanceMeters = 0;
    routeSaved = false;
    gpsStatus = 'GPS chưa bắt đầu';
    errorMessage = null;
    notifyListeners();
  }

  Future<void> saveGpsSession(DateTime endedAt) async {
    final startedAt = tracker.startedAt;
    if (startedAt == null) return;
    final effectiveEndedAt = tracker.stoppedAt ?? endedAt;
    final duration = tracker.durationAt(effectiveEndedAt);
    final session = ActivitySession(
      id: const Uuid().v4(),
      ownerUid: ownerUid,
      activityName: activityName,
      durationSeconds: duration.inSeconds,
      estimatedDistanceMeters: tracker.estimatedDistanceMeters,
      feeling: feeling,
      routeSaved: routeSaved,
      startedAt: startedAt,
      endedAt: effectiveEndedAt,
      route: routeSaved ? List<GpsPoint>.from(tracker.route) : const [],
    );
    final saved = await _save(session);
    if (saved) {
      resetGps();
    }
  }

  Future<void> saveManualSession({
    required int durationMinutes,
    required DateTime date,
  }) async {
    final endedAt = date;
    final startedAt = endedAt.subtract(Duration(minutes: durationMinutes));
    final session = ActivitySession(
      id: const Uuid().v4(),
      ownerUid: ownerUid,
      activityName: activityName,
      durationSeconds: durationMinutes * 60,
      estimatedDistanceMeters: 0,
      feeling: feeling,
      routeSaved: false,
      startedAt: startedAt,
      endedAt: endedAt,
      route: const [],
    );
    await _save(session);
  }

  Future<bool> _save(ActivitySession session) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await repository.saveSession(session);
      sessions.removeWhere((item) => item.id == session.id);
      sessions.insert(0, session);
      return true;
    } catch (error) {
      errorMessage = 'Không thể lưu nhật ký vận động: $error';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
