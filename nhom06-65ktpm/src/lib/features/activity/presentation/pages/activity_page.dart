import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/entities/activity_session.dart';
import '../../domain/repositories/activity_repository.dart';
import '../controllers/activity_controller.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({
    super.key,
    required this.repository,
    required this.ownerUid,
    this.initialActivityName,
  });

  final ActivityRepository repository;
  final String ownerUid;
  final String? initialActivityName;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with WidgetsBindingObserver {
  late final ActivityController _controller;
  final _manualDurationController = TextEditingController();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _clock;
  bool _requestingLocation = false;

  static const _standardActivities = [
    'Chạy bộ',
    'Đi bộ',
    'Đạp xe',
    'Yoga',
    'Bơi',
    'Hoạt động khác',
  ];
  late final _activities = [
    if (widget.initialActivityName case final name?
        when !_standardActivities.contains(name))
      name,
    ..._standardActivities,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ActivityController(
      repository: widget.repository,
      ownerUid: widget.ownerUid,
    );
    if (widget.initialActivityName case final name?) {
      _controller.setActivityName(name);
    }
    _controller.loadSessions();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _clock?.cancel();
    _controller.dispose();
    _manualDurationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_controller.tracker.status == ActivityStatus.recording) {
        _controller.pauseGps(DateTime.now());
        _positionSubscription?.cancel();
        _positionSubscription = null;
        _controller.setGpsStatus('GPS đã tạm dừng khi ra nền');
      }
    }
  }

  Future<String?> _locationProblem() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'Dịch vụ vị trí đang tắt';
      }
      if (!mounted) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && mounted) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'Quyền GPS bị từ chối';
      }
      return null;
    } catch (_) {
      return 'Không thể truy cập GPS. Bạn có thể nhập nhật ký thủ công.';
    }
  }

  bool get _canRecordHere {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.of(context)?.isCurrent != false;
  }

  Future<void> _beginRecording({required bool resume}) async {
    if (_requestingLocation) return;
    setState(() => _requestingLocation = true);
    try {
      final problem = await _locationProblem();
      final expectedStatus = resume
          ? ActivityStatus.paused
          : ActivityStatus.idle;
      if (!_canRecordHere || _controller.tracker.status != expectedStatus) {
        return;
      }
      if (problem != null) {
        _controller.setGpsStatus(problem);
        return;
      }

      final now = DateTime.now();
      if (resume) {
        _controller.resumeGps(now);
      } else {
        _controller.startGps(now);
      }
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 5,
            ),
          ).listen(
            (position) {
              if (!_canRecordHere ||
                  _controller.tracker.status != ActivityStatus.recording) {
                return;
              }
              _controller.setGpsStatus('Đang ghi GPS');
              _controller.addGpsPoint(
                GpsPoint(
                  latitude: position.latitude,
                  longitude: position.longitude,
                  accuracyMeters: position.accuracy,
                  recordedAt: position.timestamp,
                ),
              );
            },
            onError: (_) {
              if (mounted &&
                  _controller.tracker.status == ActivityStatus.recording) {
                _controller.tracker.breakSegment();
                _controller.setGpsStatus('Mất tín hiệu GPS');
              }
            },
          );
    } catch (_) {
      if (mounted && _controller.tracker.status == ActivityStatus.recording) {
        _pauseGps();
        _controller.setGpsStatus(
          'Không thể ghi GPS. Bạn có thể nhập thủ công.',
        );
      }
    } finally {
      if (mounted) setState(() => _requestingLocation = false);
    }
  }

  void _pauseGps() {
    _controller.pauseGps(DateTime.now());
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _stopGps() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _controller.stopGps(DateTime.now());
  }

  Future<void> _saveGpsSession() async {
    await _controller.saveGpsSession(DateTime.now());
  }

  Future<void> _saveManualSession() async {
    final duration = int.tryParse(_manualDurationController.text);
    if (duration == null || duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập thời lượng lớn hơn 0 phút'),
        ),
      );
      return;
    }
    await _controller.saveManualSession(
      durationMinutes: duration,
      date: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final now = DateTime.now();
        final duration = _controller.tracker.durationAt(now);
        final status = _controller.tracker.status;
        return Scaffold(
          appBar: AppBar(title: const Text('Nhật ký vận động')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                key: const Key('activity-name'),
                initialValue: _controller.activityName,
                decoration: const InputDecoration(labelText: 'Môn vận động'),
                items: _activities
                    .map(
                      (name) =>
                          DropdownMenuItem(value: name, child: Text(name)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) _controller.setActivityName(value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('activity-feeling'),
                decoration: const InputDecoration(
                  labelText: 'Cảm nhận',
                  hintText: 'Ví dụ: thoải mái, mệt nhẹ',
                ),
                onChanged: _controller.setFeeling,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _controller.gpsStatus,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        '${_controller.tracker.estimatedDistanceMeters.toStringAsFixed(0)} m',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              key: const Key('gps-start'),
                              onPressed:
                                  status == ActivityStatus.idle &&
                                      !_requestingLocation
                                  ? () => _beginRecording(resume: false)
                                  : null,
                              child: const Text('Start'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('gps-pause-resume'),
                              onPressed: status == ActivityStatus.recording
                                  ? _pauseGps
                                  : status == ActivityStatus.paused &&
                                        !_requestingLocation
                                  ? () => _beginRecording(resume: true)
                                  : null,
                              child: Text(
                                status == ActivityStatus.paused
                                    ? 'Resume'
                                    : 'Pause',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('gps-stop'),
                              onPressed:
                                  status == ActivityStatus.recording ||
                                      status == ActivityStatus.paused
                                  ? _stopGps
                                  : null,
                              child: const Text('Stop'),
                            ),
                          ),
                        ],
                      ),
                      if (status == ActivityStatus.stopped) ...[
                        CheckboxListTile(
                          key: const Key('save-route'),
                          contentPadding: EdgeInsets.zero,
                          value: _controller.routeSaved,
                          onChanged: _controller.isLoading
                              ? null
                              : (value) =>
                                    _controller.setRouteSaved(value ?? false),
                          title: const Text('Lưu tuyến đường'),
                          subtitle: const Text(
                            'Chỉ lưu tọa độ khi bạn chủ động chọn',
                          ),
                        ),
                        FilledButton(
                          key: const Key('save-gps-session'),
                          onPressed: _controller.isLoading
                              ? null
                              : _saveGpsSession,
                          child: const Text('Lưu phiên'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: const Key('cancel-gps-session'),
                          onPressed: _controller.isLoading
                              ? null
                              : _controller.resetGps,
                          child: const Text('Hủy / Đặt lại phiên'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Hoặc nhập thủ công'),
              const SizedBox(height: 8),
              TextField(
                key: const Key('manual-duration'),
                controller: _manualDurationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Thời lượng (phút)',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('save-manual-session'),
                onPressed: _controller.isLoading ? null : _saveManualSession,
                child: const Text('Lưu nhật ký thủ công'),
              ),
              if (_controller.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Lịch sử'),
              if (_controller.isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ..._controller.sessions.map(
                  (session) => Card(
                    child: ListTile(
                      title: Text(session.activityName),
                      subtitle: Text(
                        '${(session.durationSeconds / 60).round()} phút'
                        '${session.feeling.isEmpty ? '' : ' • ${session.feeling}'}'
                        '${session.routeSaved ? ' • Có tuyến đường' : ' • Không lưu tuyến'}',
                      ),
                      trailing: session.estimatedDistanceMeters > 0
                          ? Text(
                              '${session.estimatedDistanceMeters.toStringAsFixed(0)} m',
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
