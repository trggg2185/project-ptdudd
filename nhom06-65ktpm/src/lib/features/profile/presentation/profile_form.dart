import 'package:flutter/material.dart';

import '../domain/health_profile.dart';
import '../domain/profile_time.dart';

class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.initialProfile,
    required this.save,
    required this.openManualSchedule,
  });

  final HealthProfile initialProfile;
  final Future<void> Function(HealthProfile) save;
  final VoidCallback openManualSchedule;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final _form = GlobalKey<FormState>();
  late HealthProfile _lastSaved = widget.initialProfile;
  late bool _adult = _lastSaved.adultConfirmed;
  late bool _needsGuidance = _lastSaved.requiresProfessionalGuidance;
  late ProfileGoal? _goal = _lastSaved.goal;
  late ActivityLevel? _activity = _lastSaved.activityLevel;
  late String? _occupation = _lastSaved.occupation;
  late AllergyStatus _allergyStatus = _lastSaved.allergyStatus;
  late int? _sleepStart = _lastSaved.sleepStart;
  late int? _sleepEnd = _lastSaved.sleepEnd;
  late final _zone = TextEditingController(text: _lastSaved.timeZone);
  late final _minutes = _numberController(_lastSaved.sessionMinutes);
  late final _sessions = _numberController(_lastSaved.sessionsPerWeek);
  late final _exerciseBudget = _numberController(_lastSaved.exerciseBudget);
  late final _mealBudget = _numberController(_lastSaved.mealBudget);
  late final _avoided = TextEditingController(
    text: _lastSaved.avoidedIngredients.join(', '),
  );
  late final _equipment = _lastSaved.equipment.toSet();
  late final _sports = _lastSaved.preferredSports.toSet();
  late final _avoidSports = _lastSaved.dislikedSports.toSet();
  late final _limits = _lastSaved.movementLimits.toSet();
  late final _allergens = _lastSaved.allergens.toSet();
  bool _saving = false;
  String? _feedback;

  static TextEditingController _numberController(int? value) =>
      TextEditingController(text: value?.toString());

  @override
  void dispose() {
    for (final field in [
      _zone,
      _minutes,
      _sessions,
      _exerciseBudget,
      _mealBudget,
      _avoided,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final zone = _zone.text.trim();
    final ingredients = _avoided.text
        .split(RegExp(r'[,;\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (ingredients.any((item) => HealthProfile.ingredientCode(item).isEmpty)) {
      setState(() => _feedback = 'Hãy nhập tên nguyên liệu hợp lệ.');
      return;
    }
    final profile = HealthProfile(
      adultConfirmed: _adult,
      requiresProfessionalGuidance: _needsGuidance,
      timeZone: zone.isEmpty ? null : zone,
      goal: _goal,
      activityLevel: _activity,
      occupation: _occupation,
      sessionMinutes: int.tryParse(_minutes.text.trim()),
      sessionsPerWeek: int.tryParse(_sessions.text.trim()),
      exerciseBudget: int.tryParse(_exerciseBudget.text.trim()),
      mealBudget: int.tryParse(_mealBudget.text.trim()),
      sleepStart: _sleepStart,
      sleepEnd: _sleepEnd,
      allergyStatus: _allergyStatus,
      allergens: _allergyStatus == AllergyStatus.declared
          ? _allergens
          : const [],
      avoidedIngredients: ingredients,
      equipment: _equipment,
      preferredSports: _sports,
      dislikedSports: _avoidSports,
      movementLimits: _limits,
    );
    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      profile.validate();
      await widget.save(profile);
      if (!mounted) return;
      setState(() {
        _lastSaved = profile;
        _feedback = 'Đã lưu hồ sơ.';
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _feedback = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _feedback = 'Không thể lưu hồ sơ. Tải lại trang nếu hồ sơ đã đổi trên thiết bị khác.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickSleepTime({required bool start}) async {
    final value = (start ? _sleepStart : _sleepEnd) ?? (start ? 1320 : 360);
    final time = await showTimePicker(
      context: context,
      useRootNavigator: false,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
    );
    if (time == null || !mounted) return;
    setState(() {
      if (start) {
        _sleepStart = time.hour * 60 + time.minute;
      } else {
        _sleepEnd = time.hour * 60 + time.minute;
      }
    });
  }

  Widget _choice<T>(
    String label,
    T? value,
    Map<T, String> choices,
    ValueChanged<T?> changed,
  ) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<T>(child: const Text('Chưa khai báo')),
        for (final item in choices.entries)
          DropdownMenuItem(value: item.key, child: Text(item.value)),
      ],
      onChanged: _saving ? null : (next) => setState(() => changed(next)),
    );
  }

  Widget _number(
    String label,
    TextEditingController controller,
    int minimum, {
    int? maximum,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_saving,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      validator: (text) {
        final value = text?.trim() ?? '';
        if (value.isEmpty) return null;
        final number = int.tryParse(value);
        if (number == null ||
            number < minimum ||
            (maximum != null && number > maximum)) {
          return maximum == null
              ? 'Nhập số nguyên từ $minimum.'
              : 'Nhập số nguyên từ $minimum đến $maximum.';
        }
        return null;
      },
    );
  }

  Widget _choices(
    String label,
    Map<String, String> options,
    Set<String> selected, {
    Set<String>? opposite,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Wrap(
        spacing: 8,
        children: [
          for (final option in options.entries)
            FilterChip(
              label: Text(option.value),
              selected: selected.contains(option.key),
              onSelected: _saving
                  ? null
                  : (enabled) => setState(() {
                      if (enabled) {
                        selected.add(option.key);
                        opposite?.remove(option.key);
                      } else {
                        selected.remove(option.key);
                      }
                    }),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blockedReason = _lastSaved.automaticScheduleBlockReason;
    return Form(
      key: _form,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              blockedReason ?? 'Hồ sơ đã đủ dữ liệu cơ bản cho gợi ý vận động.',
              style: theme.textTheme.bodyMedium,
            ),
            if (!_lastSaved.allergiesAreConfirmed)
              const Text('Xác nhận dị ứng để sử dụng gợi ý món ăn.'),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: widget.openManualSchedule,
                child: const Text('Mở lịch thủ công'),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _adult,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _adult = value ?? false),
              title: const Text('Tôi xác nhận mình từ 18 tuổi trở lên'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _needsGuidance,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _needsGuidance = value ?? false),
              title: const Text(
                'Tôi cần hướng dẫn chuyên môn trước khi lập lịch tự động',
              ),
            ),
            TextFormField(
              controller: _zone,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Múi giờ IANA',
                hintText: defaultProfileZone,
                helperText: 'Ví dụ Asia/Ho_Chi_Minh hoặc UTC',
              ),
              autocorrect: false,
              validator: (value) {
                final zone = value?.trim() ?? '';
                return zone.isEmpty || profileLocation(zone) != null
                    ? null
                    : 'Múi giờ không hợp lệ.';
              },
            ),
            const SizedBox(height: 12),
            _choice(
              'Mục tiêu',
              _goal,
              HealthProfile.goals,
              (value) => _goal = value,
            ),
            const SizedBox(height: 12),
            _choice(
              'Mức vận động hiện tại',
              _activity,
              HealthProfile.activityLevels,
              (value) => _activity = value,
            ),
            const SizedBox(height: 12),
            _choice('Công việc', _occupation, {
              ...HealthProfile.occupations,
              if (_occupation != null &&
                  !HealthProfile.occupations.containsKey(_occupation))
                _occupation!: _occupation!,
            }, (value) => _occupation = value),
            const SizedBox(height: 12),
            _number('Số buổi có thể tập mỗi tuần', _sessions, 1, maximum: 14),
            const SizedBox(height: 12),
            _number('Số phút có thể tập mỗi buổi', _minutes, 1, maximum: 240),
            const SizedBox(height: 12),
            _choices(
              'Môn tập yêu thích',
              HealthProfile.sports,
              _sports,
              opposite: _avoidSports,
            ),
            _choices(
              'Môn tập muốn tránh',
              HealthProfile.sports,
              _avoidSports,
              opposite: _sports,
            ),
            _choices(
              'Thiết bị sẵn có',
              HealthProfile.availableEquipment,
              _equipment,
            ),
            _choices(
              'Giới hạn vận động',
              HealthProfile.movementOptions,
              _limits,
            ),
            const SizedBox(height: 12),
            _number('Ngân sách mỗi buổi tập (đồng)', _exerciseBudget, 0),
            const SizedBox(height: 12),
            _number('Ngân sách mỗi bữa ăn (đồng)', _mealBudget, 0),
            const SizedBox(height: 12),
            DropdownButtonFormField<AllergyStatus>(
              initialValue: _allergyStatus,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tình trạng dị ứng thực phẩm',
              ),
              items: const [
                DropdownMenuItem(
                  value: AllergyStatus.unconfirmed,
                  child: Text('Chưa xác nhận'),
                ),
                DropdownMenuItem(
                  value: AllergyStatus.none,
                  child: Text('Đã xác nhận không có dị ứng'),
                ),
                DropdownMenuItem(
                  value: AllergyStatus.declared,
                  child: Text('Có dị ứng cần khai báo'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _allergyStatus = value);
                    },
            ),
            if (_allergyStatus == AllergyStatus.declared) ...[
              _choices('Dị nguyên', HealthProfile.allergenOptions, _allergens),
              const Text(
                'Nếu dị nguyên của bạn chưa có trong danh sách, hãy chọn Chưa xác nhận.',
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _avoided,
              enabled: !_saving,
              maxLength: 250,
              decoration: const InputDecoration(
                labelText: 'Nguyên liệu cần tránh',
                helperText: 'Cách nhau bằng dấu phẩy, ví dụ đậu phộng, cá hồi',
              ),
            ),
            Text('Giờ ngủ mong muốn', style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : () => _pickSleepTime(start: true),
                  child: Text(
                    _sleepStart == null
                        ? 'Chọn giờ ngủ'
                        : 'Ngủ ${clockLabel(_sleepStart!)}',
                  ),
                ),
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => _pickSleepTime(start: false),
                  child: Text(
                    _sleepEnd == null
                        ? 'Chọn giờ thức'
                        : 'Thức ${clockLabel(_sleepEnd!)}',
                  ),
                ),
                if (_sleepStart != null || _sleepEnd != null)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _sleepStart = null;
                            _sleepEnd = null;
                          }),
                    child: const Text('Xóa giờ ngủ'),
                  ),
              ],
            ),
            if (_feedback case final message?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Semantics(liveRegion: true, child: Text(message)),
              ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Đang lưu…' : 'Lưu hồ sơ'),
            ),
          ],
        ),
      ),
    );
  }
}
