import 'package:flutter/material.dart';

import '../../../profile/domain/profile_time.dart';

/// Kết quả chọn khoảng giờ yên lặng từ hộp thoại cấu hình.
sealed class QuietHoursDialogResult {
  const QuietHoursDialogResult();
}

class SaveQuietHoursResult extends QuietHoursDialogResult {
  final int startMinute;
  final int endMinute;

  const SaveQuietHoursResult({
    required this.startMinute,
    required this.endMinute,
  });
}

class DisableQuietHoursResult extends QuietHoursDialogResult {
  const DisableQuietHoursResult();
}

/// Hộp thoại cài đặt **Giờ yên lặng** hỗ trợ cả khung ngủ đêm (`22:00 – 07:00`)
/// lẫn khung ban ngày cho người làm ca đêm (`08:00 – 15:00`).
class QuietHoursDialog extends StatefulWidget {
  final int? initialStartMinute;
  final int? initialEndMinute;

  const QuietHoursDialog({
    super.key,
    this.initialStartMinute,
    this.initialEndMinute,
  });

  @override
  State<QuietHoursDialog> createState() => _QuietHoursDialogState();
}

class _QuietHoursDialogState extends State<QuietHoursDialog> {
  late int _startMinute;
  late int _endMinute;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startMinute = widget.initialStartMinute ?? 22 * 60;
    _endMinute = widget.initialEndMinute ?? 7 * 60;
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startMinute : _endMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (picked == null) return;
    setState(() {
      final total = picked.hour * 60 + picked.minute;
      if (isStart) {
        _startMinute = total;
      } else {
        _endMinute = total;
      }
      _error = null;
    });
  }

  void _applyPreset(int start, int end) {
    setState(() {
      _startMinute = start;
      _endMinute = end;
      _error = null;
    });
  }

  void _submit() {
    if (_startMinute == _endMinute) {
      setState(() {
        _error = 'Giờ bắt đầu và giờ kết thúc không được trùng nhau.';
      });
      return;
    }
    Navigator.of(context).pop(
      SaveQuietHoursResult(startMinute: _startMinute, endMinute: _endMinute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final crossesMidnight = _startMinute > _endMinute;
    return AlertDialog(
      title: const Text('Cấu hình giờ yên lặng'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Lời nhắc rơi vào khoảng giờ yên lặng sẽ được tự động lùi sang ngay sau giờ kết thúc. '
              'Hỗ trợ cả ca ngày lẫn ca đêm (ngủ ban ngày).',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  key: const Key('quiet_preset_night'),
                  label: const Text('Ban đêm (22:00 – 07:00)'),
                  onPressed: () => _applyPreset(22 * 60, 7 * 60),
                ),
                ActionChip(
                  key: const Key('quiet_preset_shift'),
                  label: const Text('Ca đêm — ngủ ngày (08:00 – 15:00)'),
                  onPressed: () => _applyPreset(8 * 60, 15 * 60),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bắt đầu yên lặng'),
              trailing: OutlinedButton(
                key: const Key('quiet_start_picker'),
                onPressed: () => _pickTime(isStart: true),
                child: Text(clockLabel(_startMinute)),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kết thúc yên lặng'),
              trailing: OutlinedButton(
                key: const Key('quiet_end_picker'),
                onPressed: () => _pickTime(isStart: false),
                child: Text(clockLabel(_endMinute)),
              ),
            ),
            Text(
              crossesMidnight
                  ? 'Khung hiện tại: ${clockLabel(_startMinute)} – ${clockLabel(_endMinute)} (qua nửa đêm)'
                  : 'Khung hiện tại: ${clockLabel(_startMinute)} – ${clockLabel(_endMinute)} (trong ngày)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('quiet_disable_button'),
          onPressed: () =>
              Navigator.of(context).pop(const DisableQuietHoursResult()),
          child: const Text('Tắt giờ yên lặng'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('quiet_save_button'),
          onPressed: _submit,
          child: const Text('Lưu khung giờ'),
        ),
      ],
    );
  }
}
