import 'package:flutter/material.dart';

import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/sleep_window.dart';
import '../../domain/logic/sleep_schedule_analyzer.dart';

/// Thẻ tổng quan giấc ngủ 7 ngày và khoảng ngủ mong muốn do người dùng tự đặt.
///
/// Ngày không có dữ liệu được hiển thị trung tính ("Chưa ghi nhận"), không đánh dấu thất bại.
class SleepSummaryCard extends StatelessWidget {
  final SleepWeeklySummary summary;
  final SleepWindow? sleepWindow;
  final VoidCallback onEditSleepWindow;

  const SleepSummaryCard({
    super.key,
    required this.summary,
    required this.sleepWindow,
    required this.onEditSleepWindow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hàng 1: Khoảng ngủ mong muốn
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bedtime_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khoảng ngủ mong muốn',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (sleepWindow != null) ...[
                        Text(
                          '${sleepWindow!.formattedRange} (${sleepWindow!.formattedDuration})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (sleepWindow!.label != null &&
                            sleepWindow!.label!.isNotEmpty)
                          Text(
                            sleepWindow!.label!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ] else
                        Text(
                          'Chưa đặt khung giờ cố định — bạn tự do chọn kể cả ca đêm.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: sleepWindow == null
                      ? 'Đặt khoảng ngủ mong muốn'
                      : 'Chỉnh sửa khoảng ngủ mong muốn',
                  child: OutlinedButton.icon(
                    onPressed: onEditSleepWindow,
                    icon: const Icon(Icons.tune, size: 16),
                    label: Text(sleepWindow == null ? 'Thiết lập' : 'Đổi khung'),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Hàng 2: 3 chỉ số tổng hợp 7 ngày
            Text(
              'Tính đều đặn 7 ngày gần nhất',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricChip(
                  icon: Icons.schedule,
                  label: 'Trung bình',
                  value: summary.formattedAverageDuration,
                  semanticLabel:
                      'Thời lượng ngủ trung bình: ${summary.formattedAverageDuration}',
                ),
                _MetricChip(
                  icon: Icons.wb_sunny_outlined,
                  label: 'Tỉnh táo tự đánh giá',
                  value: summary.averageAlertnessScore == null
                      ? 'Chưa có'
                      : '${summary.averageAlertnessScore!.toStringAsFixed(1)} / 5',
                  semanticLabel: summary.averageAlertnessScore == null
                      ? 'Mức tỉnh táo trung bình: chưa có dữ liệu'
                      : 'Mức tỉnh táo trung bình ${summary.averageAlertnessScore!.toStringAsFixed(1)} trên 5',
                ),
                _MetricChip(
                  icon: Icons.auto_graph,
                  label: 'Độ đều đặn',
                  value: summary.regularityScore == null
                      ? '${summary.loggedDaysCount}/7 ngày có ghi'
                      : '${summary.regularityScore}% (${summary.loggedDaysCount}/7 ngày)',
                  semanticLabel: summary.regularityScore == null
                      ? 'Đã ghi nhận ${summary.loggedDaysCount} trên 7 ngày'
                      : 'Độ đều đặn ${summary.regularityScore} phần trăm, ${summary.loggedDaysCount} trên 7 ngày có ghi nhận',
                ),
              ],
            ),
            if (summary.averageBedtimeDeviationMinutes != null) ...[
              const SizedBox(height: 8),
              Text(
                'Độ lệch giờ đi ngủ trung bình so với khoảng mong muốn: '
                '${summary.averageBedtimeDeviationMinutes} phút.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),

            // Hàng 3: Biểu đồ cột 7 ngày (ngày trống hiển thị trung tính, không báo đỏ thất bại)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: summary.days.map((day) {
                final dayLabel =
                    DateHelper.weekdayToVietnamese(day.date.weekday, short: true);
                final hours = day.totalMinutes / 60.0;
                final barHeight = day.hasData
                    ? (hours.clamp(1.0, 12.0) / 12.0 * 48.0)
                    : 6.0;
                final semanticDesc = day.hasData
                    ? '$dayLabel: đã ghi nhận ${hours.toStringAsFixed(1)} giờ ngủ'
                    : '$dayLabel: chưa ghi nhận giấc ngủ';

                return Expanded(
                  child: Semantics(
                    label: semanticDesc,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          day.hasData ? '${hours.toStringAsFixed(1)}h' : '—',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: day.hasData
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 18,
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: day.hasData
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dayLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'Ký hiệu "—" là ngày chưa ghi nhận dữ liệu (không tính là thất bại).',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String semanticLabel;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
