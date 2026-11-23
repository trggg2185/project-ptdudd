import 'package:flutter/material.dart';

import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/logic/streak_calculator.dart';

/// Thanh lịch tuần (7 ngày) hiển thị trực quan trạng thái thói quen.
class HabitWeekCalendar extends StatelessWidget {
  final Habit habit;
  final List<HabitLog> logs;
  final DateTime selectedDate;
  final ValueChanged<DateTime>? onDateSelected;

  const HabitWeekCalendar({
    super.key,
    required this.habit,
    required this.logs,
    required this.selectedDate,
    this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final weekItems = StreakCalculator.getWeekStatus(
      habit,
      logs,
      selectedDate,
      referenceDate: DateHelper.normalize(DateTime.now()),
    );

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Lịch sử tuần này',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Row(
                  children: [
                    _legendItem(Colors.green, 'Đạt'),
                    const SizedBox(width: 8),
                    _legendItem(Colors.orange, 'Bỏ qua'),
                    const SizedBox(width: 8),
                    _legendItem(Colors.red.shade400, 'Lỡ'),
                    const SizedBox(width: 8),
                    _legendItem(Colors.grey.shade400, 'Nghỉ/Chờ'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: weekItems.map((item) {
                final isSelected = DateHelper.isSameDay(item.date, selectedDate);
                final isToday = DateHelper.isSameDay(item.date, DateTime.now());

                return InkWell(
                  onTap: onDateSelected != null ? () => onDateSelected!(item.date) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 42,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isToday
                          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)
                          : null,
                    ),
                    child: Column(
                      children: [
                        Text(
                          DateHelper.weekdayToVietnamese(item.date.weekday, short: true),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.date.day}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _statusIndicator(item.status),
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

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _statusIndicator(HabitDayStatus status) {
    Color bg;
    IconData? icon;

    switch (status) {
      case HabitDayStatus.completed:
        bg = Colors.green;
        icon = Icons.check;
        break;
      case HabitDayStatus.skipped:
        bg = Colors.orange;
        icon = Icons.pause;
        break;
      case HabitDayStatus.missed:
        bg = Colors.red.shade400;
        icon = Icons.close;
        break;
      case HabitDayStatus.pending:
        bg = Colors.grey.shade300;
        icon = Icons.hourglass_empty;
        break;
      case HabitDayStatus.future:
        bg = Colors.grey.shade200;
        icon = Icons.schedule;
        break;
      case HabitDayStatus.restDay:
        bg = Colors.grey.shade200;
        icon = null;
        break;
    }

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: icon != null
          ? Icon(
              icon,
              size: 13,
              color: (status == HabitDayStatus.pending || status == HabitDayStatus.future)
                  ? Colors.black54
                  : Colors.white,
            )
          : null,
    );
  }
}
