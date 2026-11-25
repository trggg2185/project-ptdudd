import '../../domain/entities/activity_session.dart';
import '../../domain/repositories/activity_repository.dart';

class InMemoryActivityRepository implements ActivityRepository {
  final Map<String, List<ActivitySession>> _sessions = {};

  @override
  Future<void> saveSession(ActivitySession session) async {
    final sessions = _sessions.putIfAbsent(session.ownerUid, () => []);
    sessions.removeWhere((item) => item.id == session.id);
    sessions.insert(0, session);
  }

  @override
  Future<List<ActivitySession>> getSessions({required String ownerUid}) async =>
      List.unmodifiable(_sessions[ownerUid] ?? const []);
}
