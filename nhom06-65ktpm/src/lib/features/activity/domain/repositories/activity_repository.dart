import '../entities/activity_session.dart';

abstract class ActivityRepository {
  Future<void> saveSession(ActivitySession session);
  Future<List<ActivitySession>> getSessions({required String ownerUid});
}
