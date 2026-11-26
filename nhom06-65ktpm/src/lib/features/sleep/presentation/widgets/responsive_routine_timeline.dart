import 'package:flutter/material.dart';

import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/routine_block.dart';

/// Giao diện lịch sinh hoạt 24 giờ responsive cho cả Android và Web.
///
/// Hiển thị trực quan trục giờ 00:00 → 24:00 cùng các khối:
/// - Ca làm việc (hỗ trợ tách đoạn qua nửa đêm, ví dụ ca đêm 22:00–06:00).
/// - Khoảng bận cố định.
/// - Khoảng ngủ mong muốn (cả ban đêm lẫn ban ngày).
/// - Giấc ngủ đã ghi nhận (tự tách đoạn nếu qua mốc 00:00).
class ResponsiveRoutineTimeline extends StatelessWidget {
  final DateTime selectedDate;
  final List<DailyTimelineSegment> segments;
  final List<String> conflictWarnings;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final VoidCallback onSelectToday;

  const ResponsiveRoutineTimeline({
    super.key,
    required this.selectedDate,
    required this.segments,
    this.conflictWarnings = const [],
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onSelectToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateLabel = DateHelper.formatVietnameseDate(selectedDate);

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
            // Header điều hướng ngày
            Row(
              children: [
                Icon(Icons.view_timeline_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lịch sinh hoạt 24 giờ',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Chuyển về hôm nay',
                  child: TextButton(
                    onPressed: onSelectToday,
                    child: const Text('Hôm nay'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Xem lịch ngày hôm trước',
                  child: IconButton(
                    tooltip: 'Ngày trước (Alt + ←)',
                    onPressed: onPreviousDay,
                    icon: const Icon(Icons.chevron_left),
                  ),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    label: 'Đang xem lịch sinh hoạt ngày $dateLabel',
                    child: Text(
                      dateLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Xem lịch ngày tiếp theo',
                  child: IconButton(
                    tooltip: 'Ngày sau (Alt + →)',
                    onPressed: onNextDay,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
              ],
            ),

            // Chú giải màu
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: RoutineBlockKind.values
                  .map(
                    (kind) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _colorForKind(kind, colorScheme),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(kind.label, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  )
                  .toList(),
            ),

            // Cảnh báo xung đột ca làm vs khoảng ngủ mong muốn (nếu có)
            if (conflictWarnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final warning in conflictWarnings)
                Semantics(
                  liveRegion: true,
                  label: 'Cảnh báo lịch: $warning',
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            warning,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 12),
            // Thanh trục 24 giờ trực quan (00h -> 06h -> 12h -> 18h -> 24h)
            _Day24HourBar(segments: segments),
            const SizedBox(height: 14),

            // Danh sách chi tiết các đoạn thời gian trong ngày
            if (segments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Chưa có khối lịch hoặc giấc ngủ nào trong ngày này.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Column(
                children: segments.map((seg) {
                  final accent = _colorForKind(seg.kind, colorScheme);
                  final semanticText =
                      '${seg.kind.label}: ${seg.title}, thời gian ${seg.formattedRange}'
                      '${seg.subtitle != null ? ', ${seg.subtitle}' : ''}';

                  return Semantics(
                    container: true,
                    label: semanticText,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 36,
                            margin: const EdgeInsets.only(right: 10, top: 2),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          SizedBox(
                            width: 112,
                            child: Text(
                              seg.formattedRange,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  seg.title,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (seg.subtitle != null)
                                  Text(
                                    seg.subtitle!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                if (seg.continuedFromPreviousDay ||
                                    seg.continuesToNextDay)
                                  Text(
                                    seg.continuedFromPreviousDay
                                        ? 'Tiếp nối từ ngày hôm trước qua mốc 00:00'
                                        : 'Kéo dài sang ngày kế tiếp sau 24:00',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.tertiary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  static Color _colorForKind(RoutineBlockKind kind, ColorScheme scheme) {
    switch (kind) {
      case RoutineBlockKind.workShift:
        return Colors.deepOrange.shade600;
      case RoutineBlockKind.busy:
        return Colors.blueGrey.shade600;
      case RoutineBlockKind.sleepTarget:
        return scheme.tertiary;
      case RoutineBlockKind.sleepLogged:
        return scheme.primary;
    }
  }
}

/// Thanh trục 24 giờ thu gọn hiển thị tỉ lệ phân bố giấc ngủ và ca làm trong ngày.
class _Day24HourBar extends StatelessWidget {
  final List<DailyTimelineSegment> segments;

  const _Day24HourBar({required this.segments});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Container(
              height: 28,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: segments.map((seg) {
                  final left = (seg.startMinute / 1440.0) * width;
                  final segWidth =
                      ((seg.durationMinutes / 1440.0) * width).clamp(4.0, width);
                  final isTarget = seg.kind == RoutineBlockKind.sleepTarget;
                  final color =
                      ResponsiveRoutineTimeline._colorForKind(seg.kind, scheme);

                  return Positioned(
                    left: left,
                    top: isTarget ? 2 : 5,
                    bottom: isTarget ? 2 : 5,
                    width: segWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isTarget
                            ? color.withValues(alpha: 0.25)
                            : color.withValues(alpha: 0.85),
                        border: isTarget
                            ? Border.all(color: color, width: 1.5)
                            : null,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['00:00', '06:00', '12:00', '18:00', '24:00']
              .map(
                (mark) => Text(
                  mark,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
