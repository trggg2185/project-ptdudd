import 'package:flutter/material.dart';

import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/entities/streak_info.dart';
import '../../domain/repositories/habit_repository.dart';
import '../widgets/habit_streak_card.dart';
import '../widgets/habit_week_calendar.dart';
import 'habit_form_page.dart';

/// Màn hình chi tiết thói quen, biểu đồ lịch sử tuần và thống kê chuỗi kỷ luật (Streak).
class HabitDetailPage extends StatefulWidget {
  final Habit habit;
  final HabitRepository repository;
  final String currentUserId;

  const HabitDetailPage({
    super.key,
    required this.habit,
    required this.repository,
    required this.currentUserId,
  });

  @override
  State<HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends State<HabitDetailPage> {
  late Habit _habit;
  List<HabitLog> _logs = [];
  StreakInfo _streakInfo = const StreakInfo();
  DateTime _selectedDate = DateHelper.normalize(DateTime.now());
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _habit = widget.habit;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final logs = await widget.repository.getHabitLogs(_habit.id);
      final streak = await widget.repository.getStreakInfo(_habit, referenceDate: _selectedDate);
      setState(() {
        _logs = logs;
        _streakInfo = streak;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_habit.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Chỉnh sửa thói quen',
            onPressed: _editHabit,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // 1. Thẻ thông tin cơ bản
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _habit.isActive ? Colors.green.shade50 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _habit.isActive ? Colors.green.shade300 : Colors.grey.shade400,
                                  ),
                                ),
                                child: Text(
                                  _habit.isActive ? 'Đang theo dõi' : 'Đang tạm dừng',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _habit.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Chu kỳ: ${_habit.frequency.displayLabel}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          if (_habit.description != null && _habit.description!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              _habit.description!,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                          if (_habit.reminderTime != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.alarm, size: 16, color: Colors.blueAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'Nhắc lúc: ${_habit.reminderTime}',
                                  style: const TextStyle(fontSize: 12, color: Colors.blueAccent),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Thẻ Streak thống kê chi tiết
                  HabitStreakCard(streakInfo: _streakInfo),
                  const SizedBox(height: 16),

                  // 3. Lịch tuần tương tác
                  HabitWeekCalendar(
                    habit: _habit,
                    logs: _logs,
                    selectedDate: _selectedDate,
                    onDateSelected: (date) {
                      setState(() => _selectedDate = date);
                    },
                  ),
                  const SizedBox(height: 20),

                  // 4. Lịch sử check-in gần đây
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Nhật ký check-in gần đây',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_logs.length} lượt ghi',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_logs.isEmpty)
                    Card(
                      elevation: 0,
                      color: Colors.grey.shade50,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'Chưa có lượt check-in nào được ghi nhận.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._logs.take(15).map((log) => _buildLogTile(log)),
                ],
              ),
            ),
    );
  }

  Widget _buildLogTile(HabitLog log) {
    final isCompleted = log.status == CheckInStatus.completed;
    final isSkipped = log.status == CheckInStatus.skipped;

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCompleted
              ? Colors.green.shade50
              : isSkipped
                  ? Colors.orange.shade50
                  : Colors.red.shade50,
          child: Icon(
            isCompleted
                ? Icons.check
                : isSkipped
                    ? Icons.pause
                    : Icons.close,
            color: isCompleted
                ? Colors.green
                : isSkipped
                    ? Colors.orange
                    : Colors.red,
            size: 20,
          ),
        ),
        title: Text(
          DateHelper.formatVietnameseDate(log.date),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: log.reason != null
            ? Text(
                'Lý do: ${log.reason}',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              )
            : Text(
                isCompleted ? 'Đã hoàn thành xuất sắc' : 'Không hoàn thành',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
        trailing: Text(
          '${log.loggedAt.hour.toString().padLeft(2, '0')}:${log.loggedAt.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  Future<void> _editHabit() async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (ctx) => HabitFormPage(
          habit: _habit,
          ownerUid: widget.currentUserId,
        ),
      ),
    );

    if (result is Habit) {
      await widget.repository.saveHabit(result);
      setState(() => _habit = result);
      await _loadData();
    } else if (result == 'delete') {
      await widget.repository.deleteHabit(_habit.id);
      if (mounted) Navigator.of(context).pop();
    }
  }
}
