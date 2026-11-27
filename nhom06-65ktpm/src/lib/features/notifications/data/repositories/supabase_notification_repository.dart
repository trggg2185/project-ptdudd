import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/approved_plan_reminder_item.dart';
import '../../domain/entities/reminder_preferences.dart';
import '../../domain/entities/scheduled_reminder.dart';
import '../../domain/repositories/notification_repository.dart';
import '../fixtures/sample_notification_fixture.dart';

/// Triển khai `NotificationRepository` kết nối trực tiếp schema Supabase đã triển khai:
/// - `public.reminder_preferences` (`owner_uid`, `quiet_hours_start`, `quiet_hours_end`,
///   `reminders_enabled`, `timezone`, `version`)
/// - `public.plans` & `public.plan_items` (đọc trạng thái `approved`/`draft`/`completed`/`skipped`)
/// - `public.device_tokens` (`owner_uid`, `token`, `platform`, `is_active` — hủy kích hoạt khi đăng xuất)
class SupabaseNotificationRepository implements NotificationRepository {
  final SupabaseClient? _client;

  SupabaseNotificationRepository({SupabaseClient? client})
    : _client = client ?? _tryDefaultClient();

  static SupabaseClient? _tryDefaultClient() {
    try {
      return Supabase.instance.isInitialized ? Supabase.instance.client : null;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const NotificationSyncException(
        'Chưa khởi tạo kết nối Supabase. Vui lòng kiểm tra phiên đăng nhập hoặc mạng.',
      );
    }
    return client;
  }

