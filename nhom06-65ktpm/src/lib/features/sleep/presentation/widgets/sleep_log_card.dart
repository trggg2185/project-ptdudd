import 'package:flutter/material.dart';

import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/sleep_log.dart';

/// Thẻ hiển thị một bản ghi nhật ký giấc ngủ tự khai báo.
class SleepLogCard extends StatelessWidget {
  final SleepLog log;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const SleepLogCard({
    super.key,
    required this.log,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final start = log.sleptAt.toLocal();
    final end = log.wokeAt.toLocal();

    final startClock = _formatClock(start);
    final endClock = _formatClock(end);
    final startDateLabel = DateHelper.formatVietnameseDate(start);
    final endDateSuffix = log.crossesMidnight
        ? ' (+1 ngày, ${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')})'
        : '';

    final semanticDescription =
        'Nhật ký ngủ ngày $startDateLabel, từ $startClock đến $endClock$endDateSuffix, '
        'thời lượng ${log.formattedDuration}, mức tỉnh táo ${log.alertness.label}.';

    return Semantics(
      container: true,
      label: semanticDescription,
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          startDateLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$startClock – $endClock$endDateSuffix',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Chỉnh sửa nhật ký ngủ $startClock đến $endClock',
                    child: IconButton(
                      tooltip: 'Chỉnh sửa',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: onEdit,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Xóa nhật ký ngủ $startClock đến $endClock',
                    child: IconButton(
                      tooltip: 'Xóa',
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: colorScheme.error,
                      ),
                      onPressed: onDelete,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Badge(
                    icon: Icons.timelapse,
                    text: log.formattedDuration,
                    background: colorScheme.primaryContainer,
                    foreground: colorScheme.onPrimaryContainer,
                  ),
                  _Badge(
                    icon: _alertnessIcon(log.alertness),
                    text: '${log.alertness.score}/5 • ${log.alertness.label}',
                    background: colorScheme.secondaryContainer,
                    foreground: colorScheme.onSecondaryContainer,
                  ),
                  if (log.crossesMidnight)
                    _Badge(
                      icon: Icons.nights_stay_outlined,
                      text: 'Qua nửa đêm',
                      background: colorScheme.tertiaryContainer,
                      foreground: colorScheme.onTertiaryContainer,
                    ),
                  if (log.isDaytimeSleep)
                    _Badge(
                      icon: Icons.wb_twilight_outlined,
                      text: 'Ngủ ban ngày (ca đêm)',
                      background: colorScheme.tertiaryContainer,
                      foreground: colorScheme.onTertiaryContainer,
                    ),
                ],
              ),
              if (log.note != null && log.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  log.note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatClock(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static IconData _alertnessIcon(AlertnessLevel level) {
    switch (level) {
      case AlertnessLevel.veryGroggy:
        return Icons.battery_1_bar;
      case AlertnessLevel.groggy:
        return Icons.battery_3_bar;
      case AlertnessLevel.neutral:
        return Icons.battery_4_bar;
      case AlertnessLevel.refreshed:
        return Icons.battery_6_bar;
      case AlertnessLevel.energized:
        return Icons.bolt;
    }
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  const _Badge({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
