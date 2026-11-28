import 'package:flutter/material.dart';

import '../../../core/utils/id_generator.dart';
import '../../profile/domain/profile_time.dart';
import '../domain/weekly_plan.dart';
import '../domain/weekly_planner.dart';

class PlanItemEditor extends StatefulWidget {
  const PlanItemEditor({
    super.key,
    required this.calendar,
    required this.day,
    required this.items,
    required this.now,
    this.item,
  });

  final PlannerCalendar calendar;
  final DateTime day;
  final List<PlanItem> items;
  final DateTime Function() now;
  final PlanItem? item;

  @override
  State<PlanItemEditor> createState() => _PlanItemEditorState();
}

class _PlanItemEditorState extends State<PlanItemEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.item?.title);
  late DateTime _day = _initialDay();
  late final _time = TextEditingController(text: _initialTime());
  late final _duration = TextEditingController(
    text:
        (widget.item?.endsAt.difference(widget.item!.startsAt).inMinutes ?? 30)
            .toString(),
  );
  late PlanItemKind _kind = widget.item?.kind ?? PlanItemKind.manual;
  String? _problem;

  DateTime _initialDay() {
    final week = widget.calendar.week;
    final item = widget.item;
    if (item == null) return widget.day;
    final date = calendarDate(week.local(item.startsAt));
    return date.isBefore(week.monday) || date.isAfter(week.day(6))
        ? widget.day
        : date;
  }

  String _initialTime() {
    final item = widget.item;
    if (item == null) return '18:00';
    final local = widget.calendar.week.local(item.startsAt);
    return clockLabel(local.hour * 60 + local.minute);
  }

  int? _minutes(String text) {
    final parts = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (parts == null) return null;
    final hour = int.parse(parts[1]!);
    final minute = int.parse(parts[2]!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  Future<void> _pickDay() async {
    final week = widget.calendar.week;
    final date = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: _day,
      firstDate: week.monday,
      lastDate: week.day(6),
    );
    if (date != null && mounted) setState(() => _day = calendarDate(date));
  }

  void _confirm() {
    if (!_form.currentState!.validate()) return;
    final week = widget.calendar.week;
    final minutes = _minutes(_time.text)!;
    final start = week.at(_day, minutes);
    final local = week.local(start);
    if (calendarDate(local) != _day ||
        local.hour * 60 + local.minute != minutes) {
      setState(
        () => _problem = 'Giờ này không tồn tại trong múi giờ hiện tại.',
      );
      return;
    }
    if (!start.isAfter(widget.now())) {
      setState(() => _problem = 'Chọn thời gian trong tương lai.');
      return;
    }
    final original = widget.item;
    final item = PlanItem(
      id: original?.id ?? IdGenerator.generateUuid(),
      kind: _kind,
      title: _title.text.trim(),
      startsAt: start,
      endsAt: start.add(Duration(minutes: int.parse(_duration.text.trim()))),
      isLocked: original?.isLocked ?? true,
      reason: original?.kind == _kind && original?.title == _title.text.trim()
          ? original?.reason
          : null,
      mealType: _kind == PlanItemKind.meal ? original?.mealType : null,
    );
    final conflict = widget.calendar.conflictFor(item, widget.items);
    if (conflict != null) {
      setState(() => _problem = conflict);
      return;
    }
    Navigator.of(context).pop(item);
  }

  @override
  void dispose() {
    _title.dispose();
    _time.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.item == null ? 'Thêm hoạt động' : 'Sửa hoạt động'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<PlanItemKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Loại hoạt động'),
                items: [
                  for (final kind in PlanItemKind.values)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (kind) {
                  if (kind != null) setState(() => _kind = kind);
                },
              ),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Tên hoạt động'),
                maxLength: 80,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nhập tên hoạt động.'
                    : null,
              ),
              OutlinedButton(
                onPressed: _pickDay,
                child: Text('Ngày ${calendarDateKey(_day)}'),
              ),
              TextFormField(
                controller: _time,
                decoration: const InputDecoration(
                  labelText: 'Giờ bắt đầu (HH:mm)',
                ),
                validator: (value) => _minutes(value ?? '') == null
                    ? 'Nhập giờ hợp lệ, ví dụ 18:30.'
                    : null,
              ),
              TextFormField(
                controller: _duration,
                decoration: const InputDecoration(
                  labelText: 'Thời lượng (phút)',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final minutes = int.tryParse(value?.trim() ?? '');
                  return minutes == null || minutes < 1 || minutes > 1440
                      ? 'Nhập từ 1 đến 1440 phút.'
                      : null;
                },
              ),
              if (_problem case final problem?)
                Semantics(liveRegion: true, child: Text(problem)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Giữ trong bản nháp'),
        ),
      ],
    );
  }
}