  Future<void> _ensureProfileRow(SupabaseClient client, String ownerUid) async {
    await client
        .from('profiles')
        .upsert(
          {'owner_uid': ownerUid},
          onConflict: 'owner_uid',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<ReminderPreferences> getPreferences(String ownerUid) async {
    final client = _requireClient();
    try {
      final row = await client
          .from('reminder_preferences')
          .select()
          .eq('owner_uid', ownerUid)
          .maybeSingle();
      if (row == null) {
        return SampleNotificationFixture.defaultPreferences(ownerUid);
      }
      return ReminderPreferences.fromSupabaseMap(
        Map<String, dynamic>.from(row),
      );
    } catch (error) {
      throw NotificationSyncException(
        'Không thể tải cấu hình nhắc lịch từ Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<ReminderPreferences> savePreferences(
    ReminderPreferences preferences, {
    int? expectedVersion,
  }) async {
    preferences.validate();
    final client = _requireClient();
    try {
      await _ensureProfileRow(client, preferences.ownerUid);

      final existingRow = await client
          .from('reminder_preferences')
          .select()
          .eq('owner_uid', preferences.ownerUid)
          .maybeSingle();

      if (existingRow == null) {
        final inserted = await client
            .from('reminder_preferences')
            .insert({
              'owner_uid': preferences.ownerUid,
              'reminders_enabled': preferences.remindersEnabled,
              'quiet_hours_start': ReminderPreferences.formatPostgresTime(
                preferences.quietHoursStartMinute,
              ),
              'quiet_hours_end': ReminderPreferences.formatPostgresTime(
                preferences.quietHoursEndMinute,
              ),
              'timezone': preferences.timezone,
              'version': 1,
            })
            .select()
            .single();
        return ReminderPreferences.fromSupabaseMap(
          Map<String, dynamic>.from(inserted),
        ).copyWith(
          hideHealthDetailsOnLockScreen:
              preferences.hideHealthDetailsOnLockScreen,
          defaultSnoozeMinutes: preferences.defaultSnoozeMinutes,
        );
      }

      final current = ReminderPreferences.fromSupabaseMap(
        Map<String, dynamic>.from(existingRow),
      );
      final targetVersion = expectedVersion ?? current.version;
      if (current.version != targetVersion) {
        throw NotificationConflictException(
          'Cấu hình nhắc lịch đã thay đổi trên thiết bị khác. Vui lòng tải lại trước khi lưu.',
          serverVersion: current.version,
          serverPreferences: current,
        );
      }

      final updated = await client
          .from('reminder_preferences')
          .update({
            'reminders_enabled': preferences.remindersEnabled,
            'quiet_hours_start': ReminderPreferences.formatPostgresTime(
              preferences.quietHoursStartMinute,
            ),
            'quiet_hours_end': ReminderPreferences.formatPostgresTime(
              preferences.quietHoursEndMinute,
            ),
            'timezone': preferences.timezone,
            'version': targetVersion + 1,
          })
          .eq('owner_uid', preferences.ownerUid)
          .eq('version', targetVersion)
          .select()
          .maybeSingle();

      if (updated == null) {
        final latestRow = await client
            .from('reminder_preferences')
            .select()
            .eq('owner_uid', preferences.ownerUid)
            .maybeSingle();
        final latest = latestRow == null
            ? null
            : ReminderPreferences.fromSupabaseMap(
                Map<String, dynamic>.from(latestRow),
              );
        throw NotificationConflictException(
          'Cấu hình nhắc lịch đang được cập nhật đồng thời từ thiết bị khác. Vui lòng thử lại.',
          serverVersion: latest?.version,
          serverPreferences: latest,
        );
      }

      return ReminderPreferences.fromSupabaseMap(
        Map<String, dynamic>.from(updated),
      ).copyWith(
        hideHealthDetailsOnLockScreen:
            preferences.hideHealthDetailsOnLockScreen,
        defaultSnoozeMinutes: preferences.defaultSnoozeMinutes,
      );
    } on NotificationSyncException {
      rethrow;
    } catch (error) {
      throw NotificationSyncException(
        'Không thể lưu cấu hình nhắc lịch lên Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<List<ApprovedPlanReminderItem>> getPlanItems(String ownerUid) async {
    final client = _requireClient();
    try {
      final plansRows = await client
          .from('plans')
          .select('id, status')
          .eq('owner_uid', ownerUid);
      final planStatusById = <String, PlanApprovalStatus>{};
      for (final raw in plansRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        planStatusById[row['id'] as String] = PlanApprovalStatus.fromDb(
          row['status'] as String?,
        );
      }

      final itemRows = await client
          .from('plan_items')
          .select()
          .eq('owner_uid', ownerUid)
          .order('start_at');

      return (itemRows as List).map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final planId = row['plan_id'] as String;
        final itemType = ReminderItemType.fromDb(row['item_type'] as String?);
        final reason = (row['recommendation_reason'] as String?)?.trim();
        final title = (reason != null && reason.isNotEmpty)
            ? reason
            : '${itemType.displayLabel} theo lịch đã duyệt';

        return ApprovedPlanReminderItem(
          itemId: row['id'] as String,
          planId: planId,
          ownerUid: ownerUid,
          itemType: itemType,
          title: title,
          startsAt: DateTime.parse(row['start_at'] as String).toUtc(),
          endsAt: row['end_at'] != null
              ? DateTime.parse(row['end_at'] as String).toUtc()
              : null,
          planStatus: planStatusById[planId] ?? PlanApprovalStatus.draft,
          itemStatus: PlanItemStatus.fromDb(row['status'] as String?),
          recommendationReason: reason,
          version: (row['version'] as num?)?.toInt() ?? 1,
        );
      }).toList();
    } catch (error) {
      throw NotificationSyncException(
        'Không thể tải danh sách lịch đã duyệt từ Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<void> upsertPlanItem(ApprovedPlanReminderItem item) async {
    final client = _requireClient();
    try {
      await client
          .from('plan_items')
          .update({
            'start_at': item.startsAtUtc.toIso8601String(),
            'end_at': item.endsAtUtc?.toIso8601String(),
            'status': item.itemStatus.name,
            'recommendation_reason': item.recommendationReason,
          })
          .eq('owner_uid', item.ownerUid)
          .eq('id', item.itemId);
    } catch (error) {
      throw NotificationSyncException(
        'Không thể cập nhật mục lịch trên Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<void> deletePlanItem({
    required String ownerUid,
    required String itemId,
  }) async {
    final client = _requireClient();
    try {
      await client
          .from('plan_items')
          .delete()
          .eq('owner_uid', ownerUid)
          .eq('id', itemId);
    } catch (error) {
      throw NotificationSyncException(
        'Không thể xóa mục lịch trên Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<List<DeviceTokenRecord>> getDeviceTokens(String ownerUid) async {
    final client = _requireClient();
    try {
      final rows = await client
          .from('device_tokens')
          .select()
          .eq('owner_uid', ownerUid);
      return (rows as List)
          .map(
            (r) => DeviceTokenRecord.fromSupabaseMap(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList();
    } catch (error) {
      throw NotificationSyncException(
        'Không thể đọc danh sách thiết bị từ Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<void> registerDeviceToken({
    required String ownerUid,
    required String token,
    required String platform,
  }) async {
    if (token.trim().isEmpty) return;
    final client = _requireClient();
    try {
      await _ensureProfileRow(client, ownerUid);
      await client.from('device_tokens').upsert({
        'owner_uid': ownerUid,
        'token': token.trim(),
        'platform': platform,
        'is_active': true,
      }, onConflict: 'owner_uid,token');
    } catch (error) {
      throw NotificationSyncException(
        'Không thể cập nhật token thiết bị trên Supabase.',
        cause: error,
      );
    }
  }

  @override
  Future<void> deactivateDeviceTokens(String ownerUid, {String? token}) async {
    final client = _requireClient();
    try {
      var query = client
          .from('device_tokens')
          .update({'is_active': false})
          .eq('owner_uid', ownerUid);
      if (token != null && token.trim().isNotEmpty) {
        query = query.eq('token', token.trim());
      }
      await query;
    } catch (error) {
      throw NotificationSyncException(
        'Không thể hủy liên kết token thiết bị trên Supabase.',
        cause: error,
      );
    }
  }
}
