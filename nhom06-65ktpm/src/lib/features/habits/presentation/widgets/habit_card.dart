import 'package:flutter/material.dart';

import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/entities/streak_info.dart';
import 'skip_reason_dialog.dart';

/// Thẻ hiển thị một thói quen trên danh sách kèm trạng thái check-in trong ngày.
class HabitCard extends StatelessWidget {
  final Habit habit;
  final HabitDayStatus dayStatus;
  final HabitLog? currentLog;
  final StreakInfo streakInfo;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final ValueChanged<String?> onSkip;
  final VoidCallback onUndo;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const HabitCard({
    super.key,
    required this.habit,
    required this.dayStatus,
    this.currentLog,
    required this.streakInfo,
    required this.onTap,
    required this.onComplete,
    required this.onSkip,
    required this.onUndo,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: dayStatus == HabitDayStatus.completed
              ? Colors.green.shade200
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                habit.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  decoration: !habit.isActive
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: !habit.isActive
                                      ? Colors.grey
                                      : null,
                                ),
                              ),
                            ),
                            if (!habit.isActive) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Tạm dừng',
                                  style: TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (habit.description != null && habit.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            habit.description!,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildStreakBadge(),
                  _buildMenuButton(context),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.repeat, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    habit.frequency.displayLabel,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (habit.reminderTime != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.alarm, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      habit.reminderTime!,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                  const Spacer(),
                  _buildActionWidget(context),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreakBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: streakInfo.currentStreak > 0
            ? Colors.deepOrange.withValues(alpha: 0.12)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department,
            size: 16,
            color: streakInfo.currentStreak > 0 ? Colors.deepOrange : Colors.grey,
          ),
          const SizedBox(width: 3),
          Text(
            '${streakInfo.currentStreak}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: streakInfo.currentStreak > 0 ? Colors.deepOrange : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
      onSelected: (val) {
        switch (val) {
          case 'edit':
            onEdit();
            break;
          case 'toggle':
            onToggleActive();
            break;
          case 'delete':
            _confirmDelete(context);
            break;
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('Chỉnh sửa'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(
            children: [
              Icon(habit.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 18),
              SizedBox(width: 8),
              Text(habit.isActive ? 'Tạm dừng' : 'Tiếp tục theo dõi'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Xóa thói quen', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionWidget(BuildContext context) {
    switch (dayStatus) {
      case HabitDayStatus.completed:
        return InkWell(
          onTap: onUndo,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.shade400),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                SizedBox(width: 4),
                Text(
                  'Đã xong',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );

      case HabitDayStatus.skipped:
        return InkWell(
          onTap: onUndo,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.shade400),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pause_circle, color: Colors.orange, size: 16),
                const SizedBox(width: 4),
                Text(
                  currentLog?.reason != null ? 'Bỏ qua' : 'Đã bỏ qua',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );

      case HabitDayStatus.restDay:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Hôm nay nghỉ',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        );

      case HabitDayStatus.missed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Chưa làm',
                style: TextStyle(fontSize: 11, color: Colors.red),
              ),
            ),
            const SizedBox(width: 6),
            _buildCheckInButtons(context),
          ],
        );

      case HabitDayStatus.pending:
        return _buildCheckInButtons(context);
    }
  }

  Widget _buildCheckInButtons(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Bỏ qua có lý do',
          icon: const Icon(Icons.pause_circle_outline, color: Colors.orange, size: 22),
          onPressed: () async {
            final reason = await showDialog<String>(
              context: context,
              builder: (ctx) => SkipReasonDialog(habitName: habit.name),
            );
            if (reason != null) {
              onSkip(reason);
            }
          },
        ),
        FilledButton.tonalIcon(
          onPressed: onComplete,
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Check-in', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: const Size(0, 32),
          ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc chắn muốn xóa thói quen "${habit.name}"? Lịch sử check-in sẽ bị xóa hoàn toàn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete();
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}
