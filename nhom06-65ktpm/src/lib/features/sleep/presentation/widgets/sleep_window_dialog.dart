import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/sleep_window.dart';
import '../../domain/logic/sleep_schedule_analyzer.dart';

/// Kết quả trả về từ [SleepWindowDialog]: lưu khung mới hoặc xóa khung cố định.
sealed class SleepWindowDialogResult {
  const SleepWindowDialogResult();
}

class SaveSleepWindowResult extends SleepWindowDialogResult {
  final SleepWindow window;
  const SaveSleepWindowResult(this.window);
}

class ClearSleepWindowResult extends SleepWindowDialogResult {
  const ClearSleepWindowResult();
}

/// Hộp thoại thiết lập khoảng ngủ mong muốn (hỗ trợ cả ngủ đêm lẫn ca đêm ngủ ban ngày).
///
/// Cho phép nhập giờ trực tiếp bằng bàn phím hoặc chọn mẫu nhanh,
/// tuyệt đối không ép mốc 22:00 cho mọi người dùng.
class SleepWindowDialog extends StatefulWidget {
  final SleepWindow? initialWindow;

  const SleepWindowDialog({super.key, this.initialWindow});

  @override
  State<SleepWindowDialog> createState() => _SleepWindowDialogState();
}

class _SleepWindowDialogState extends State<SleepWindowDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _startHourCtrl;
  late final TextEditingController _startMinCtrl;
  late final TextEditingController _endHourCtrl;
  late final TextEditingController _endMinCtrl;
  late final TextEditingController _labelCtrl;

  String? _validationError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialWindow;
    _startHourCtrl = TextEditingController(
      text: (initial?.startHour ?? 23).toString().padLeft(2, '0'),
    );
    _startMinCtrl = TextEditingController(
      text: (initial?.startMin ?? 0).toString().padLeft(2, '0'),
    );
    _endHourCtrl = TextEditingController(
      text: (initial?.endHour ?? 7).toString().padLeft(2, '0'),
    );
    _endMinCtrl = TextEditingController(
      text: (initial?.endMin ?? 0).toString().padLeft(2, '0'),
    );
    _labelCtrl = TextEditingController(text: initial?.label ?? '');
  }

  @override
  void dispose() {
    _startHourCtrl.dispose();
    _startMinCtrl.dispose();
    _endHourCtrl.dispose();
    _endMinCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(SleepWindowPreset preset) {
    setState(() {
      _startHourCtrl.text = preset.window.startHour.toString().padLeft(2, '0');
      _startMinCtrl.text = preset.window.startMin.toString().padLeft(2, '0');
      _endHourCtrl.text = preset.window.endHour.toString().padLeft(2, '0');
      _endMinCtrl.text = preset.window.endMin.toString().padLeft(2, '0');
      _labelCtrl.text = preset.title;
      _validationError = null;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final hourCtrl = isStart ? _startHourCtrl : _endHourCtrl;
    final minCtrl = isStart ? _startMinCtrl : _endMinCtrl;
    final currentHour = int.tryParse(hourCtrl.text) ?? (isStart ? 23 : 7);
    final currentMin = int.tryParse(minCtrl.text) ?? 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentHour.clamp(0, 23),
        minute: currentMin.clamp(0, 59),
      ),
    );
    if (picked == null) return;
    setState(() {
      hourCtrl.text = picked.hour.toString().padLeft(2, '0');
      minCtrl.text = picked.minute.toString().padLeft(2, '0');
      _validationError = null;
    });
  }

  SleepWindow? _tryBuildWindow() {
    final sh = int.tryParse(_startHourCtrl.text.trim());
    final sm = int.tryParse(_startMinCtrl.text.trim());
    final eh = int.tryParse(_endHourCtrl.text.trim());
    final em = int.tryParse(_endMinCtrl.text.trim());
    if (sh == null || sm == null || eh == null || em == null) return null;
    if (sh < 0 || sh > 23 || eh < 0 || eh > 23) return null;
    if (sm < 0 || sm > 59 || em < 0 || em > 59) return null;
    return SleepWindow.fromHourMinute(
      startHour: sh,
      startMinute: sm,
      endHour: eh,
      endMinute: em,
      label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final window = _tryBuildWindow();
    if (window == null) {
      setState(() {
        _validationError = 'Vui lòng nhập giờ hợp lệ (00–23) và phút (00–59).';
      });
      return;
    }

    try {
      SleepScheduleAnalyzer.validateSleepWindow(window);
    } on SleepValidationException catch (err) {
      setState(() => _validationError = err.message);
      return;
    }

    Navigator.of(context).pop(SaveSleepWindowResult(window));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _tryBuildWindow();

    return AlertDialog(
      title: const Text('Khoảng ngủ mong muốn'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chọn khung ngủ phù hợp với nhịp sinh hoạt hoặc ca làm việc của riêng bạn (không bắt buộc mốc 22:00).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Gợi ý nhanh (tùy chọn)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: SleepWindow.presets.map((preset) {
                    return ActionChip(
                      label: Text(preset.title),
                      tooltip: preset.description,
                      onPressed: () => _applyPreset(preset),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Nhập giờ bắt đầu ngủ
                _ClockInputRow(
                  title: 'Giờ đi ngủ mong muốn',
                  hourController: _startHourCtrl,
                  minuteController: _startMinCtrl,
                  hourSemanticLabel: 'Giờ bắt đầu khoảng ngủ mong muốn',
                  minuteSemanticLabel: 'Phút bắt đầu khoảng ngủ mong muốn',
                  onPickTime: () => _pickTime(isStart: true),
                  onChanged: () => setState(() => _validationError = null),
                ),
                const SizedBox(height: 12),

                // Nhập giờ thức dậy
                _ClockInputRow(
                  title: 'Giờ thức dậy mong muốn',
                  hourController: _endHourCtrl,
                  minuteController: _endMinCtrl,
                  hourSemanticLabel: 'Giờ thức dậy khoảng ngủ mong muốn',
                  minuteSemanticLabel: 'Phút thức dậy khoảng ngủ mong muốn',
                  onPickTime: () => _pickTime(isStart: false),
                  onChanged: () => setState(() => _validationError = null),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _labelCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Nhãn lịch ngủ (tùy chọn)',
                    hintText: 'Ví dụ: Ca đêm — ngủ ban ngày',
                  ),
                  onFieldSubmitted: (_) => _submit(),
                ),

                if (preview != null && preview.startMinute != preview.endMinute) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Xem trước: ${preview.formattedRange} • ${preview.formattedDuration}'
                      '${preview.isDaytimeWindow ? ' (ngủ ban ngày / ca đêm)' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                if (_validationError != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _validationError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.initialWindow != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const ClearSleepWindowResult()),
            child: const Text('Bỏ khung cố định'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Lưu khung ngủ'),
        ),
      ],
    );
  }
}

class _ClockInputRow extends StatelessWidget {
  final String title;
  final TextEditingController hourController;
  final TextEditingController minuteController;
  final String hourSemanticLabel;
  final String minuteSemanticLabel;
  final VoidCallback onPickTime;
  final VoidCallback onChanged;

  const _ClockInputRow({
    required this.title,
    required this.hourController,
    required this.minuteController,
    required this.hourSemanticLabel,
    required this.minuteSemanticLabel,
    required this.onPickTime,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: hourSemanticLabel,
                child: TextFormField(
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
                      return '0–23';
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
                      return '0–59';
                    }
                    return null;
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Chọn giờ bằng đồng hồ',
              onPressed: onPickTime,
              icon: const Icon(Icons.access_time),
            ),
          ],
        ),
      ],
    );
  }
}
