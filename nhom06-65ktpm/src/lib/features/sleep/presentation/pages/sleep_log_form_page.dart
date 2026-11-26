import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/date_helper.dart';
import '../../domain/entities/sleep_log.dart';
import '../../domain/entities/sleep_window.dart';
import '../../domain/logic/sleep_schedule_analyzer.dart';

/// Callback lưu bản ghi ngủ; trả về `null` nếu thành công, hoặc thông báo lỗi nếu thất bại.
typedef SleepLogSaveCallback = Future<String?> Function({
  String? existingId,
  required DateTime sleptAt,
  required DateTime wokeAt,
  required AlertnessLevel alertness,
  String? note,
});

/// Màn hình thêm hoặc chỉnh sửa nhật ký giấc ngủ (Issue #5).
///
/// - Hỗ trợ nhập giờ/phút trực tiếp bằng bàn phím lẫn chọn giờ qua TimePicker.
/// - Tự động nhận diện giấc ngủ qua nửa đêm (+1 ngày) và ngủ ban ngày (ca đêm).
/// - Cho phép chọn mức tỉnh táo tự đánh giá (1–5) và ghi chú.
/// - Khẳng định minh bạch: không suy ra giấc ngủ thật từ thời gian không dùng điện thoại.
class SleepLogFormPage extends StatefulWidget {
  final SleepLog? initialLog;
  final SleepWindow? defaultWindow;
  final DateTime? referenceNow;
  final SleepLogSaveCallback onSave;

  const SleepLogFormPage({
    super.key,
    this.initialLog,
    this.defaultWindow,
    this.referenceNow,
    required this.onSave,
  });

  @override
  State<SleepLogFormPage> createState() => _SleepLogFormPageState();
}

