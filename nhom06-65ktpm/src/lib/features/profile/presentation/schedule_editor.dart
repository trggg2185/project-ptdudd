import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/utils/id_generator.dart';
import '../domain/profile_time.dart';
import '../domain/schedule_block.dart';

class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({
    super.key,
    required this.timeZone,
    required this.isManual,
    required this.save,
    this.initialBlock,
  });

  final String timeZone;
  final bool isManual;
  final ScheduleBlock? initialBlock;
  final Future<void> Function(ScheduleBlock) save;

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  final _form = GlobalKey<FormState>();
  late final _existing = widget.initialBlock;
  late final _id = _existing?.id ?? IdGenerator.generateUuid();
  late final _title = TextEditingController(text: _existing?.title);
  late final _zone = TextEditingController(
    text: _existing?.timeZone ?? widget.timeZone,
  );
  late final _travel = TextEditingController(
    text: _existing?.travelMinutes.toString(),
  );
  late ScheduleKind _kind =
      _existing?.kind ??
      (widget.isManual ? ScheduleKind.manual : ScheduleKind.busy);
  late DateTime _date = calendarDate(
    _existing?.localStart ?? _today(widget.timeZone),
  );
  late int _start = _existing == null
      ? 480
      : _existing.localStart.hour * 60 + _existing.localStart.minute;
  late int _end = _existing == null
      ? 540
      : _existing.localEnd.hour * 60 + _existing.localEnd.minute;
  late bool _weekly = _existing?.repeatsWeekly ?? false;
  late final Set<DateTime> _exceptions =
      _existing?.exceptionDates.toSet() ?? {};
  bool _saving = false;
  String? _error;

  DateTime _today(String name) =>
      tz.TZDateTime.now(profileLocation(name) ?? tz.UTC);

  @override
  void dispose() {
    _title.dispose();
    _zone.dispose();
    _travel.dispose();
    super.dispose();
  }

  Future<void> _pickDay({required bool exception}) async {
    final first = exception ? _date : DateTime(1900);
    final date = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: _date,
      firstDate: first,
      lastDate: DateTime(2200),
      selectableDayPredicate: exception
          ? (value) => isWeeklyOccurrenceDate(value, _date)
          : null,
    );
    if (date == null || !mounted) return;
    setState(() {
      if (exception) {
        _exceptions.add(calendarDate(date));
      } else {
        _date = calendarDate(date);
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final minute = start ? _start : _end;
    final time = await showTimePicker(
      context: context,
      useRootNavigator: false,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (time == null || !mounted) return;
    setState(() {
      if (start) {
        _start = time.hour * 60 + time.minute;
      } else {
        _end = time.hour * 60 + time.minute;
      }
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final slot = ScheduleBlock.fromLocal(
        id: _id,
        kind: _kind,
        title: _title.text,
        timeZone: _zone.text.trim(),
        date: _date,
        startMinute: _start,
        endMinute: _end,
        travelMinutes: int.tryParse(_travel.text.trim()) ?? 0,
        repeatsWeekly: _weekly,
        exceptionDates: _weekly ? _exceptions : const [],
      );
      await widget.save(slot);
      if (mounted) Navigator.of(context).pop(slot);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không thể lưu khoảng lịch. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exceptions = _exceptions.toList()..sort();
    final invalidExceptions = _weekly
        ? exceptions.where((day) => !isWeeklyOccurrenceDate(day, _date)).toSet()
        : const <DateTime>{};
    final errorColor = Theme.of(context).colorScheme.error;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          _existing != null
              ? 'Sửa khoảng lịch'
              : widget.isManual
              ? 'Thêm lịch thủ công'
              : 'Thêm khoảng bận',
        ),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.isManual) ...[
                  DropdownButtonFormField<ScheduleKind>(
                    initialValue: _kind,
                    decoration: const InputDecoration(
                      labelText: 'Loại khoảng bận',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ScheduleKind.busy,
                        child: Text('Khoảng bận'),
                      ),
                      DropdownMenuItem(
                        value: ScheduleKind.work,
                        child: Text('Ca làm việc'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (kind) {
                            if (kind != null) setState(() => _kind = kind);
                          },
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _title,
                  maxLength: 80,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Tên khoảng lịch',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập tên khoảng lịch.'
                      : null,
                ),
                TextFormField(
                  controller: _zone,
                  enabled: !_saving,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Múi giờ IANA'),
                  validator: (value) => profileLocation(value?.trim()) == null
                      ? 'Múi giờ không hợp lệ.'
                      : null,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _saving ? null : () => _pickDay(exception: false),
                  child: Text('Ngày bắt đầu ${calendarDateKey(_date)}'),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : () => _pickTime(start: true),
                      child: Text('Bắt đầu ${clockLabel(_start)}'),
                    ),
                    OutlinedButton(
                      onPressed: _saving ? null : () => _pickTime(start: false),
                      child: Text('Kết thúc ${clockLabel(_end)}'),
                    ),
                  ],
                ),
                if (_end < _start) const Text('Kết thúc vào ngày hôm sau.'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _travel,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Đi lại mỗi chiều (phút)',
                    helperText: 'Để trống nếu không cần đi lại',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (text) {
                    final value = text?.trim() ?? '';
                    if (value.isEmpty) return null;
                    final minutes = int.tryParse(value);
                    return minutes == null || minutes < 0 || minutes > 1440
                        ? 'Nhập số phút từ 0 đến 1440.'
                        : null;
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lặp hằng tuần vào ngày này'),
                  value: _weekly,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _weekly = value),
                ),
                if (_weekly) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final day in exceptions)
                        InputChip(
                          label: Text(calendarDateKey(day)),
                          labelStyle: invalidExceptions.contains(day)
                              ? TextStyle(color: errorColor)
                              : null,
                          onDeleted: _saving
                              ? null
                              : () => setState(() => _exceptions.remove(day)),
                        ),
                    ],
                  ),
                  if (invalidExceptions.isNotEmpty)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Bỏ ngày ngoại lệ ${invalidExceptions.map(calendarDateKey).join(', ')} '
                        'hoặc đổi ngày bắt đầu.',
                        style: TextStyle(color: errorColor),
                      ),
                    ),
                  TextButton(
                    onPressed: _saving ? null : () => _pickDay(exception: true),
                    child: const Text('Thêm ngày ngoại lệ'),
                  ),
                ],
                if (_error case final message?)
                  Semantics(liveRegion: true, child: Text(message)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: _saving || invalidExceptions.isNotEmpty ? null : _save,
            child: Text(_saving ? 'Đang lưu…' : 'Lưu khoảng lịch'),
          ),
        ],
      ),
    );
  }
}
