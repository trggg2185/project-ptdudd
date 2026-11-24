import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/sleep_log.dart';
import '../../domain/repositories/sleep_repository.dart';
import '../controllers/sleep_controller.dart';
import '../widgets/responsive_routine_timeline.dart';
import '../widgets/sleep_log_card.dart';
import '../widgets/sleep_summary_card.dart';
import '../widgets/sleep_window_dialog.dart';
import 'sleep_log_form_page.dart';

enum _CompactSleepSection { logs, timeline }

/// Màn hình chính của module Nhật ký ngủ & Lịch sinh hoạt responsive (Issue #5).
///
/// - Tự thích ứng bố cục: 1 cột có thanh chuyển đổi trên Android (< 760px)
///   và 2 cột song song (Nhật ký & Tổng quan | Lịch sinh hoạt 24h) trên Web/màn hình rộng (>= 760px).
/// - Hỗ trợ đầy đủ trạng thái tải (loading), trống (empty), lỗi (error + thử lại).
/// - Hỗ trợ nhãn truy cập (Semantics) và phím tắt bàn phím:
///   `Alt + N` (thêm nhật ký), `Alt + W` (khoảng ngủ mong muốn),
///   `Alt + R` (tải lại), `Alt + ←/→` (chuyển ngày lịch sinh hoạt).
class SleepPage extends StatefulWidget {
  final SleepRepository repository;
  final String currentUserId;
  final DateTime Function()? nowProvider;

  const SleepPage({
    super.key,
    required this.repository,
    required this.currentUserId,
    this.nowProvider,
  });

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage> {
  static const double _wideBreakpoint = 760;

  late final SleepController _controller;
  _CompactSleepSection _compactSection = _CompactSleepSection.logs;

  @override
  void initState() {
    super.initState();
    _controller = SleepController(
      repository: widget.repository,
      currentUserId: widget.currentUserId,
      nowProvider: widget.nowProvider,
    );
    _controller.loadAll();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openSleepForm({SleepLog? existing}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SleepLogFormPage(
          initialLog: existing,
          defaultWindow: _controller.sleepWindow,
          referenceNow: _controller.now,
          onSave: ({
            String? existingId,
            required DateTime sleptAt,
            required DateTime wokeAt,
            required AlertnessLevel alertness,
            String? note,
          }) async {
            final ok = await _controller.saveSleepLog(
              existingId: existingId,
              sleptAt: sleptAt,
              wokeAt: wokeAt,
              alertness: alertness,
              note: note,
            );
            return ok ? null : (_controller.actionError ?? 'Không thể lưu nhật ký.');
          },
        ),
      ),
    );
  }

  Future<void> _openSleepWindowDialog() async {
    final result = await showDialog<SleepWindowDialogResult>(
      context: context,
      builder: (_) => SleepWindowDialog(initialWindow: _controller.sleepWindow),
    );
    if (!mounted || result == null) return;

    if (result is SaveSleepWindowResult) {
      await _controller.saveSleepWindow(result.window);
    } else if (result is ClearSleepWindowResult) {
      await _controller.clearSleepWindow();
    }
  }