class _SleepLogFormPageState extends State<SleepLogFormPage> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _startDate;
  DateTime? _explicitWakeDate;
  bool _manualWakeDate = false;

  late final TextEditingController _bedHourCtrl;
  late final TextEditingController _bedMinCtrl;
  late final TextEditingController _wakeHourCtrl;
  late final TextEditingController _wakeMinCtrl;
  late final TextEditingController _noteCtrl;

  late AlertnessLevel _alertness;
  bool _submitting = false;
  String? _formError;

  DateTime get _now => widget.referenceNow ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final existing = widget.initialLog;
    if (existing != null) {
      final start = existing.sleptAt.toLocal();
      final end = existing.wokeAt.toLocal();
      _startDate = DateHelper.normalize(start);
      _bedHourCtrl = TextEditingController(
        text: start.hour.toString().padLeft(2, '0'),
      );
      _bedMinCtrl = TextEditingController(
        text: start.minute.toString().padLeft(2, '0'),
      );
      _wakeHourCtrl = TextEditingController(
        text: end.hour.toString().padLeft(2, '0'),
      );
      _wakeMinCtrl = TextEditingController(
        text: end.minute.toString().padLeft(2, '0'),
      );
      _alertness = existing.alertness;
      _noteCtrl = TextEditingController(text: existing.note ?? '');
      // Nếu ngày thức không khớp suy luận mặc định (ví dụ ngủ kéo dài đặc biệt), bật chọn tay
      final expectedAutoNextDay =
          (end.hour * 60 + end.minute) < (start.hour * 60 + start.minute);
      final actualNextDay =
          DateHelper.isSameDay(end, DateHelper.shiftDays(_startDate, 1));
      final actualSameDay = DateHelper.isSameDay(end, _startDate);
      if ((expectedAutoNextDay && !actualNextDay) ||
          (!expectedAutoNextDay && !actualSameDay)) {
        _manualWakeDate = true;
        _explicitWakeDate = DateHelper.normalize(end);
      }
    } else {
      final window = widget.defaultWindow;
      final defaultBedHour = window?.startHour ?? 23;
      final defaultBedMin = window?.startMin ?? 0;
      final defaultWakeHour = window?.endHour ?? 7;
      final defaultWakeMin = window?.endMin ?? 0;
      final crossesMidnight =
          (defaultWakeHour * 60 + defaultWakeMin) <
          (defaultBedHour * 60 + defaultBedMin);

      final today = DateHelper.normalize(_now);
      // Nếu mặc định ngủ qua nửa đêm, chọn ngày bắt đầu là hôm qua để sáng nay đã thức dậy
      _startDate = crossesMidnight ? DateHelper.shiftDays(today, -1) : today;
      // Nếu là ngủ ban ngày mà giờ thức mặc định vượt quá hiện tại, lùi về hôm qua
      if (!crossesMidnight) {
        final candidateEnd = DateTime(
          _startDate.year,
          _startDate.month,
          _startDate.day,
          defaultWakeHour,
          defaultWakeMin,
        );
        if (candidateEnd.isAfter(_now)) {
          _startDate = DateHelper.shiftDays(today, -1);
        }
      }

      _bedHourCtrl = TextEditingController(
        text: defaultBedHour.toString().padLeft(2, '0'),
      );
      _bedMinCtrl = TextEditingController(
        text: defaultBedMin.toString().padLeft(2, '0'),
      );
      _wakeHourCtrl = TextEditingController(
        text: defaultWakeHour.toString().padLeft(2, '0'),
      );
      _wakeMinCtrl = TextEditingController(
        text: defaultWakeMin.toString().padLeft(2, '0'),
      );
      _alertness = AlertnessLevel.refreshed;
      _noteCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _bedHourCtrl.dispose();
    _bedMinCtrl.dispose();
    _wakeHourCtrl.dispose();
    _wakeMinCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  ({DateTime sleptAt, DateTime wokeAt, bool crossesMidnight})? _tryResolve() {
    final bh = int.tryParse(_bedHourCtrl.text.trim());
    final bm = int.tryParse(_bedMinCtrl.text.trim());
    final wh = int.tryParse(_wakeHourCtrl.text.trim());
    final wm = int.tryParse(_wakeMinCtrl.text.trim());
    if (bh == null || bm == null || wh == null || wm == null) return null;
    try {
      return SleepScheduleAnalyzer.resolveSleepInterval(
        startDate: _startDate,
        bedHour: bh,
        bedMinute: bm,
        wakeHour: wh,
        wakeMinute: wm,
        explicitWakeDate: _manualWakeDate ? _explicitWakeDate : null,
      );
    } on SleepValidationException {
      return null;
    }
  }

  Future<void> _pickDate({required bool isWakeDate}) async {
    final current = isWakeDate ? (_explicitWakeDate ?? _startDate) : _startDate;
    final today = DateHelper.normalize(_now);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(today) ? today : current,
      firstDate: DateHelper.shiftDays(today, -365),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() {
      if (isWakeDate) {
        _explicitWakeDate = DateHelper.normalize(picked);
      } else {
        _startDate = DateHelper.normalize(picked);
      }
      _formError = null;
    });
  }

  Future<void> _pickTime({required bool isBedtime}) async {
    final hourCtrl = isBedtime ? _bedHourCtrl : _wakeHourCtrl;
    final minCtrl = isBedtime ? _bedMinCtrl : _wakeMinCtrl;
    final h = int.tryParse(hourCtrl.text) ?? (isBedtime ? 23 : 7);
    final m = int.tryParse(minCtrl.text) ?? 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59)),
    );
    if (picked == null) return;
    setState(() {
      hourCtrl.text = picked.hour.toString().padLeft(2, '0');
      minCtrl.text = picked.minute.toString().padLeft(2, '0');
      _formError = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _formError = null);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final bh = int.parse(_bedHourCtrl.text.trim());
    final bm = int.parse(_bedMinCtrl.text.trim());
    final wh = int.parse(_wakeHourCtrl.text.trim());
    final wm = int.parse(_wakeMinCtrl.text.trim());

    late final ({DateTime sleptAt, DateTime wokeAt, bool crossesMidnight}) resolved;
    try {
      resolved = SleepScheduleAnalyzer.resolveSleepInterval(
        startDate: _startDate,
        bedHour: bh,
        bedMinute: bm,
        wakeHour: wh,
        wakeMinute: wm,
        explicitWakeDate: _manualWakeDate ? (_explicitWakeDate ?? _startDate) : null,
      );
    } on SleepValidationException catch (err) {
      setState(() => _formError = err.message);
      return;
    }

    setState(() => _submitting = true);
    final error = await widget.onSave(
      existingId: widget.initialLog?.id,
      sleptAt: resolved.sleptAt,
      wokeAt: resolved.wokeAt,
      alertness: _alertness,
      note: _noteCtrl.text.trim(),
    );

    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _formError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preview = _tryResolve();
    final isEditing = widget.initialLog != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Sửa nhật ký giấc ngủ' : 'Ghi nhật ký giấc ngủ'),
      ),
      body: SafeArea(
        child: FocusTraversalGroup(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Thông báo minh bạch nguồn dữ liệu
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Giờ ngủ, giờ thức và mức tỉnh táo do bạn tự khai báo. '
                                'Ứng dụng không suy ra giấc ngủ thật từ việc không dùng điện thoại '
                                'và hỗ trợ cả ca đêm ngủ ban ngày.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Chọn ngày bắt đầu ngủ
                      _DatePickerTile(
                        title: 'Ngày bắt đầu ngủ',
                        date: _startDate,
                        onPrevious: () => setState(() {
                          _startDate = DateHelper.shiftDays(_startDate, -1);
                          _formError = null;
                        }),
                        onNext: DateHelper.isFutureDay(
                          DateHelper.shiftDays(_startDate, 1),
                          _now,
                        )
                            ? null
                            : () => setState(() {
                                  _startDate = DateHelper.shiftDays(_startDate, 1);
                                  _formError = null;
                                }),
                        onPick: () => _pickDate(isWakeDate: false),
                      ),
                      const SizedBox(height: 16),

                      // Nhập giờ đi ngủ & giờ thức dậy (hỗ trợ bàn phím + time picker)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final bedField = _TimeInputCard(
                            title: 'Giờ đi ngủ',
                            hourKey: const Key('sleep_bed_hour'),
                            minuteKey: const Key('sleep_bed_minute'),
                            hourController: _bedHourCtrl,
                            minuteController: _bedMinCtrl,
                            hourSemanticLabel: 'Giờ đi ngủ từ 0 đến 23',
                            minuteSemanticLabel: 'Phút đi ngủ từ 0 đến 59',
                            onPickTime: () => _pickTime(isBedtime: true),
                            onChanged: () => setState(() => _formError = null),
                          );
                          final wakeField = _TimeInputCard(
                            title: 'Giờ thức dậy',
                            hourKey: const Key('sleep_wake_hour'),
                            minuteKey: const Key('sleep_wake_minute'),
                            hourController: _wakeHourCtrl,
                            minuteController: _wakeMinCtrl,
                            hourSemanticLabel: 'Giờ thức dậy từ 0 đến 23',
                            minuteSemanticLabel: 'Phút thức dậy từ 0 đến 59',
                            onPickTime: () => _pickTime(isBedtime: false),
                            onChanged: () => setState(() => _formError = null),
                          );

                          if (constraints.maxWidth >= 520) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: bedField),
                                const SizedBox(width: 12),
                                Expanded(child: wakeField),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              bedField,
                              const SizedBox(height: 12),
                              wakeField,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // Tùy chọn chỉnh tay ngày thức dậy (mặc định tự động suy luận qua nửa đêm)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Chọn ngày thức dậy thủ công'),
                        subtitle: const Text(
                          'Khi tắt, hệ thống tự động tính +1 ngày nếu giờ thức nhỏ hơn giờ ngủ.',
                        ),
                        value: _manualWakeDate,
                        onChanged: (val) => setState(() {
                          _manualWakeDate = val;
                          if (val && _explicitWakeDate == null) {
                            final auto = _tryResolve();
                            _explicitWakeDate = auto != null
                                ? DateHelper.normalize(auto.wokeAt)
                                : _startDate;
                          }
                          _formError = null;
                        }),
                      ),
                      if (_manualWakeDate) ...[
                        _DatePickerTile(
                          title: 'Ngày thức dậy',
                          date: _explicitWakeDate ?? _startDate,
                          onPrevious: () => setState(() {
                            final current = _explicitWakeDate ?? _startDate;
                            _explicitWakeDate = DateHelper.shiftDays(current, -1);
                            _formError = null;
                          }),
                          onNext: DateHelper.isFutureDay(
                            DateHelper.shiftDays(
                              _explicitWakeDate ?? _startDate,
                              1,
                            ),
                            _now,
                          )
                              ? null
                              : () => setState(() {
                                    final current = _explicitWakeDate ?? _startDate;
                                    _explicitWakeDate =
                                        DateHelper.shiftDays(current, 1);
                                    _formError = null;
                                  }),
                          onPick: () => _pickDate(isWakeDate: true),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Xem trước kết quả tính khoảng thời gian
                      if (preview != null &&
                          preview.wokeAt.isAfter(preview.sleptAt)) ...[
                        _SleepPreviewBanner(
                          sleptAt: preview.sleptAt,
                          wokeAt: preview.wokeAt,
                          crossesMidnight: preview.crossesMidnight,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Chọn mức tỉnh táo tự đánh giá (1–5)
                      Text(
                        'Mức tỉnh táo sau khi thức dậy (tự đánh giá)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: AlertnessLevel.values.map((level) {
                          final selected = _alertness == level;
                          return Semantics(
                            button: true,
                            selected: selected,
                            label:
                                'Mức tỉnh táo ${level.score} trên 5: ${level.label}',
                            child: ChoiceChip(
                              label: Text('${level.score} • ${level.label}'),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _alertness = level),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Ghi chú tùy chọn
                      TextFormField(
                        key: const Key('sleep_note_field'),
                        controller: _noteCtrl,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Ghi chú (tùy chọn)',
                          hintText:
                              'Ví dụ: Ngủ bù sau ca đêm, tỉnh giấc 1 lần giữa đêm...',
                          alignLabelWithHint: true,
                        ),
                        onFieldSubmitted: (_) => _submit(),
                      ),

                      if (_formError != null) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formError!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      Semantics(
                        button: true,
                        label: isEditing
                            ? 'Lưu thay đổi nhật ký ngủ'
                            : 'Lưu nhật ký ngủ mới',
                        child: FilledButton.icon(
                          key: const Key('sleep_save_button'),
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(
                            _submitting
                                ? 'Đang lưu...'
                                : (isEditing
                                    ? 'Lưu thay đổi'
                                    : 'Lưu nhật ký ngủ'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String title;
  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPick;

  const _DatePickerTile({
    required this.title,
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final label = DateHelper.formatVietnameseDate(date);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Lùi $title 1 ngày',
              child: IconButton(
                tooltip: 'Lùi 1 ngày',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
            ),
            Semantics(
              button: true,
              label: 'Tăng $title 1 ngày',
              child: IconButton(
                tooltip: 'Tiến 1 ngày',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ),
            Semantics(
              button: true,
              label: 'Mở lịch chọn $title',
              child: IconButton(
                tooltip: 'Chọn ngày',
                onPressed: onPick,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeInputCard extends StatelessWidget {
  final String title;
  final Key hourKey;
  final Key minuteKey;
  final TextEditingController hourController;
  final TextEditingController minuteController;
  final String hourSemanticLabel;
  final String minuteSemanticLabel;
  final VoidCallback onPickTime;
  final VoidCallback onChanged;

  const _TimeInputCard({
    required this.title,
    required this.hourKey,
    required this.minuteKey,
    required this.hourController,
    required this.minuteController,
    required this.hourSemanticLabel,
    required this.minuteSemanticLabel,
    required this.onPickTime,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Chọn $title bằng đồng hồ',
                  child: IconButton(
                    tooltip: 'Chọn bằng đồng hồ',
                    onPressed: onPickTime,
                    icon: const Icon(Icons.access_time, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: hourSemanticLabel,
                    child: TextFormField(
                      key: hourKey,
                      controller: hourController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Giờ (0–23)',
                        isDense: true,
                      ),
                      onChanged: (_) => onChanged(),
                      validator: (v) {
                        final parsed = int.tryParse((v ?? '').trim());
                        if (parsed == null || parsed < 0 || parsed > 23) {
                          return 'Nhập 0–23';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(':', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Semantics(
                    label: minuteSemanticLabel,
                    child: TextFormField(
                      key: minuteKey,
                      controller: minuteController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phút (0–59)',
                        isDense: true,
                      ),
                      onChanged: (_) => onChanged(),
                      validator: (v) {
                        final parsed = int.tryParse((v ?? '').trim());
                        if (parsed == null || parsed < 0 || parsed > 59) {
                          return 'Nhập 0–59';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepPreviewBanner extends StatelessWidget {
  final DateTime sleptAt;
  final DateTime wokeAt;
  final bool crossesMidnight;

  const _SleepPreviewBanner({
    required this.sleptAt,
    required this.wokeAt,
    required this.crossesMidnight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final durationMins = wokeAt.difference(sleptAt).inMinutes;
    final hours = durationMins ~/ 60;
    final mins = durationMins % 60;
    final durationText = mins == 0 ? '$hours giờ' : '$hours giờ $mins phút';

    final startStr =
        '${sleptAt.hour.toString().padLeft(2, '0')}:${sleptAt.minute.toString().padLeft(2, '0')} '
        '(${sleptAt.day.toString().padLeft(2, '0')}/${sleptAt.month.toString().padLeft(2, '0')})';
    final endStr =
        '${wokeAt.hour.toString().padLeft(2, '0')}:${wokeAt.minute.toString().padLeft(2, '0')} '
        '(${wokeAt.day.toString().padLeft(2, '0')}/${wokeAt.month.toString().padLeft(2, '0')})';

    final modeNote = crossesMidnight
        ? 'Qua nửa đêm (+1 ngày)'
        : (sleptAt.hour >= 5 && sleptAt.hour < 18
            ? 'Cùng ngày — ngủ ban ngày (ca đêm)'
            : 'Cùng ngày');

    return Semantics(
      liveRegion: true,
      label:
          'Xem trước giấc ngủ: từ $startStr đến $endStr, thời lượng $durationText, $modeNote',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              crossesMidnight
                  ? Icons.nights_stay_outlined
                  : Icons.wb_sunny_outlined,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$startStr → $endStr',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Tổng thời lượng: $durationText • $modeNote',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
