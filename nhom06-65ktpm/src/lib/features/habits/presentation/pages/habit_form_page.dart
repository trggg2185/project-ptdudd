import 'package:flutter/material.dart';

import '../../../../core/utils/id_generator.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_frequency.dart';

/// Màn hình thêm mới hoặc chỉnh sửa thói quen.
class HabitFormPage extends StatefulWidget {
  final Habit? habit;
  final String ownerUid;

  const HabitFormPage({super.key, this.habit, required this.ownerUid});

  @override
  State<HabitFormPage> createState() => _HabitFormPageState();
}

class _HabitFormPageState extends State<HabitFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;

  FrequencyType _frequencyType = FrequencyType.daily;
  Set<int> _customDays = {1, 2, 3, 4, 5, 6, 7};
  TimeOfDay? _reminderTime;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _nameController = TextEditingController(text: h?.name ?? '');
    _descController = TextEditingController(text: h?.description ?? '');

    if (h != null) {
      _frequencyType = h.frequency.type;
      _customDays = Set.from(h.frequency.scheduledDays);
      _isActive = h.isActive;
      if (h.reminderTime != null && h.reminderTime!.contains(':')) {
        final parts = h.reminderTime!.split(':');
        _reminderTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 8,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.habit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Chỉnh sửa thói quen' : 'Thêm thói quen mới'),
        actions: [
          TextButton(
            onPressed: _saveForm,
            child: const Text('Lưu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên thói quen *',
                hintText: 'Ví dụ: Uống 2 lít nước, Tập yoga 20 phút',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.star_outline),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Vui lòng nhập tên thói quen';
                }
                if (val.trim().length > 100) {
                  return 'Tên thói quen không vượt quá 100 ký tự';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Mô tả / Mục tiêu (tùy chọn)',
                hintText: 'Chi tiết lợi ích hoặc kế hoạch rèn luyện kỷ luật...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chu kỳ lặp lại',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            _buildFrequencySelector(),
            const SizedBox(height: 24),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              leading: const Icon(Icons.alarm, color: Colors.blueAccent),
              title: const Text('Thời gian nhắc nhở'),
              subtitle: Text(
                _reminderTime != null
                    ? '${_reminderTime!.hour.toString().padLeft(2, '0')}:${_reminderTime!.minute.toString().padLeft(2, '0')}'
                    : 'Chưa đặt giờ nhắc',
              ),
              trailing: _reminderTime != null
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => setState(() => _reminderTime = null),
                    )
                  : const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _pickTime,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              secondary: Icon(
                _isActive ? Icons.play_circle_outline : Icons.pause_circle_outline,
                color: _isActive ? Colors.green : Colors.grey,
              ),
              title: const Text('Kích hoạt theo dõi'),
              subtitle: Text(_isActive ? 'Đang thực hiện hằng ngày' : 'Tạm dừng không tính streak'),
              value: _isActive,
              onChanged: (val) => setState(() => _isActive = val),
            ),
            if (isEditing) ...[
              const SizedBox(height: 32),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Xóa thói quen này'),
                onPressed: _confirmDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFrequencySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Hằng ngày'),
              selected: _frequencyType == FrequencyType.daily,
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _frequencyType = FrequencyType.daily;
                    _customDays = {1, 2, 3, 4, 5, 6, 7};
                  });
                }
              },
            ),
            ChoiceChip(
              label: const Text('Ngày trong tuần (T2-T6)'),
              selected: _frequencyType == FrequencyType.customDays &&
                  _customDays.length == 5 &&
                  !_customDays.contains(6) &&
                  !_customDays.contains(7),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _frequencyType = FrequencyType.customDays;
                    _customDays = {1, 2, 3, 4, 5};
                  });
                }
              },
            ),
            ChoiceChip(
              label: const Text('Cuối tuần (T7, CN)'),
              selected: _frequencyType == FrequencyType.customDays &&
                  _customDays.length == 2 &&
                  _customDays.contains(6) &&
                  _customDays.contains(7),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _frequencyType = FrequencyType.customDays;
                    _customDays = {6, 7};
                  });
                }
              },
            ),
            ChoiceChip(
              label: const Text('Tùy chọn ngày'),
              selected: _frequencyType == FrequencyType.customDays &&
                  !(_customDays.length == 5 && !_customDays.contains(6) && !_customDays.contains(7)) &&
                  !(_customDays.length == 2 && _customDays.contains(6) && _customDays.contains(7)),
              onSelected: (val) {
                if (val) {
                  setState(() {
                    _frequencyType = FrequencyType.customDays;
                  });
                }
              },
            ),
          ],
        ),
        if (_frequencyType == FrequencyType.customDays) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _dayButton(1, 'T2'),
              _dayButton(2, 'T3'),
              _dayButton(3, 'T4'),
              _dayButton(4, 'T5'),
              _dayButton(5, 'T6'),
              _dayButton(6, 'T7'),
              _dayButton(7, 'CN'),
            ],
          ),
          if (_customDays.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6.0),
              child: Text(
                'Vui lòng chọn ít nhất một ngày trong tuần',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ],
    );
  }

  Widget _dayButton(int dayIndex, String label) {
    final isSelected = _customDays.contains(dayIndex);
    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _customDays.remove(dayIndex);
          } else {
            _customDays.add(dayIndex);
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade200,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final initial = _reminderTime ?? const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() => _reminderTime = picked);
    }
  }

  void _saveForm() {
    if (!_formKey.currentState!.validate()) return;

    if (_frequencyType == FrequencyType.customDays && _customDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ít nhất một ngày thực hiện thói quen!')),
      );
      return;
    }

    final freq = _frequencyType == FrequencyType.daily
        ? const HabitFrequency.daily()
        : HabitFrequency.custom(_customDays);

    final timeStr = _reminderTime != null
        ? '${_reminderTime!.hour.toString().padLeft(2, '0')}:${_reminderTime!.minute.toString().padLeft(2, '0')}'
        : null;

    final habit = Habit(
      id: widget.habit?.id ?? IdGenerator.generateUuid(),
      ownerUid: widget.ownerUid,
      name: _nameController.text.trim(),
      description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
      frequency: freq,
      reminderTime: timeStr,
      isActive: _isActive,
      createdAt: widget.habit?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      version: (widget.habit?.version ?? 0) + 1,
    );

    Navigator.of(context).pop(habit);
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Bạn có chắc chắn muốn xóa thói quen này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop('delete');
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}
