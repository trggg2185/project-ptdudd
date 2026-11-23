import 'package:flutter/material.dart';

import '../../../recommendations/domain/entities/recommendation_profile.dart';
import '../../domain/entities/meal_log.dart';
import '../../domain/entities/meal_photo_attachment.dart';
import '../../domain/entities/meal_suggestion_session.dart';
import '../../domain/usecases/meal_nutrition_usecase.dart';

/// Màn hình/widget ghi nhật ký bữa ăn độc lập (không chỉnh `main.dart`):
/// - Gợi ý & đổi món theo hồ sơ người dùng từ module `recommendations`.
/// - Cho người dùng tự sửa và xác nhận tên món ăn thực tế.
/// - Cho chụp ảnh từ camera hoặc chọn ảnh từ thư viện, rồi lưu nhật ký.
class MealLogComposerView extends StatefulWidget {
  final String ownerUid;
  final RecommendationProfile profile;
  final MealNutritionUseCase useCase;
  final String mealType;

  const MealLogComposerView({
    super.key,
    required this.ownerUid,
    required this.profile,
    required this.useCase,
    this.mealType = 'lunch',
  });

  @override
  State<MealLogComposerView> createState() => _MealLogComposerViewState();
}

class _MealLogComposerViewState extends State<MealLogComposerView> {
  final _formKey = GlobalKey<FormState>();
  final _mealNameController = TextEditingController();
  final _noteController = TextEditingController();

  MealSuggestionSession? _session;
  SelectedMealPhoto? _selectedPhoto;
  List<MealLog> _history = const [];
  bool _loading = true;
  bool _saving = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _mealNameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    final session = await widget.useCase.loadSuggestions(
      profile: widget.profile,
      mealType: widget.mealType,
    );
    final history = await widget.useCase.getMealHistory(
      ownerUid: widget.ownerUid,
    );
    if (!mounted) return;
    setState(() {
      _session = session;
      _history = history;
      _loading = false;
      final current = session.currentOption;
      if (current != null && _mealNameController.text.trim().isEmpty) {
        _mealNameController.text = current.item.name;
      }
    });
  }

  void _swapMeal() {
    final currentSession = _session;
    if (currentSession == null || !currentSession.canSwap) return;
    final nextSession = widget.useCase.swapSuggestion(currentSession);
    setState(() {
      _session = nextSession;
      final option = nextSession.currentOption;
      if (option != null) {
        _mealNameController.text = option.item.name;
      }
    });
  }

  Future<void> _pickPhoto(MealPhotoSource source) async {
    final picked = await widget.useCase.captureOrPickPhoto(source);
    if (!mounted || picked == null) return;
    setState(() {
      _selectedPhoto = picked;
      _statusMessage = null;
    });
  }

  Future<void> _saveMealLog() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _statusMessage = null;
    });
    try {
      final currentOption = _session?.currentOption?.item;
      final confirmedName = _mealNameController.text.trim();
      final matchedCatalog =
          currentOption != null && confirmedName == currentOption.name
          ? currentOption
          : null;

      await widget.useCase.confirmAndLogMeal(
        ownerUid: widget.ownerUid,
        confirmedMealName: confirmedName,
        mealType: widget.mealType,
        selectedCatalogMeal: matchedCatalog,
        selectedPhoto: _selectedPhoto,
        note: _noteController.text,
      );
      final updatedHistory = await widget.useCase.getMealHistory(
        ownerUid: widget.ownerUid,
      );
      if (!mounted) return;
      setState(() {
        _history = updatedHistory;
        _selectedPhoto = null;
        _noteController.clear();
        _statusMessage = 'Đã lưu nhật ký bữa ăn "$confirmedName".';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Không thể lưu nhật ký bữa ăn: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final session = _session;
    final currentOption = session?.currentOption;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Gợi ý món ăn theo hồ sơ',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (currentOption == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                session?.result.emptyReason ??
                    'Không có món gợi ý phù hợp. Bạn có thể tự nhập tên món bên dưới.',
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentOption.item.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(currentOption.explanation),
                  const SizedBox(height: 4),
                  Text(
                    currentOption.conditionsSummary,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: session!.canSwap ? _swapMeal : null,
                        child: const Text('Đổi món khác'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          _mealNameController.text = currentOption.item.name;
                        },
                        child: const Text('Dùng tên gợi ý'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _mealNameController,
                decoration: const InputDecoration(
                  labelText: 'Tên món bạn xác nhận đã ăn',
                  hintText: 'Nhập hoặc chỉnh tên món thực tế',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập tên món bạn xác nhận.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú bữa ăn (tùy chọn)',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _pickPhoto(MealPhotoSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Chụp ảnh bữa ăn'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _pickPhoto(MealPhotoSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Chọn từ thư viện'),
                  ),
                ],
              ),
              if (_selectedPhoto case final photo?) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Ảnh đính kèm: ${photo.fileName}'),
                  subtitle: Text(
                    photo.source == MealPhotoSource.camera
                        ? 'Nguồn: Camera (${photo.sizeBytes} bytes)'
                        : 'Nguồn: Thư viện (${photo.sizeBytes} bytes)',
                  ),
                  trailing: TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _selectedPhoto = null),
                    child: const Text('Bỏ ảnh'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _saveMealLog,
                child: Text(_saving ? 'Đang lưu...' : 'Lưu nhật ký bữa ăn'),
              ),
              if (_statusMessage case final message?) ...[
                const SizedBox(height: 8),
                Text(message),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Nhật ký bữa ăn đã ghi (${_history.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          const Text('Chưa có nhật ký bữa ăn nào.')
        else
          ..._history.map(
            (log) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(log.mealName),
                subtitle: Text(
                  log.hasPhoto
                      ? 'Ảnh riêng tư: ${log.imagePath}'
                      : 'Ghi nhận nhập tay (không có ảnh)',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
