import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/weekly_plan.dart';
import '../domain/weekly_plan_repository.dart';

class SupabaseWeeklyPlanRepository implements WeeklyPlanRepository {
  const SupabaseWeeklyPlanRepository(this._client, this._ownerUid);

  final SupabaseClient _client;
  final String _ownerUid;

  @override
  Future<WeeklyPlan?> load(PlanWeek week) async {
    final row = await _client
        .from('plans')
        .select('*, plan_items(*)')
        .eq('owner_uid', _ownerUid)
        .eq('week_start', week.key)
        .eq('status', 'approved')
        .maybeSingle();
    return row == null ? null : _readPlan(row);
  }

  @override
  Future<WeeklyPlan> approve({
    required PlanWeek week,
    required int? expectedVersion,
    required List<PlanItem> items,
  }) => _change('approve_weekly_plan', {
    'p_week_start': week.key,
    'p_timezone': week.timeZone,
    'p_expected_version': expectedVersion,
    'p_items': items.map(_itemPayload).toList(growable: false),
  });

  @override
  Future<WeeklyPlan> recordOutcome({
    required PlanWeek week,
    required int expectedVersion,
    required String itemId,
    required PlanItemStatus outcome,
  }) => _change('record_weekly_plan_outcome', {
    'p_week_start': week.key,
    'p_expected_version': expectedVersion,
    'p_item_id': itemId,
    'p_outcome': outcome.name,
  });

  Future<WeeklyPlan> _change(
    String function,
    Map<String, Object?> params,
  ) async {
    try {
      final row = await _client.rpc(
        function,
        params: {'p_expected_owner_uid': _ownerUid, ...params},
      );
      return _readPlan(Map<String, dynamic>.from(row as Map));
    } on PostgrestException catch (error) {
      throw PlannerSaveException(switch (error.code) {
        '40001' => 'Lịch đã thay đổi. Hãy tải lại lịch trước khi thử lại.',
        '22023' =>
          'Một khoảng giờ không còn hợp lệ. Hãy tải lại lịch và kiểm tra giờ.',
        'PGRST202' =>
          'Supabase nhóm cần migration lập lịch tuần để lưu thay đổi.',
        _ => 'Không thể cập nhật lịch tuần. Hãy thử lại.',
      });
    }
  }

  static Map<String, Object?> _itemPayload(PlanItem item) => {
    'id': item.id,
    'item_type': item.kind.name,
    'title': item.title,
    'start_at': item.startsAt.toUtc().toIso8601String(),
    'end_at': item.endsAt.toUtc().toIso8601String(),
    'is_locked': item.isLocked,
    'recommendation_reason': item.reason,
    'meal_type': item.mealType,
  };

  static WeeklyPlan _readPlan(Map<String, dynamic> row) {
    final items = (row['plan_items'] as List).map((rawItem) {
      final item = rawItem as Map<String, dynamic>;
      final kind = PlanItemKind.values.byName(item['item_type'] as String);
      final start = DateTime.parse(item['start_at'] as String);
      return PlanItem(
        id: item['id'] as String,
        kind: kind,
        title: (item['title'] as String?) ?? kind.label,
        startsAt: start,
        endsAt: item['end_at'] == null
            ? start.add(const Duration(minutes: 1))
            : DateTime.parse(item['end_at'] as String),
        status: PlanItemStatus.values.byName(item['status'] as String),
        isLocked: item['is_locked'] == true,
        reason: item['recommendation_reason'] as String?,
        mealType: item['meal_type'] as String?,
      );
    }).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    return WeeklyPlan(version: row['version'] as int, items: items);
  }
}
