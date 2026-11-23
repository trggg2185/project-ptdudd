import 'package:flutter/material.dart';

import '../../../recommendations/domain/entities/recommendation_profile.dart';
import '../../domain/entities/meal_label_suggestion.dart';
import '../../domain/entities/meal_log.dart';
import '../../domain/entities/meal_photo_attachment.dart';
import '../../domain/entities/meal_photo_policy.dart';
import '../../domain/entities/meal_suggestion_session.dart';
import '../../domain/usecases/meal_nutrition_usecase.dart';

/// Màn hình/widget ghi nhật ký bữa ăn độc lập (không chỉnh `main.dart`):
/// - Gợi ý & đổi món theo hồ sơ người dùng từ module `recommendations`.
/// - Cho người dùng tự sửa và xác nhận tên món ăn thực tế.
/// - Chụp/chọn ảnh, kiểm tra định dạng/kích thước, nén & xóa EXIF ngay ở client.
/// - Fallback nhập tay khi từ chối quyền/ảnh lỗi và giữ nhật ký + ảnh chờ khi mất mạng.
class MealLogComposerView extends StatefulWidget {
  final String ownerUid;
  final RecommendationProfile profile;
  final MealNutritionUseCase useCase;
  final String mealType;
  final bool aiPhotoLabelConsentGranted;

  const MealLogComposerView({
    super.key,
    required this.ownerUid,
    required this.profile,
    required this.useCase,
    this.mealType = 'lunch',
    this.aiPhotoLabelConsentGranted = false,
  });

  @override
  State<MealLogComposerView> createState() => _MealLogComposerViewState();
}

class _MealLogComposerViewState extends State<MealLogComposerView> {
  final _formKey = GlobalKey<FormState>();
  final _mealNameController = TextEditingController();
  final _noteController = TextEditingController();

  MealSuggestionSession? _session;
  PreparedMealPhoto? _preparedPhoto;
  MealLabelSuggestionResult? _optionalLabelResult;
  List<MealLog> _history = const [];
  int _pendingPhotoCount = 0;
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
    final pendingCount = await widget.useCase.countPendingPhotos(
      ownerUid: widget.ownerUid,
    );
    if (!mounted) return;
    setState(() {
      _session = session;
      _history = history;
      _pendingPhotoCount = pendingCount;
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
    final outcome = await widget.useCase.pickAndPreparePhoto(source);
    if (!mounted || outcome.cancelled) return;
    if (!outcome.hasPhoto) {
      setState(() {
        _preparedPhoto = null;
        _optionalLabelResult = null;
        _statusMessage = outcome.userMessage;
      });
      return;
    }

    final prepared = outcome.preparedPhoto!;
    setState(() {
      _preparedPhoto = prepared;
      _optionalLabelResult = null;
      _statusMessage = null;
    });

    // AI chỉ là phần mở rộng không chặn luồng cốt lõi; không tự ghi đè tên món người dùng.
    final labelResult = await widget.useCase
        .requestOptionalPhotoLabelSuggestions(
          ownerUid: widget.ownerUid,
          photo: prepared,
          aiConsentGranted: widget.aiPhotoLabelConsentGranted,
        );
    if (!mounted || _preparedPhoto != prepared) return;
    setState(() {
      _optionalLabelResult = labelResult;
    });
  }

  Future<void> _retryPendingPhotos() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final uploaded = await widget.useCase.retryPendingPhotoUploads(
        ownerUid: widget.ownerUid,
      );
      final updatedHistory = await widget.useCase.getMealHistory(
        ownerUid: widget.ownerUid,
      );
      final remaining = await widget.useCase.countPendingPhotos(
        ownerUid: widget.ownerUid,
      );
      if (!mounted) return;
      setState(() {
        _history = updatedHistory;
        _pendingPhotoCount = remaining;
        _statusMessage = uploaded > 0
            ? 'Đã đồng bộ $uploaded ảnh bữa ăn đang chờ.'
            : 'Chưa thể đồng bộ ảnh đang chờ, dữ liệu vẫn an toàn ở cục bộ.';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
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

      final result = await widget.useCase.saveMealLogResilient(
        ownerUid: widget.ownerUid,
        confirmedMealName: confirmedName,
        mealType: widget.mealType,
        selectedCatalogMeal: matchedCatalog,
        preparedPhoto: _preparedPhoto,
        note: _noteController.text,
      );
      final updatedHistory = await widget.useCase.getMealHistory(
        ownerUid: widget.ownerUid,
      );
      final pendingCount = await widget.useCase.countPendingPhotos(
        ownerUid: widget.ownerUid,
      );
      if (!mounted) return;
      setState(() {
        _history = updatedHistory;
        _pendingPhotoCount = pendingCount;
        _preparedPhoto = null;
        _optionalLabelResult = null;
        _noteController.clear();
        _statusMessage = result.userMessage;
      });
    } on MealPhotoException catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Không thể hoàn tất thao tác. Vui lòng thử lưu lại nhật ký.';
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              MealLabelSuggestionResult.photoSafetyDisclaimer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 12),
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
              if (_preparedPhoto case final photo?) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Ảnh đính kèm: ${photo.fileName}'),
                  subtitle: Text(
                    '${photo.source == MealPhotoSource.camera ? 'Camera' : 'Thư viện'} • ${photo.sizeBytes} bytes • Đã xóa EXIF',
                  ),
                  trailing: TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _preparedPhoto = null;
                            _optionalLabelResult = null;
                          }),
                    child: const Text('Bỏ ảnh'),
                  ),
                ),
                if (_optionalLabelResult case final labelResult?
                    when labelResult.hasCandidates) ...[
                  const SizedBox(height: 4),
                  Text(
                    labelResult.userNotice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: labelResult.candidateLabels
                        .map(
                          (label) => ActionChip(
                            label: Text(label),
                            onPressed: _saving
                                ? null
                                : () {
                                    setState(() {
                                      _mealNameController.text = label;
                                    });
                                  },
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _saveMealLog,
                child: Text(_saving ? 'Đang lưu...' : 'Lưu nhật ký bữa ăn'),
              ),
              if (_pendingPhotoCount > 0) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _saving ? null : _retryPendingPhotos,
                  child: Text('Thử đồng bộ $_pendingPhotoCount ảnh đang chờ'),
                ),
              ],
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
                subtitle: Text(_subtitleForLog(log)),
              ),
            ),
          ),
      ],
    );
  }

  static String _subtitleForLog(MealLog log) {
    if (log.hasPhoto) {
      return 'Ảnh riêng tư: ${log.imagePath}';
    }
    if (log.photoUploadStatus == MealPhotoUploadStatus.pendingLocal) {
      return 'Đã lưu cục bộ • Ảnh đang chờ đồng bộ khi có mạng';
    }
    return 'Ghi nhận nhập tay (không có ảnh)';
  }
}