  Future<void> _confirmDeleteLog(SleepLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa nhật ký giấc ngủ?'),
        content: Text(
          'Bạn có chắc muốn xóa bản ghi ngủ (${log.formattedDuration}) này không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.deleteSleepLog(log.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, alt: true): () =>
            _openSleepForm(),
        const SingleActivator(LogicalKeyboardKey.keyW, alt: true): () =>
            _openSleepWindowDialog(),
        const SingleActivator(LogicalKeyboardKey.keyR, alt: true): () =>
            _controller.loadAll(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _controller.shiftSelectedDate(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _controller.shiftSelectedDate(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Giấc ngủ & Lịch sinh hoạt'),
            actions: [
              Semantics(
                button: true,
                label: 'Thiết lập khoảng ngủ mong muốn',
                child: IconButton(
                  tooltip: 'Khoảng ngủ mong muốn (Alt + W)',
                  onPressed: _openSleepWindowDialog,
                  icon: const Icon(Icons.bedtime_outlined),
                ),
              ),
              Semantics(
                button: true,
                label: 'Tải lại dữ liệu giấc ngủ',
                child: IconButton(
                  tooltip: 'Tải lại (Alt + R)',
                  onPressed: _controller.loadAll,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
          floatingActionButton: Semantics(
            button: true,
            label: 'Thêm nhật ký giấc ngủ mới',
            child: FloatingActionButton.extended(
              key: const Key('sleep_add_fab'),
              onPressed: () => _openSleepForm(),
              tooltip: 'Ghi nhật ký ngủ (Alt + N)',
              icon: const Icon(Icons.add),
              label: const Text('Ghi giấc ngủ'),
            ),
          ),
          body: SafeArea(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                if (_controller.isLoading && !_controller.hasLoadedOnce) {
                  return _LoadingView();
                }
                if (_controller.loadError != null && !_controller.hasLoadedOnce) {
                  return _LoadErrorView(
                    message: _controller.loadError!,
                    onRetry: _controller.loadAll,
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= _wideBreakpoint;
                    if (isWide) {
                      return _buildWideLayout(context);
                    }
                    return _buildCompactLayout(context);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 84),
          child: Row(
            key: const Key('sleep_wide_layout'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SelfReportDisclosureBanner(),
                      const SizedBox(height: 12),
                      if (_controller.actionError != null) ...[
                        _ActionErrorBanner(
                          message: _controller.actionError!,
                          onDismiss: _controller.clearActionError,
                        ),
                        const SizedBox(height: 12),
                      ],
                      SleepSummaryCard(
                        summary: _controller.weeklySummary,
                        sleepWindow: _controller.sleepWindow,
                        onEditSleepWindow: _openSleepWindowDialog,
                      ),
                      const SizedBox(height: 16),
                      _buildSleepLogsSection(context),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  child: ResponsiveRoutineTimeline(
                    selectedDate: _controller.selectedDate,
                    segments: _controller.segmentsForSelectedDate,
                    conflictWarnings: _controller.windowConflictsForSelectedDate,
                    onPreviousDay: () => _controller.shiftSelectedDate(-1),
                    onNextDay: () => _controller.shiftSelectedDate(1),
                    onSelectToday: () =>
                        _controller.setSelectedDate(_controller.now),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLayout(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('sleep_compact_layout'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SelfReportDisclosureBanner(),
          const SizedBox(height: 12),
          if (_controller.actionError != null) ...[
            _ActionErrorBanner(
              message: _controller.actionError!,
              onDismiss: _controller.clearActionError,
            ),
            const SizedBox(height: 12),
          ],
          SegmentedButton<_CompactSleepSection>(
            segments: const [
              ButtonSegment<_CompactSleepSection>(
                value: _CompactSleepSection.logs,
                icon: Icon(Icons.hotel_outlined),
                label: Text('Nhật ký ngủ'),
              ),
              ButtonSegment<_CompactSleepSection>(
                value: _CompactSleepSection.timeline,
                icon: Icon(Icons.view_timeline_outlined),
                label: Text('Lịch sinh hoạt 24h'),
              ),
            ],
            selected: {_compactSection},
            onSelectionChanged: (selection) => setState(() {
              _compactSection = selection.first;
            }),
          ),
          const SizedBox(height: 14),
          if (_compactSection == _CompactSleepSection.logs) ...[
            SleepSummaryCard(
              summary: _controller.weeklySummary,
              sleepWindow: _controller.sleepWindow,
              onEditSleepWindow: _openSleepWindowDialog,
            ),
            const SizedBox(height: 16),
            _buildSleepLogsSection(context),
          ] else ...[
            ResponsiveRoutineTimeline(
              selectedDate: _controller.selectedDate,
              segments: _controller.segmentsForSelectedDate,
              conflictWarnings: _controller.windowConflictsForSelectedDate,
              onPreviousDay: () => _controller.shiftSelectedDate(-1),
              onNextDay: () => _controller.shiftSelectedDate(1),
              onSelectToday: () => _controller.setSelectedDate(_controller.now),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSleepLogsSection(BuildContext context) {
    final theme = Theme.of(context);
    final logs = _controller.sleepLogs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Nhật ký giấc ngủ (${logs.length})',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_controller.isMutating || _controller.isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (logs.isEmpty)
          _EmptySleepLogsCard(
            onAddLog: () => _openSleepForm(),
            onConfigureWindow: _openSleepWindowDialog,
          )
        else
          ...logs.map(
            (log) => SleepLogCard(
              log: log,
              onEdit: () => _openSleepForm(existing: log),
              onDelete: () => _confirmDeleteLog(log),
            ),
          ),
      ],
    );
  }
}

class _SelfReportDisclosureBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nhật ký ngủ chỉ dựa trên giờ ngủ/thức và mức tỉnh táo bạn tự khai báo — '
              'không suy ra giấc ngủ thật từ việc không dùng điện thoại và không ép mốc 22:00 cố định.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Đang tải dữ liệu nhật ký giấc ngủ và lịch sinh hoạt',
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang tải nhật ký giấc ngủ và lịch sinh hoạt...'),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 48, color: scheme.error),
                const SizedBox(height: 12),
                Text(
                  'Không thể tải dữ liệu',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySleepLogsCard extends StatelessWidget {
  final VoidCallback onAddLog;
  final VoidCallback onConfigureWindow;

  const _EmptySleepLogsCard({
    required this.onAddLog,
    required this.onConfigureWindow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.bedtime_outlined, size: 44, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'Chưa có nhật ký giấc ngủ nào',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Ghi lại giờ ngủ/thức và mức tỉnh táo theo nhịp sinh hoạt thực tế của bạn '
              '(kể cả ca đêm hoặc ngủ qua nửa đêm).',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onAddLog,
                  icon: const Icon(Icons.add),
                  label: const Text('Ghi nhật ký ngủ đầu tiên'),
                ),
                OutlinedButton.icon(
                  onPressed: onConfigureWindow,
                  icon: const Icon(Icons.tune),
                  label: const Text('Đặt khoảng ngủ mong muốn'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ActionErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
              ),
            ),
            IconButton(
              tooltip: 'Đóng thông báo lỗi',
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 18, color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}
