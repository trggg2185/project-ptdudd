import 'package:flutter/material.dart';

import '../domain/health_profile.dart';
import '../domain/profile_repository.dart';
import '../domain/profile_time.dart';
import '../domain/schedule_block.dart';
import 'profile_form.dart';
import 'schedule_editor.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.repository});

  final ProfileRepository repository;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  HealthProfile? _profile;
  List<ScheduleBlock> _blocks = [];
  bool _loadFailed = false;
  bool _deleting = false;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _profile = result.profile;
        _blocks = result.blocks.toList();
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _saveProfile(HealthProfile profile) async {
    await widget.repository.saveProfile(profile);
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _editBlock({
    required bool manual,
    ScheduleBlock? existing,
  }) async {
    final saved = await showDialog<ScheduleBlock>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => ScheduleEditor(
        timeZone: profileLocation(_profile?.timeZone) != null
            ? _profile!.timeZone!
            : defaultProfileZone,
        isManual: manual,
        initialBlock: existing,
        save: widget.repository.saveBlock,
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _blocks = [
        for (final block in _blocks)
          if (block.id != saved.id) block,
        saved,
      ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    });
  }

  Future<void> _deleteBlock(ScheduleBlock block) async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa khoảng lịch?'),
        content: Text(block.title),
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
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.deleteBlock(block.id);
      if (mounted) {
        setState(() => _blocks.removeWhere((item) => item.id == block.id));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể xóa khoảng lịch. Hãy thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _openManual() {
    _tabs.animateTo(2);
    setState(() => _selectedTab = 2);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ và lịch'),
        bottom: profile == null
            ? null
            : TabBar(
                controller: _tabs,
                onTap: (i) => setState(() => _selectedTab = i),
                tabs: const [
                  Tab(text: 'Hồ sơ'),
                  Tab(text: 'Lịch bận'),
                  Tab(text: 'Lịch thủ công'),
                ],
              ),
      ),
      body: SafeArea(
        child: profile == null
            ? Center(
                child: _loadFailed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Không thể tải hồ sơ và lịch.'),
                          TextButton(
                            onPressed: () {
                              setState(() => _loadFailed = false);
                              _load();
                            },
                            child: const Text('Thử lại'),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      ProfileForm(
                        initialProfile: profile,
                        save: _saveProfile,
                        openManualSchedule: _openManual,
                      ),
                      _scheduleList(manual: false),
                      _scheduleList(manual: true),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _scheduleList({required bool manual}) {
    final blocks = _blocks.where(
      (block) => (block.kind == ScheduleKind.manual) == manual,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (manual)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Tự đặt giờ cho hoạt động của bạn, kể cả khi chưa đủ thông tin gợi ý.',
            ),
          ),
        FilledButton.icon(
          onPressed: _deleting ? null : () => _editBlock(manual: manual),
          icon: const Icon(Icons.add),
          label: Text(manual ? 'Thêm lịch thủ công' : 'Thêm khoảng bận'),
        ),
        if (blocks.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Chưa có khoảng lịch.'),
          ),
        for (final block in blocks)
          Card(
            child: ListTile(
              title: Text(block.title),
              subtitle: Text(_describe(block)),
              onTap: _deleting
                  ? null
                  : () => _editBlock(manual: manual, existing: block),
              trailing: IconButton(
                tooltip: 'Xóa ${block.title}',
                onPressed: _deleting ? null : () => _deleteBlock(block),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
      ],
    );
  }

  String _describe(ScheduleBlock block) {
    final start = block.localStart;
    final end = block.localEnd;
    return [
      if (block.kind == ScheduleKind.work) 'Ca làm việc',
      '${calendarDateKey(start)} · ${clockLabel(start.hour * 60 + start.minute)}–${clockLabel(end.hour * 60 + end.minute)}'
          '${calendarDate(start) == calendarDate(end) ? '' : ' ngày hôm sau'}',
      block.timeZone,
      if (block.travelMinutes > 0)
        'Đi lại ${block.travelMinutes} phút mỗi chiều',
      if (block.repeatsWeekly) 'Lặp hằng tuần',
      if (block.exceptionDates.isNotEmpty)
        'Ngoại lệ ${block.exceptionDates.map(calendarDateKey).join(', ')}',
    ].join(' · ');
  }
}
