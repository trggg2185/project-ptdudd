import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/activity/domain/entities/activity_session.dart';
import 'package:healthylife/features/activity/domain/logic/activity_session_tracker.dart';
import 'package:healthylife/features/activity/data/repositories/in_memory_activity_repository.dart';
import 'package:healthylife/features/activity/presentation/controllers/activity_controller.dart';

void main() {
  group('ActivitySessionTracker', () {
    test('rejects inaccurate GPS points', () {
      final tracker = ActivitySessionTracker(maximumAccuracyMeters: 30);
      tracker.start(DateTime(2026, 11, 25, 8));

      final accepted = tracker.addPoint(
        GpsPoint(
          latitude: 10.762622,
          longitude: 106.660172,
          accuracyMeters: 31,
          recordedAt: DateTime(2026, 11, 25, 8),
        ),
      );

      expect(accepted, isNull);
      expect(tracker.route, isEmpty);
    });

    test('adds distance only for accepted points', () {
      final tracker = ActivitySessionTracker();
      tracker.start(DateTime(2026, 11, 25, 8));

      tracker.addPoint(
        GpsPoint(
          latitude: 10.762622,
          longitude: 106.660172,
          accuracyMeters: 8,
          recordedAt: DateTime(2026, 11, 25, 8),
        ),
      );
      tracker.addPoint(
        GpsPoint(
          latitude: 10.763522,
          longitude: 106.660172,
          accuracyMeters: 9,
          recordedAt: DateTime(2026, 11, 25, 8, 0, 30),
        ),
      );

      expect(tracker.route, hasLength(2));
      expect(tracker.estimatedDistanceMeters, greaterThan(90));
      expect(tracker.estimatedDistanceMeters, lessThan(110));
    });

    test('pause and resume exclude paused time from duration', () {
      final tracker = ActivitySessionTracker();
      final started = DateTime(2026, 11, 25, 8);
      tracker.start(started);
      tracker.pause(started.add(const Duration(minutes: 5)));
      tracker.resume(started.add(const Duration(minutes: 20)));

      final duration = tracker.durationAt(
        started.add(const Duration(minutes: 30)),
      );

      expect(duration, const Duration(minutes: 15));
    });

    test('does not accept or add points while paused', () {
      final tracker = ActivitySessionTracker();
      final started = DateTime(2026, 11, 25, 8);
      tracker.start(started);
      tracker.pause(started.add(const Duration(minutes: 1)));

      final accepted = tracker.addPoint(
        GpsPoint(
          latitude: 10.762622,
          longitude: 106.660172,
          accuracyMeters: 5,
          recordedAt: started.add(const Duration(minutes: 2)),
        ),
      );

      expect(accepted, isNull);
      expect(tracker.route, isEmpty);
    });

    test('does not add distance across pause and resume', () {
      final tracker = ActivitySessionTracker();
      final started = DateTime(2026, 11, 25, 8);
      tracker.start(started);

      tracker.addPoint(
        GpsPoint(
          latitude: 10.762622,
          longitude: 106.660172,
          recordedAt: started,
        ),
      );
      tracker.addPoint(
        GpsPoint(
          latitude: 10.763522,
          longitude: 106.660172,
          recordedAt: started.add(const Duration(seconds: 30)),
        ),
      );
      final firstSegmentDistance = tracker.estimatedDistanceMeters;

      tracker.pause(started.add(const Duration(minutes: 1)));
      tracker.resume(started.add(const Duration(minutes: 20)));
      tracker.addPoint(
        GpsPoint(
          latitude: 10.770000,
          longitude: 106.670000,
          recordedAt: started.add(const Duration(minutes: 21)),
        ),
      );
      tracker.addPoint(
        GpsPoint(
          latitude: 10.770900,
          longitude: 106.670000,
          recordedAt: started.add(const Duration(minutes: 21, seconds: 30)),
        ),
      );

      expect(
        tracker.estimatedDistanceMeters,
        greaterThan(firstSegmentDistance + 90),
      );
      expect(
        tracker.estimatedDistanceMeters,
        lessThan(firstSegmentDistance + 110),
      );
    });

    test('stop freezes duration while recording', () {
      final tracker = ActivitySessionTracker();
      final started = DateTime(2026, 11, 25, 8);
      tracker.start(started);
      final stopped = started.add(const Duration(minutes: 10));
      tracker.stop(stopped);

      expect(
        tracker.durationAt(started.add(const Duration(minutes: 30))),
        const Duration(minutes: 10),
      );
    });

    test('stop while paused includes the final pause duration', () {
      final tracker = ActivitySessionTracker();
      final started = DateTime(2026, 11, 25, 8);
      tracker.start(started);
      tracker.pause(started.add(const Duration(minutes: 5)));
      tracker.stop(started.add(const Duration(minutes: 25)));

      expect(tracker.pausedDuration, const Duration(minutes: 20));
      expect(
        tracker.durationAt(started.add(const Duration(hours: 1))),
        const Duration(minutes: 5),
      );
    });

    test('GPS save respects routeSaved setting', () async {
      final repository = InMemoryActivityRepository();
      final controller = ActivityController(
        repository: repository,
        ownerUid: 'route-test-user',
      );
      final started = DateTime(2026, 11, 25, 8);
      controller.startGps(started);
      controller.addGpsPoint(
        GpsPoint(
          latitude: 10.762622,
          longitude: 106.660172,
          recordedAt: started,
        ),
      );
      controller.stopGps(started.add(const Duration(minutes: 5)));
      await controller.saveGpsSession(started.add(const Duration(minutes: 30)));

      var sessions = await repository.getSessions(ownerUid: 'route-test-user');
      expect(sessions.single.routeSaved, isFalse);
      expect(sessions.single.route, isEmpty);

      controller.resetGps();
      controller.startGps(started);
      controller.setRouteSaved(true);
      controller.addGpsPoint(
        GpsPoint(
          latitude: 10.762622,
          longitude: 106.660172,
          recordedAt: started,
        ),
      );
      controller.stopGps(started.add(const Duration(minutes: 5)));
      await controller.saveGpsSession(started.add(const Duration(minutes: 30)));

      sessions = await repository.getSessions(ownerUid: 'route-test-user');
      expect(sessions, hasLength(2));
      expect(sessions.first.routeSaved, isTrue);
      expect(sessions.first.route, isNotEmpty);
    });

    test('in-memory repository can save and load sessions', () async {
      const owner = 'user-8';
      final repository = InMemoryActivityRepository();
      final session = ActivitySession(
        id: 'session-1',
        ownerUid: owner,
        activityName: 'Đi bộ',
        durationSeconds: 1200,
        estimatedDistanceMeters: 1500,
        feeling: 'Thoải mái',
        routeSaved: false,
        startedAt: DateTime(2026, 11, 25, 7),
        endedAt: DateTime(2026, 11, 25, 7, 20),
        route: const [],
      );

      await repository.saveSession(session);

      expect(await repository.getSessions(ownerUid: owner), [session]);
    });
  });
}
