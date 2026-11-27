import 'package:flutter/material.dart';

import '../../domain/entities/insight_data_source.dart';
import '../../domain/entities/weekly_insights_summary.dart';
import '../../domain/services/insights_display_formatter.dart';
import '../../domain/usecases/get_weekly_insights_usecase.dart';
import '../controllers/weekly_insights_controller.dart';

/// Widget Dashboard & tổng kết tuần độc lập (không sửa `main.dart`):
/// - Tổng hợp tỷ lệ hoàn thành, streak, thời lượng tập, giấc ngủ tự ghi và bữa ăn theo tuần.
/// - Tách bạch "Chưa ghi nhận" với "Không hoàn thành" ở mọi mục.
/// - Hiển thị rõ nguồn nhập tay / tự khai báo / thiết bị GPS / camera.
/// - Luôn gắn lưu ý phi y khoa, tuyệt đối không gọi mức kỷ luật là "điểm sức khỏe".
class WeeklyInsightsDashboardView extends StatefulWidget {
  final String ownerUid;
  final GetWeeklyInsightsUseCase useCase;
  final DateTime? initialWeekAnchor;
  final DateTime? referenceDate;

  const WeeklyInsightsDashboardView({
    super.key,
    required this.ownerUid,
    required this.useCase,
    this.initialWeekAnchor,
    this.referenceDate,
  });

  @override
  State<WeeklyInsightsDashboardView> createState() =>
      _WeeklyInsightsDashboardViewState();
}

