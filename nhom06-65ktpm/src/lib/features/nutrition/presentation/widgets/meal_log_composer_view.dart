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
  final Future<bool> Function()? syncLogs;

  const MealLogComposerView({
    super.key,
    required this.ownerUid,
    required this.profile,
    required this.useCase,
    this.mealType = 'lunch',
    this.aiPhotoLabelConsentGranted = false,
    this.syncLogs,
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
  bool _picking = false;
  bool _historyUnavailable = false;
  int _loadGeneration = 0;
  int _historyRequest = 0;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant MealLogComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerUid != widget.ownerUid ||
        oldWidget.mealType != widget.mealType ||
        oldWidget.profile != widget.profile) {
      _mealNameController.clear();
      _noteController.clear();
      _preparedPhoto = null;
      _optionalLabelResult = null;
      _statusMessage = null;
      _history = const [];
      _pendingPhotoCount = 0;
      _historyUnavailable = false;
      _loadInitialData();
    }
  }

  @override
  void dispose() {
    _mealNameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final generation = ++_loadGeneration;
    setState(() => _loading = true);
    final session = await widget.useCase.loadSuggestions(
      profile: widget.profile,
      mealType: widget.mealType,
    );
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _session = session;
      _loading = false;
      final current = session.currentOption;
      if (current != null && _mealNameController.text.trim().isEmpty) {
        _mealNameController.text = current.item.name;
      }
    });
    await _refreshHistory();
  }

  Future<void> _refreshHistory() async {
    final generation = _loadGeneration;
    final request = ++_historyRequest;
    final owner = widget.ownerUid;
    try {
      final history = await widget.useCase.getMealHistory(ownerUid: owner);
      final pendingCount = await widget.useCase.countPendingPhotos(
        ownerUid: owner,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          request != _historyRequest) {
        return;
      }
      setState(() {
        _history = history;
        _pendingPhotoCount = pendingCount;
        _historyUnavailable = false;
      });
    } catch (_) {
      if (mounted &&
          generation == _loadGeneration &&
          request == _historyRequest) {
        setState(() => _historyUnavailable = true);
      }
    }
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
    if (_picking || _saving) return;
    final generation = _loadGeneration;
    setState(() => _picking = true);
    final outcome = await widget.useCase.pickAndPreparePhoto(source);
    if (!mounted) return;
    setState(() => _picking = false);
    if (generation != _loadGeneration || outcome.cancelled) return;
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

  Future<bool> _syncLogs() async =>
      await (widget.syncLogs?.call() ?? Future.value(true));

  Future<void> _retryPendingPhotos() async {
    if (_saving || _picking) return;
    final generation = _loadGeneration;
    setState(() => _saving = true);
    try {
      final logsSynced = await _syncLogs();
      if (!mounted || generation != _loadGeneration) return;
      if (!logsSynced) {
        setState(() {
          _statusMessage =
              'Nhật ký vẫn lưu trên thiết bị. Hãy thử đồng bộ lại sau.';
        });
        return;
      }
      final report = await widget.useCase.retryPendingPhotoUploadsDetailed(
        ownerUid: widget.ownerUid,
      );
      if (!mounted || generation != _loadGeneration) return;
      final syncedAttachments = report.uploadedCount == 0 || await _syncLogs();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _statusMessage = !syncedAttachments
            ? '${report.userMessage} Nhật ký vẫn chờ đồng bộ.'
            : _pendingPhotoCount == 0 && widget.syncLogs != null
            ? 'Đã đồng bộ nhật ký bữa ăn.'
            : report.userMessage;
      });
      await _refreshHistory();
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _statusMessage = 'Chưa thể đồng bộ. Hãy thử lại sau.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveMealLog() async {
    if (_saving || _picking || !_formKey.currentState!.validate()) return;
    final generation = _loadGeneration;
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
      if (!mounted || generation != _loadGeneration) return;
      final synced = await _syncLogs();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _preparedPhoto = null;
        _optionalLabelResult = null;
        _noteController.clear();
        _statusMessage = synced
            ? result.userMessage
            : '${result.userMessage} Nhật ký còn lưu trên thiết bị để đồng bộ sau.';
      });
      await _refreshHistory();
    } on MealPhotoException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _statusMessage = error.message;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
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
                session?.result.emptyReason ?? 'Không có món gợi ý phù hợp. Bạn có thể tự nhập tên món bên dưới.',
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
                    onPressed: _saving || _picking
                        ? null
                        : () => _pickPhoto(MealPhotoSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Chụp ảnh bữa ăn'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving || _picking
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
                onPressed: _saving || _picking ? null : _saveMealLog,
                child: Text(_saving ? 'Đang lưu...' : 'Lưu nhật ký bữa ăn'),
              ),
              if (_pendingPhotoCount > 0 || widget.syncLogs != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _saving || _picking ? null : _retryPendingPhotos,
                  child: Text(
                    _pendingPhotoCount > 0
                        ? 'Thử đồng bộ $_pendingPhotoCount ảnh đang chờ'
                        : 'Đồng bộ nhật ký',
                  ),
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
        if (_historyUnavailable)
          TextButton(
            onPressed: _refreshHistory,
            child: const Text('Không thể tải nhật ký. Thử lại'),
          )
        else if (_history.isEmpty)
          const Text('Chưa có nhật ký bữa ăn nào.'),
        if (_history.isNotEmpty)
          ..._history.map(
            (log) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(log.mealName),
                subtitle: Text(_subtitleForLog(log)),
                trailing: log.hasPhoto
                    ? IconButton(
                        tooltip: 'Xem ảnh bữa ăn',
                        onPressed: () => _viewPhoto(log),
                        icon: const Icon(Icons.image_outlined),
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  void _viewPhoto(MealLog log) {
    final url = widget.useCase.photoStorage.createShortLivedSignedUrl(
      ownerUid: widget.ownerUid,
      storagePath: log.imagePath!,
    );
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(log.mealName),
        content: SizedBox(
          width: 360,
          height: 280,
          child: FutureBuilder<String?>(
            future: url,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final imageUrl = snapshot.data;
              if (imageUrl == null) {
                return const Text('Không thể mở ảnh riêng tư.');
              }
              return Image.network(
                imageUrl,
                fit: BoxFit.contain,
                semanticLabel: 'Ảnh bữa ăn',
                errorBuilder: (context, error, stackTrace) =>
                    const Text('Không thể tải ảnh riêng tư.'),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  static String _subtitleForLog(MealLog log) {
    if (log.hasPhoto) {
      return 'Có ảnh riêng tư';
    }
    if (log.photoUploadStatus == MealPhotoUploadStatus.pendingLocal) {
      return 'Đã lưu cục bộ • Ảnh đang chờ đồng bộ khi có mạng';
    }
    if (log.photoUploadStatus == MealPhotoUploadStatus.failed) {
      return 'Ảnh chưa được lưu';
    }
    return 'Ghi nhận nhập tay (không có ảnh)';
  }
}
