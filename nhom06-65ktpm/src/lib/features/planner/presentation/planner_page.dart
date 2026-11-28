import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../profile/domain/profile_repository.dart';
import '../../profile/domain/profile_time.dart';
import '../domain/weekly_plan.dart';
import '../domain/weekly_plan_repository.dart';
import '../domain/weekly_planner.dart';
import 'plan_item_editor.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({
    super.key,
    required this.profileRepository,
    required this.repository,
    required this.planner,
    required this.profilePageBuilder,
    required this.journalPageBuilder,
    this.now = DateTime.now,
  });

  final ProfileRepository profileRepository;
  final WeeklyPlanRepository repository;
  final WeeklyPlanner planner;
  final WidgetBuilder profilePageBuilder;
  final Widget Function(PlanItem) journalPageBuilder;
  final DateTime Function() now;

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  PlannerCalendar? _calendar;
  WeeklyPlan? _approved;
  List<PlanItem>? _draft;
  List<String> _notices = const [];
  int _selectedDay = 0;
  bool _busy = false;
  String? _message;

  PlanWeek get _week => _calendar!.week;
  List<PlanItem> get _items => _draft ?? _approved?.items ?? const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _zone(ProfileData data) =>
      profileLocation(data.profile.timeZone) == null
      ? defaultProfileZone
      : data.profile.timeZone!;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on PlannerSaveException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Không thể tải hoặc lưu lịch tuần. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load([DateTime? selectedWeek]) => _run(() async {
    final profile = await widget.profileRepository.load();
    final now = widget.now();
    final zone = _zone(profile);
    final week = selectedWeek == null
        ? PlanWeek.containing(now, zone)
        : PlanWeek(selectedWeek, zone);
    final plan = await widget.repository.load(week);
    if (!mounted) return;
    final today = calendarDate(week.local(now));
    final selectedDay = _calendar?.week.monday == week.monday
        ? _selectedDay
        : today.difference(week.monday).inDays.clamp(0, 6).toInt();
    setState(() {
      _calendar = PlannerCalendar(week, profile);
      _approved = plan;
      _selectedDay = selectedDay;
      _notices = const [];
    });
  });

  Future<void> _openProfile() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: widget.profilePageBuilder));
    if (!mounted) return;
    if (_draft == null) {
      await _load(_calendar?.week.monday);
    } else {
      await _run(() async {
        final profile = await widget.profileRepository.load();
        if (!mounted) return;
        setState(
          () => _calendar = PlannerCalendar(
            PlanWeek(_week.monday, _zone(profile)),
            profile,
          ),
        );
      });
    }
  }

  Future<void> _generate() => _run(() async {
    final fresh = await widget.profileRepository.load();
    if (!mounted) return;
    final calendar = PlannerCalendar(
      PlanWeek(_week.monday, _zone(fresh)),
      fresh,
    );
    final current = _items;
    final suggestion = await widget.planner.generate(
      calendar: calendar,
      current: current,
      now: widget.now(),
    );
    if (!mounted) return;
    setState(() {
      _calendar = calendar;
      if (!listEquals(current, suggestion.items)) _draft = suggestion.items;
      _notices = suggestion.notices;
    });
  });

  Future<void> _approve() => _run(() async {
    final draft = _draft!;
    final fresh = await widget.profileRepository.load();
    if (!mounted) return;
    final calendar = PlannerCalendar(
      PlanWeek(_week.monday, _zone(fresh)),
      fresh,
    );
    setState(() => _calendar = calendar);
    final now = widget.now();
    final existing = {
      for (final item in _approved?.items ?? <PlanItem>[]) item.id: item,
    };
    final futureItems = <PlanItem>[];
    for (final item in draft) {
      if (item.recorded) continue;
      if (item.hasStarted(now)) {
        final old = existing[item.id];
        if (old != null &&
            old.startsAt == item.startsAt &&
            old.endsAt == item.endsAt) {
          continue;
        }
        throw PlannerSaveException(
          '${item.title} đã tới giờ. Hãy đổi sang giờ khác hoặc bỏ khỏi bản nháp.',
        );
      }
      final conflict = calendar.conflictFor(item, draft);
      if (conflict != null) {
        throw PlannerSaveException('${item.title} · $conflict');
      }
      futureItems.add(item);
    }
    if (futureItems.isEmpty && _approved == null) {
      throw const PlannerSaveException(
        'Thêm ít nhất một hoạt động trước khi duyệt lịch.',
      );
    }

    final plan = await widget.repository.approve(
      week: calendar.week,
      expectedVersion: _approved?.version,
      items: futureItems,
    );
    if (!mounted) return;
    setState(() {
      _approved = plan;
      _draft = null;
      _notices = const [];
      _message = 'Đã duyệt lịch tuần.';
    });
  });

  Future<void> _record(PlanItem item, PlanItemStatus outcome) => _run(() async {
    final plan = await widget.repository.recordOutcome(
      week: _week,
      expectedVersion: _approved!.version,
      itemId: item.id,
      outcome: outcome,
    );
    if (mounted) setState(() => _approved = plan);
  });

  Future<void> _edit([PlanItem? item]) async {
    final day = _week.day(_selectedDay);
    final value = await showDialog<PlanItem>(
      context: context,
      useRootNavigator: false,
      builder: (context) => PlanItemEditor(
        calendar: _calendar!,
        day: day,
        items: _items,
        now: widget.now,
        item: item,
      ),
    );
    if (!mounted || value == null) return;
    _replaceItem(value);
    setState(
      () =>
          _selectedDay = calendarDate(_week.local(value.startsAt))
              .difference(_week.monday)
              .inDays,
    );
  }

  void _replaceItem(PlanItem value) {
    setState(
      () => _draft = [
        for (final item in _items)
          if (item.id != value.id) item,
        value,
      ]..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
    );
  }

  bool _editable(PlanItem item) =>
      !item.recorded &&
      (item.status == PlanItemStatus.draft || !item.hasStarted(widget.now()));

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ bản nháp?'),
        content: const Text('Các chỉnh sửa chưa duyệt sẽ bị bỏ.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tiếp tục sửa'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bỏ bản nháp'),
          ),
        ],
      ),
    );
    if (mounted && discard == true) {
      setState(() {
        _draft = null;
        _notices = const [];
        _message = null;
      });
    }
  }

  Future<void> _openJournal(PlanItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => widget.journalPageBuilder(item)),
    );
    if (mounted && _draft == null) await _load(_week.monday);
  }

  @override
  Widget build(BuildContext context) {
    final calendar = _calendar;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch tuần'),
        actions: [
          IconButton(
            tooltip: 'Mở hồ sơ',
            onPressed: _busy ? null : _openProfile,
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
        ],
      ),
      body: calendar == null
          ? Center(
              child: _busy
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_message ?? 'Chưa tải được lịch tuần.'),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                _weekHeader(context),
                const SizedBox(height: 12),
                _actions(),
                if (_message case final message?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Semantics(liveRegion: true, child: Text(message)),
                  ),
                for (final notice in _notices)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(notice),
                  ),
                const SizedBox(height: 12),
                _dayPicker(),
                _timeline(calendar),
                const SizedBox(height: 16),
                _weeklySummary(context),
              ],
            ),
    );
  }

  Widget _weekHeader(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Tuần trước',
        onPressed: _busy || _draft != null ? null : () => _load(_week.day(-7)),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Column(
          children: [
            Text(
              '${_week.key} – ${calendarDateKey(_week.day(6))}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(_week.timeZone),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Tuần sau',
        onPressed: _busy || _draft != null ? null : () => _load(_week.day(7)),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  Widget _actions() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FilledButton.tonal(
        onPressed: _busy ? null : _generate,
        child: Text(_draft == null ? 'Tạo lịch nháp' : 'Tạo lại gợi ý'),
      ),
      OutlinedButton(
        onPressed: _busy ? null : () => _edit(),
        child: const Text('Thêm hoạt động'),
      ),
      if (_draft == null && _approved != null)
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => setState(() => _draft = _items.toList()),
          child: const Text('Chỉnh lịch'),
        ),
      if (_draft == null)
        TextButton(
          onPressed: _busy ? null : () => _load(_week.monday),
          child: const Text('Tải lại'),
        ),
      if (_draft != null) ...[
        FilledButton(
          onPressed: _busy || (_items.isEmpty && _approved == null)
              ? null
              : _approve,
          child: const Text('Duyệt lịch'),
        ),
        TextButton(
          onPressed: _busy ? null : _confirmDiscard,
          child: const Text('Hủy bản nháp'),
        ),
      ],
    ],
  );

  Widget _dayPicker() {
    const days = [
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7',
      'Chủ nhật',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (var offset = 0; offset < 7; offset++)
          ChoiceChip(
            selected: _selectedDay == offset,
            label: Text(
              '${days[offset]} · ${_week.day(offset).day}/${_week.day(offset).month}',
            ),
            onSelected: _busy
                ? null
                : (_) => setState(() => _selectedDay = offset),
          ),
      ],
    );
  }

  String _timeRange(PlanInterval interval, PlanInterval day) {
    final start = _week.local(interval.start);
    final end = _week.local(interval.end);
    final startLabel = interval.start.isBefore(day.start)
        ? '00:00'
        : clockLabel(start.hour * 60 + start.minute);
    final endLabel = !interval.end.isBefore(day.end)
        ? '24:00'
        : clockLabel(end.hour * 60 + end.minute);
    return '$startLabel – $endLabel';
  }

  Widget _timeline(PlannerCalendar calendar) {
    final day = _week.dayInterval(_selectedDay);
    final rows = <({DateTime start, Widget widget})>[
      for (final reservation in calendar.reservations)
        if (intervalsOverlap(reservation.interval, day))
          (
            start: reservation.interval.start,
            widget: ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(reservation.title),
              subtitle: Text(_timeRange(reservation.interval, day)),
              dense: true,
            ),
          ),
      for (final item in _items)
        if (intervalsOverlap(item.interval, day))
          (start: item.startsAt, widget: _itemTile(item, day)),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final outside = _items.where(
      (item) => !intervalsOverlap(item.interval, _week.interval),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_draft != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Bản nháp · Chỉ lịch đã duyệt được dùng để nhắc.'),
          ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Ngày này chưa có mục nào.'),
          ),
        for (final row in rows) row.widget,
        if (outside.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Mục ngoài tuần theo múi giờ hiện tại'),
          ),
          for (final item in outside) _itemTile(item, null),
        ],
      ],
    );
  }

  Widget _itemTile(PlanItem item, PlanInterval? day) {
    String dateTimeLabel(DateTime instant) {
      final local = _week.local(instant);
      return '${calendarDateKey(local)} ${clockLabel(local.hour * 60 + local.minute)}';
    }

    final timeRange = day == null
        ? '${dateTimeLabel(item.startsAt)} – ${dateTimeLabel(item.endsAt)}'
        : _timeRange(item.interval, day);
    final status = switch (item.status) {
      PlanItemStatus.completed => 'Hoàn thành',
      PlanItemStatus.skipped => 'Bỏ qua',
      _ when _draft != null && _editable(item) => 'Bản nháp',
      _ when item.hasStarted(widget.now()) => 'Chưa ghi nhận',
      _ => 'Đã duyệt',
    };
    final warning = _editable(item)
        ? _calendar!.conflictFor(item, _items)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '$timeRange · ${item.kind.label} · $status${item.isLocked ? ' · Đã khóa' : ''}',
            ),
            if (item.reason != null) Text(item.reason!),
            if (warning != null)
              Text(
                warning,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_draft != null && _editable(item))
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _replaceItem(item.withLock(!item.isLocked)),
                    child: Text(item.isLocked ? 'Mở khóa' : 'Khóa mục'),
                  ),
                  if (!item.isLocked) ...[
                    TextButton(
                      onPressed: _busy ? null : () => _edit(item),
                      child: const Text('Đổi giờ'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                              () => _draft = _items
                                  .where((other) => item.id != other.id)
                                  .toList(),
                            ),
                      child: const Text('Bỏ mục'),
                    ),
                  ],
                ],
              ),
            if (_draft == null &&
                item.status == PlanItemStatus.approved &&
                item.hasStarted(widget.now()))
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => _openJournal(item),
                    child: const Text('Ghi nhật ký'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _record(item, PlanItemStatus.completed),
                    child: const Text('Hoàn thành'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _record(item, PlanItemStatus.skipped),
                    child: const Text('Bỏ qua'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _weeklySummary(BuildContext context) {
    final plan = _approved;
    final items = plan?.items ?? const <PlanItem>[];
    final completed = items
        .where((item) => item.status == PlanItemStatus.completed)
        .length;
    final skipped = items
        .where((item) => item.status == PlanItemStatus.skipped)
        .length;
    final upcoming = plan?.upcomingReminderItems(widget.now()).length ?? 0;
    final unrecorded = items.length - completed - skipped - upcoming;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tổng kết tuần',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (plan == null)
              const Text('Chưa có lịch đã duyệt.')
            else ...[
              Text('Hoàn thành $completed/${items.length} · Bỏ qua $skipped'),
              Text('Chưa ghi nhận $unrecorded · Sắp tới $upcoming'),
            ],
          ],
        ),
      ),
    );
  }
}
