import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/health_profile.dart';
import '../domain/profile_repository.dart';
import '../domain/profile_time.dart';
import '../domain/schedule_block.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client, this._ownerUid);

  final SupabaseClient _client;
  final String _ownerUid;
  static const _preferenceKey = 'healthylife_profile';

  @override
  Future<ProfileData> load() async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('owner_uid', _ownerUid)
        .maybeSingle();
    final profile = _readProfile(row);
    final rows = await _client
        .from('availability_blocks')
        .select()
        .eq('owner_uid', _ownerUid)
        .order('start_at');
    return (
      profile: profile,
      blocks: rows.map((row) => _readBlock(row, profile.timeZone)).toList(),
    );
  }

  @override
  Future<void> saveProfile(HealthProfile profile) async {
    profile.validate();
    await _ensureProfile();
    final current = await _client
        .from('profiles')
        .select('living_conditions, updated_at')
        .eq('owner_uid', _ownerUid)
        .single();
    final otherConditions = _map(current['living_conditions']);
    final written = await _client
        .from('profiles')
        .update({
          'age_group': profile.adultConfirmed ? '18_plus' : null,
          'timezone': profile.timeZone ?? defaultProfileZone,
          'occupation': profile.occupation,
          'living_conditions': {
            ...otherConditions,
            _preferenceKey: _profilePreferences(profile),
          },
        })
        .eq('owner_uid', _ownerUid)
        .eq('updated_at', current['updated_at'] as String)
        .select('owner_uid')
        .maybeSingle();
    if (written == null) throw StateError('Profile changed while saving');
  }

  @override
  Future<void> saveBlock(ScheduleBlock block) async {
    block.validate();
    await _ensureProfile();
    await _client.from('availability_blocks').upsert({
      'id': block.id,
      'owner_uid': _ownerUid,
      'title': block.title,
      'start_at': block.startsAt.toIso8601String(),
      'end_at': block.endsAt.toIso8601String(),
      'travel_minutes': block.travelMinutes,
      'recurrence_rule': jsonEncode({
        'kind': block.kind.name,
        'timezone': block.timeZone,
        'weekly': block.repeatsWeekly,
      }),
      'exception_dates': block.exceptionDates.map(calendarDateKey).toList(),
    }, onConflict: 'id');
  }

  @override
  Future<void> deleteBlock(String id) async {
    await _client
        .from('availability_blocks')
        .delete()
        .eq('owner_uid', _ownerUid)
        .eq('id', id);
  }

  Future<void> _ensureProfile() async {
    await _client
        .from('profiles')
        .upsert(
          {'owner_uid': _ownerUid},
          onConflict: 'owner_uid',
          ignoreDuplicates: true,
        );
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map<String, dynamic> ? value : const {};

  static Iterable<String> _strings(Object? value) =>
      value is List ? value.whereType<String>() : const [];

  static T? _enumValue<T extends Enum>(Iterable<T> options, Object? code) {
    for (final option in options) {
      if (option.name == code) return option;
    }
    return null;
  }

  static HealthProfile _readProfile(Map<String, dynamic>? row) {
    final stored = _map(_map(row?['living_conditions'])[_preferenceKey]);
    return HealthProfile(
      adultConfirmed: stored['adult_confirmed'] == true,
      requiresProfessionalGuidance: stored['requires_guidance'] == true,
      timeZone:
          (stored.isEmpty ? (row?['timezone']) : stored['timezone']) as String?,
      occupation: row?['occupation'] as String?,
      goal: ProfileGoal.fromCode(stored['goal']),
      activityLevel: _enumValue(ActivityLevel.values, stored['activity_level']),
      sessionMinutes: stored['session_minutes'] as int?,
      sessionsPerWeek: stored['sessions_per_week'] as int?,
      exerciseBudget: stored['exercise_budget'] as int?,
      mealBudget: stored['meal_budget'] as int?,
      sleepStart: stored['sleep_start'] as int?,
      sleepEnd: stored['sleep_end'] as int?,
      allergyStatus:
          _enumValue(AllergyStatus.values, stored['allergy_status']) ??
          AllergyStatus.unconfirmed,
      equipment: _strings(stored['equipment']),
      preferredSports: _strings(stored['preferred_sports']),
      dislikedSports: _strings(stored['disliked_sports']),
      movementLimits: _strings(stored['movement_limits']),
      allergens: _strings(stored['allergens']),
      avoidedIngredients: _strings(stored['avoided_ingredients']),
    );
  }

  static Map<String, Object?> _profilePreferences(HealthProfile profile) => {
    'adult_confirmed': profile.adultConfirmed,
    'requires_guidance': profile.requiresProfessionalGuidance,
    'timezone': profile.timeZone,
    'goal': profile.goal?.code,
    'activity_level': profile.activityLevel?.name,
    'session_minutes': profile.sessionMinutes,
    'sessions_per_week': profile.sessionsPerWeek,
    'exercise_budget': profile.exerciseBudget,
    'meal_budget': profile.mealBudget,
    'sleep_start': profile.sleepStart,
    'sleep_end': profile.sleepEnd,
    'allergy_status': profile.allergyStatus.name,
    'equipment': profile.equipment.toList(),
    'preferred_sports': profile.preferredSports.toList(),
    'disliked_sports': profile.dislikedSports.toList(),
    'movement_limits': profile.movementLimits.toList(),
    'allergens': profile.allergyStatus == AllergyStatus.declared
        ? profile.allergens.toList()
        : [],
    'avoided_ingredients': profile.avoidedIngredients.toList(),
  };

  static ScheduleBlock _readBlock(
    Map<String, dynamic> row,
    String? preferredZone,
  ) {
    final raw = row['recurrence_rule'] as String?;
    Map<String, dynamic> metadata = const {};
    if (raw != null && raw.trimLeft().startsWith('{')) {
      metadata = _map(jsonDecode(raw));
    }
    final blockZone = metadata['timezone'] as String? ?? preferredZone;
    return ScheduleBlock(
      id: row['id'] as String,
      kind:
          _enumValue(ScheduleKind.values, metadata['kind']) ??
          ScheduleKind.busy,
      title: row['title'] as String? ?? 'Khoảng bận',
      timeZone: profileLocation(blockZone) == null
          ? defaultProfileZone
          : blockZone!,
      startsAt: DateTime.parse(row['start_at'] as String),
      endsAt: DateTime.parse(row['end_at'] as String),
      travelMinutes: row['travel_minutes'] as int? ?? 0,
      repeatsWeekly: metadata['weekly'] == true || raw == 'FREQ=WEEKLY',
      exceptionDates: _strings(row['exception_dates']).map(DateTime.parse),
    );
  }
}
