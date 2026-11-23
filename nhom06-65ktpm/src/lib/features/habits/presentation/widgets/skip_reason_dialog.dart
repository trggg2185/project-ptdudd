import 'package:flutter/material.dart';

/// Hộp thoại chọn lý do bỏ qua thói quen có lý do chính đáng.
class SkipReasonDialog extends StatefulWidget {
  final String habitName;

  const SkipReasonDialog({super.key, required this.habitName});

  @override
  State<SkipReasonDialog> createState() => _SkipReasonDialogState();
}

class _SkipReasonDialogState extends State<SkipReasonDialog> {
  static const List<String> _suggestedReasons = [
    'Ốm / Sức khỏe không tốt',
    'Bận đột xuất / Lịch làm thay đổi',
    'Thời tiết xấu / Không thuận lợi',
    'Đi công tác / Di chuyển xa',
    'Cần thời gian hồi phục thể lực',
  ];

  String? _selectedReason = _suggestedReasons.first;
  final TextEditingController _customController = TextEditingController();
  bool _isCustom = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.pause_circle_outline, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bỏ qua "${widget.habitName}"',
              style: const TextStyle(fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bỏ qua có lý do hợp lệ sẽ không phá vỡ chuỗi kỷ luật (Streak) của bạn:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ..._suggestedReasons.map((reason) {
              final isChosen = !_isCustom && _selectedReason == reason;
              return InkWell(
                onTap: () {
                  setState(() {
                    _isCustom = false;
                    _selectedReason = reason;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    children: [
                      Icon(
                        isChosen ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: isChosen ? Theme.of(context).colorScheme.primary : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(reason, style: const TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              );
            }),
            InkWell(
              onTap: () {
                setState(() {
                  _isCustom = true;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Icon(
                      _isCustom ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: _isCustom ? Theme.of(context).colorScheme.primary : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Lý do khác...', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
            if (_isCustom) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Nhập lý do cụ thể...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            final finalReason = _isCustom
                ? (_customController.text.trim().isNotEmpty
                    ? _customController.text.trim()
                    : 'Bỏ qua có lý do')
                : (_selectedReason ?? 'Bỏ qua có lý do');
            Navigator.of(context).pop(finalReason);
          },
          child: const Text('Xác nhận bỏ qua'),
        ),
      ],
    );
  }
}
