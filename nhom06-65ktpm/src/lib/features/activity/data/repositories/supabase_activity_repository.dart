import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/activity_session.dart';
import '../../domain/repositories/activity_repository.dart';

class SupabaseActivityRepository implements ActivityRepository {
  SupabaseActivityRepository({SupabaseClient? client})
    : _client = client ?? _resolveClient();

  static SupabaseClient? _resolveClient() {
    try {
      if (Supabase.instance.isInitialized) {
        return Supabase.instance.client;
      }
    } catch (_) {}
    return null;
  }

  final SupabaseClient? _client;
  static const Uuid _uuid = Uuid();

  @override
  Future<void> saveSession(ActivitySession session) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase chưa được khởi tạo');
    }
    await client
        .from('profiles')
        .upsert(
          {'owner_uid': session.ownerUid},
          onConflict: 'owner_uid',
          ignoreDuplicates: true,
        );
    final explicitSource = switch (session.resolvedSource) {
      ActivityInputSource.manual => 'manual',
      ActivityInputSource.gps => 'gps',
      ActivityInputSource.unknown => null,
    };
    final basePayload = <String, dynamic>{
      'id': session.id,
      'owner_uid': session.ownerUid,
      'activity_name': session.activityName,
      'started_at': session.startedAt.toUtc().toIso8601String(),
      'ended_at': session.endedAt.toUtc().toIso8601String(),
      'duration_seconds': session.durationSeconds,
      'estimated_distance_meters': session.estimatedDistanceMeters,
      'feeling': session.feeling,
      'route_saved': false,
    };
    try {
      await client.from('activity_sessions').upsert({
        ...basePayload,
        'input_source': ?explicitSource,
      });
    } on PostgrestException catch (error) {
      // Tương thích ngược nếu môi trường cloud chưa áp dụng migration 20261128000007.
      final missingInputSourceColumn =
          error.code == 'PGRST204' ||
          error.code == '42703' ||
          error.message.contains('input_source');
      if (explicitSource == null || !missingInputSourceColumn) rethrow;
      await client.from('activity_sessions').upsert(basePayload);
    }

    if (!session.routeSaved || session.route.isEmpty) {
      await client
          .from('route_points')
          .delete()
          .eq('owner_uid', session.ownerUid)
          .eq('session_id', session.id);
      return;
    }

    await client.from('route_points').upsert([
      for (final (index, point) in session.route.indexed)
        {
          'id': _uuid.v5(Namespace.url.value, '${session.id}:$index'),
          'owner_uid': session.ownerUid,
          'session_id': session.id,
          'latitude': point.latitude,
          'longitude': point.longitude,
          'accuracy_meters': point.accuracyMeters,
          'recorded_at': point.recordedAt.toUtc().toIso8601String(),
        },
    ]);
    await client
        .from('activity_sessions')
        .update({'route_saved': true})
        .eq('owner_uid', session.ownerUid)
        .eq('id', session.id);
  }

  @override
  Future<List<ActivitySession>> getSessions({required String ownerUid}) async {
    final client = _client;
    if (client == null) return const [];
    final rows = await client
        .from('activity_sessions')
        .select()
        .eq('owner_uid', ownerUid)
        .order('started_at', ascending: false);
    final sessions = <ActivitySession>[];
    for (final row in rows) {
      final routeSaved = row['route_saved'] as bool? ?? false;
      var route = <GpsPoint>[];
      if (routeSaved) {
        final pointRows = await client
            .from('route_points')
            .select()
            .eq('owner_uid', ownerUid)
            .eq('session_id', row['id'])
            .order('recorded_at');
        route = pointRows
            .map(
              (point) => GpsPoint(
                latitude: (point['latitude'] as num).toDouble(),
                longitude: (point['longitude'] as num).toDouble(),
                accuracyMeters: (point['accuracy_meters'] as num?)?.toDouble(),
                recordedAt: DateTime.parse(point['recorded_at'] as String),
              ),
            )
            .toList();
      }
      final rawDistance = (row['estimated_distance_meters'] as num?)?.toDouble();
      final parsedSource = ActivitySession.parseInputSource(
        row['input_source'],
      );
      final resolvedSource =
          parsedSource ??
          ((routeSaved || route.isNotEmpty || (rawDistance ?? 0) > 0)
              ? ActivityInputSource.gps
              : ActivityInputSource.unknown);
      sessions.add(
        ActivitySession(
          id: row['id'] as String,
          ownerUid: ownerUid,
          activityName: row['activity_name'] as String,
          durationSeconds: (row['duration_seconds'] as num?)?.toInt() ?? 0,
          estimatedDistanceMeters: rawDistance ?? 0,
          feeling: row['feeling'] as String? ?? '',
          routeSaved: routeSaved,
          startedAt: DateTime.parse(row['started_at'] as String),
          endedAt: DateTime.parse(row['ended_at'] as String),
          route: route,
          inputSource: resolvedSource,
        ),
      );
    }
    return sessions;
  }
}