class _WeeklyInsightsDashboardViewState
    extends State<WeeklyInsightsDashboardView> {
  late WeeklyInsightsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    _controller.load();
  }

  WeeklyInsightsController _buildController() {
    return WeeklyInsightsController(
      useCase: widget.useCase,
      ownerUid: widget.ownerUid,
      initialWeekAnchor: widget.initialWeekAnchor,
      fixedReferenceDate: widget.referenceDate,
    );
  }

  @override
  void didUpdateWidget(covariant WeeklyInsightsDashboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.useCase != widget.useCase ||
        oldWidget.referenceDate != widget.referenceDate) {
      _controller.dispose();
      _controller = _buildController();
      _controller.load();
    } else if (oldWidget.ownerUid != widget.ownerUid) {
      _controller.updateOwner(widget.ownerUid);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final summary = _controller.summary;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildDisclaimerBanner(context),
                const SizedBox(height: 12),
                _buildWeekSelector(context),
                const SizedBox(height: 12),
                if (_controller.isLoading && summary == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_controller.errorMessage case final error?)
                  _buildErrorCard(context, error)
                else if (summary != null) ...[
                  if (_controller.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  _buildMetricCardsLayout(context, summary, isWide: isWide),
                  const SizedBox(height: 12),
                  _buildPerHabitBreakdownCard(context, summary.habits),
                  const SizedBox(height: 12),
                  _buildNeutralNotesCard(context, summary),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDisclaimerBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Lưu ý phạm vi tổng hợp kỷ luật',
      child: Card(
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  WeeklyInsightsSummary.nonMedicalDisclaimer,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeekSelector(BuildContext context) {
    final rangeLabel = InsightsDisplayFormatter.formatWeekRange(
      _controller.selectedWeekStart,
      _controller.selectedWeekEnd,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Tuần trước',
                  onPressed: _controller.isLoading
                      ? null
                      : _controller.previousWeek,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Tuần $rangeLabel',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Tuần sau',
                  onPressed:
                      _controller.isLoading || !_controller.canGoToNextWeek
                      ? null
                      : _controller.nextWeek,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (!_controller.isCurrentWeek)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _controller.isLoading
                      ? null
                      : _controller.goToCurrentWeek,
                  child: const Text('Về tuần hiện tại'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String error) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _controller.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCardsLayout(
    BuildContext context,
    WeeklyInsightsSummary summary, {
    required bool isWide,
  }) {
    final habitCard = _buildHabitSummaryCard(context, summary.habits);
    final activityCard = _buildActivitySummaryCard(context, summary.activity);
    final sleepCard = _buildSleepSummaryCard(context, summary.sleep);
    final mealCard = _buildMealSummaryCard(context, summary.meals);

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          habitCard,
          const SizedBox(height: 12),
          activityCard,
          const SizedBox(height: 12),
          sleepCard,
          const SizedBox(height: 12),
          mealCard,
        ],
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: habitCard),
            const SizedBox(width: 12),
            Expanded(child: activityCard),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: sleepCard),
            const SizedBox(width: 12),
            Expanded(child: mealCard),
          ],
        ),
      ],
    );
  }

  Widget _buildHabitSummaryCard(
    BuildContext context,
    WeeklyHabitInsights habits,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(
              context,
              icon: Icons.check_circle_outline,
              title: 'Kỷ luật thói quen & Streak',
              sourceLabel: habits.dataSource.label,
            ),
            const SizedBox(height: 12),
            Text(
              'Tỷ lệ hoàn thành: ${InsightsDisplayFormatter.formatCompletionRate(habits.completionRatePercent)}',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Streak hiện tại cao nhất: ${habits.bestCurrentStreak} ngày • Kỷ lục: ${habits.bestLongestStreak} ngày',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip('Hoàn thành: ${habits.totalCompletedCount}'),
                _statusChip('Bỏ qua có lý do: ${habits.skippedCount}'),
                _statusChip('Không hoàn thành: ${habits.explicitFailedCount}'),
                _statusChip('Chưa ghi nhận: ${habits.totalUnloggedCount}'),
              ],
            ),
            if (habits.dueSlotsElapsed == 0 && habits.totalHabitsCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Tuần này chưa có lượt đến hạn đã qua; các ngày chưa bấm được tính là Chưa ghi nhận.',
                style: textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySummaryCard(
    BuildContext context,
    WeeklyActivityInsights activity,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(
              context,
              icon: Icons.directions_run_outlined,
              title: 'Thời lượng tập luyện theo tuần',
              sourceLabel: activity.hasData
                  ? activity.dataSources.map((s) => s.label).join(' • ')
                  : 'Chưa ghi nhận',
            ),
            const SizedBox(height: 12),
            Text(
              'Tổng thời lượng tập: ${activity.formattedTotalDuration}',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              activity.hasData
                  ? '${activity.sessionCount} buổi tập • ${InsightsDisplayFormatter.formatEstimatedDistance(activity.totalEstimatedDistanceMeters)}'
                  : 'Tuần này chưa có buổi tập được ghi nhận.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              InsightsDisplayFormatter.formatActivitySources(activity),
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip('Đã ghi nhận: ${activity.activeDaysCount} ngày'),
                _statusChip(
                  'Chưa ghi nhận: ${activity.unloggedDaysCount} ngày',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepSummaryCard(
    BuildContext context,
    WeeklySleepInsights sleep,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(
              context,
              icon: Icons.bedtime_outlined,
              title: 'Giấc ngủ tự ghi theo tuần',
              sourceLabel: sleep.dataSource.label,
            ),
            const SizedBox(height: 12),
            Text(
              'Trung bình ngày đã ghi: ${sleep.formattedAverageDuration}',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              sleep.hasData
                  ? 'Mức tỉnh táo tự đánh giá: ${sleep.averageAlertnessScore?.toStringAsFixed(1) ?? '-'}/5'
                        '${sleep.regularityIndex == null ? '' : ' • Độ đều đặn lịch ngủ: ${sleep.regularityIndex}/100'}'
                  : 'Chưa có nhật ký giấc ngủ nào trong tuần.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Nguồn: ${InsightDataSource.selfReported.label} (không đo bằng cảm biến hay thời gian tắt màn hình).',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip('Đã ghi nhận: ${sleep.loggedDaysCount} ngày'),
                _statusChip('Chưa ghi nhận: ${sleep.unloggedDaysCount} ngày'),
                if (sleep.daytimeSleepCount > 0)
                  _statusChip('Ngủ ban ngày: ${sleep.daytimeSleepCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealSummaryCard(
    BuildContext context,
    WeeklyMealInsights meals,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(
              context,
              icon: Icons.restaurant_outlined,
              title: 'Nhật ký bữa ăn theo tuần',
              sourceLabel: meals.hasData
                  ? meals.dataSources.map((s) => s.label).join(' • ')
                  : 'Chưa ghi nhận',
            ),
            const SizedBox(height: 12),
            Text(
              meals.hasData
                  ? 'Tổng số bữa đã ghi: ${meals.totalLogsCount} bữa'
                  : 'Chưa ghi nhận bữa ăn nào trong tuần',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              InsightsDisplayFormatter.formatMealSources(meals),
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip('Đã ghi nhận: ${meals.loggedDaysCount} ngày'),
                _statusChip('Chưa ghi nhận: ${meals.unloggedDaysCount} ngày'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerHabitBreakdownCard(
    BuildContext context,
    WeeklyHabitInsights habits,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chi tiết từng thói quen trong tuần',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (habits.perHabit.isEmpty)
              const Text(
                'Chưa có thói quen nào được tạo. Trạng thái trống được hiển thị là Chưa ghi nhận.',
              )
            else
              for (final item in habits.perHabit) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.habitName, style: textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Hoàn thành: ${InsightsDisplayFormatter.formatCompletionRate(item.completionRatePercent)} • '
                        'Streak hiện tại: ${item.currentStreak} ngày • '
                        'Không hoàn thành: ${item.explicitFailedCount} • '
                        'Chưa ghi nhận: ${item.totalUnloggedCount}',
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: item.days
                            .map(
                              (cell) => Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  '${InsightsDisplayFormatter.shortWeekdayLabel(cell.date)}: ${cell.resolution.label}',
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildNeutralNotesCard(
    BuildContext context,
    WeeklyInsightsSummary summary,
  ) {
    final notes = InsightsDisplayFormatter.buildNeutralWeeklyNotes(summary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ghi chú tổng kết tuần',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $note'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cardHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String sourceLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                'Nguồn: $sourceLabel',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String label) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
    );
  }
}
