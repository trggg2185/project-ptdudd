import 'package:flutter/material.dart';

import '../../../activity/data/repositories/in_memory_activity_repository.dart';
import '../../../activity/presentation/pages/activity_page.dart';
import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/entities/streak_info.dart';
import '../../domain/repositories/habit_repository.dart';
import '../controllers/habit_controller.dart';
import '../widgets/habit_card.dart';
import 'habit_detail_page.dart';
import 'habit_form_page.dart';

/// Màn hình chính quản lý thói quen, check-in hằng ngày và theo dõi streak của HealthyLife.
class HabitsPage extends StatefulWidget {
  final HabitRepository repository;
  final String currentUserId;

  const HabitsPage({
    super.key,
    required this.repository,
    this.currentUserId = 'demo-user-duc-2351170585',
  });

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  late HabitController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HabitController(
      repository: widget.repository,
      currentUserId: widget.currentUserId,
    );
    _controller.loadHabits();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Thói quen & Kỷ luật'),
            actions: [
              IconButton(
                icon: const Icon(Icons.directions_run),
                tooltip: 'Nhật ký vận động',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ActivityPage(
                        repository: InMemoryActivityRepository(),
                        ownerUid: widget.currentUserId,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Tải lại dữ liệu',
                onPressed: _controller.loadHabits,
              ),
            ],
          ),
          body: _controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _controller.loadHabits,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 80),
                    children: [
                      // 1. Thẻ tóm tắt tiến độ ngày hôm nay
                      _buildDailySummaryCard(theme),

                      // 2. Thanh chuyển ngày (Hôm qua, Hôm nay, v.v.)
                      _buildDateSelector(),

                      // 3. Thanh bộ lọc
                      _buildFilterChips(),

                      // 4. Danh sách thói quen
                      if (_controller.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            _controller.errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),

                      if (_controller.filteredHabits.isEmpty)
                        _buildEmptyState()
                      else
                        ..._controller.filteredHabits.map((habit) {
                          final dayStatus = _controller.getDayStatusForHabit(habit);
                          final currentLog = _controller.selectedDateLogs[habit.id];
                          final streakInfo = _controller.streakInfos[habit.id] ?? const StreakInfo();

                          return HabitCard(
                            habit: habit,
                            dayStatus: dayStatus,
                            currentLog: currentLog,
                            streakInfo: streakInfo,
                            onTap: () => _openHabitDetail(habit),
                            onComplete: () => _controller.checkInHabit(
                              habitId: habit.id,
                              status: CheckInStatus.completed,
                            ),
                            onSkip: (reason) => _controller.checkInHabit(
                              habitId: habit.id,
                              status: CheckInStatus.skipped,
                              reason: reason,
                            ),
                            onUndo: () => _controller.undoCheckIn(habit.id),
                            onEdit: () => _openEditHabit(habit),
                            onToggleActive: () => _controller.toggleActive(habit.id),
                            onDelete: () => _controller.deleteHabit(habit.id),
                          );
                        }),
                    ],
                  ),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openCreateHabit,
            icon: const Icon(Icons.add),
            label: const Text('Thêm thói quen'),
          ),
        );
      },
    );
  }

  Widget _buildDailySummaryCard(ThemeData theme) {
    final completed = _controller.completedCountForSelectedDate;
    final due = _controller.dueCountForSelectedDate;
    final ratio = _controller.progressRatioForSelectedDate;
    final percent = (ratio * 100).toInt();

    final isToday = DateHelper.isSameDay(_controller.selectedDate, DateTime.now());
    final dateLabel = isToday
        ? 'Hôm nay, ${DateHelper.formatVietnameseDate(_controller.selectedDate)}'
        : DateHelper.formatVietnameseDate(_controller.selectedDate);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$percent%',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            due == 0
                ? 'Không có thói quen nào đến hạn'
                : completed == due
                    ? '🎉 Xuất sắc! Hoàn thành 100% mục tiêu'
                    : 'Đã hoàn thành $completed trên $due thói quen',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final yesterday = DateHelper.shiftDays(now, -1);
    final tomorrow = DateHelper.shiftDays(now, 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _dateChip('Hôm qua', yesterday),
              const SizedBox(width: 8),
              _dateChip('Hôm nay', now),
              const SizedBox(width: 8),
              _dateChip('Ngày mai', tomorrow),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Colors.blueAccent),
            tooltip: 'Chọn ngày bất kỳ',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _controller.selectedDate,
                firstDate: DateTime(2025),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                _controller.setSelectedDate(picked);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _dateChip(String label, DateTime date) {
    final isSelected = DateHelper.isSameDay(_controller.selectedDate, date);
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (val) {
        if (val) _controller.setSelectedDate(date);
      },
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Đang theo dõi'),
            selected: _controller.filter == 'active',
            onSelected: (_) => _controller.setFilter('active'),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Tất cả'),
            selected: _controller.filter == 'all',
            onSelected: (_) => _controller.setFilter('all'),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Tạm dừng'),
            selected: _controller.filter == 'paused',
            onSelected: (_) => _controller.setFilter('paused'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.checklist_rtl, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Chưa có thói quen nào trong danh mục này',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Hãy nhấn nút "Thêm thói quen" bên dưới để bắt đầu xây dựng lối sống kỷ luật và lành mạnh!',
            style: TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateHabit() async {
    final newHabit = await Navigator.of(context).push<Habit>(
      MaterialPageRoute(
        builder: (ctx) => HabitFormPage(ownerUid: widget.currentUserId),
      ),
    );

    if (newHabit != null) {
      await _controller.createHabit(newHabit);
    }
  }

  Future<void> _openEditHabit(Habit habit) async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (ctx) => HabitFormPage(habit: habit, ownerUid: widget.currentUserId),
      ),
    );

    if (result is Habit) {
      await _controller.updateHabit(result);
    } else if (result == 'delete') {
      await _controller.deleteHabit(habit.id);
    }
  }

  void _openHabitDetail(Habit habit) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => HabitDetailPage(
          habit: habit,
          repository: widget.repository,
          currentUserId: widget.currentUserId,
        ),
      ),
    ).then((_) => _controller.loadHabits());
  }
}
