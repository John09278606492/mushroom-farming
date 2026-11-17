import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/farm_repository.dart';
import '../logic/alerts.dart';
import '../models/farm_models.dart';

/// A command the app sent that the controller has not confirmed yet.
class _Pending<T> {
  _Pending(this.want, this.sentAt);
  final T want;
  final DateTime sentAt;
}

/// Holds the latest farm data for the whole UI and sends commands.
///
/// It listens to every repository stream once and rebuilds listeners every
/// second so "updated 5 s ago" and the online/offline state stay current.
class FarmState extends ChangeNotifier {
  FarmState(this.repo, {DateTime Function()? clock, bool tickEverySecond = true})
      : _clock = clock ?? DateTime.now {
    _subs.addAll([
      repo.watchLive().listen(_onLive),
      repo.watchControl().listen((v) => _set(() => control = v)),
      repo.watchSetpoints().listen((v) => _set(() {
            setpoints = v;
            setpointsLoaded = true;
          })),
      repo.watchSchedules().listen((v) => _set(() => schedules = v)),
      repo.watchCamera().listen((v) => _set(() => camera = v)),
      repo.watchHarvest().listen((v) => _set(() => harvest = v)),
      repo.watchBatches().listen((v) => _set(() => batches = v)),
      repo.watchConnection().listen((v) => _set(() => phoneConnected = v)),
    ]);
    if (tickEverySecond) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    }
  }

  /// A command not confirmed within this time is reported as failed.
  static const commandTimeout = Duration(seconds: 20);

  final FarmRepository repo;
  final DateTime Function() _clock;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _ticker;
  bool _disposed = false;

  LiveData live = LiveData.empty;
  bool liveLoaded = false;
  ControlState control = ControlState.empty;
  Setpoints setpoints = Setpoints.fruiting;
  bool setpointsLoaded = false;
  ScheduleTable schedules = emptyScheduleTable();
  CameraShot? camera;
  HarvestResult? harvest;
  List<Batch> batches = const [];
  bool phoneConnected = true;

  final Map<DeviceId, _Pending<bool>> _pendingDevices = {};
  _Pending<FarmMode>? _pendingMode;

  /// One-shot messages for the UI (shown as snack bars), e.g. timeouts.
  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  DateTime get now => _clock();
  bool get online => live.isOnline(now);

  List<FarmAlert> get alerts => liveLoaded ? computeAlerts(live, setpoints, now) : const [];

  Batch? get openBatch {
    for (final b in batches) {
      if (b.isOpen) return b;
    }
    return null;
  }

  bool isDevicePending(DeviceId d) => _pendingDevices.containsKey(d);

  /// The state to show on a switch: the requested one while pending.
  bool deviceDisplayState(DeviceId d) => _pendingDevices[d]?.want ?? live.deviceOn(d);

  bool get modePending => _pendingMode != null;
  FarmMode get modeDisplay => _pendingMode?.want ?? live.mode;

  String? lockReason(DeviceId d) => deviceLockReason(d, live, now);

  void _set(VoidCallback f) {
    if (_disposed) return;
    f();
    notifyListeners();
  }

  void _onLive(LiveData v) {
    _set(() {
      live = v;
      liveLoaded = true;
      _pendingDevices.removeWhere((d, p) => v.deviceOn(d) == p.want);
      if (_pendingMode != null && v.mode == _pendingMode!.want) _pendingMode = null;
    });
  }

  void _onTick() {
    final t = now;
    final timedOut = _pendingDevices.entries
        .where((e) => t.difference(e.value.sentAt) > commandTimeout)
        .map((e) => e.key)
        .toList();
    for (final d in timedOut) {
      _pendingDevices.remove(d);
      _messages.add('${d.label}: the controller did not respond.');
    }
    if (_pendingMode != null && t.difference(_pendingMode!.sentAt) > commandTimeout) {
      _pendingMode = null;
      _messages.add('Mode change: the controller did not respond.');
    }
    _set(() {});
  }

  /// Returns an error message, or null when the command was sent.
  Future<String?> setDevice(DeviceId d, bool on) async {
    final reason = lockReason(d);
    if (reason != null) return reason;
    _set(() => _pendingDevices[d] = _Pending(on, now));
    try {
      await repo.setDevice(d, on);
      return null;
    } catch (e) {
      _set(() => _pendingDevices.remove(d));
      return 'Could not send the command: $e';
    }
  }

  Future<String?> setMode(FarmMode mode) async {
    if (!online) return 'Controller offline';
    _set(() => _pendingMode = _Pending(mode, now));
    try {
      await repo.setMode(mode);
      return null;
    } catch (e) {
      _set(() => _pendingMode = null);
      return 'Could not change the mode: $e';
    }
  }

  Future<String?> saveSetpoints(Setpoints sp) => _guard(() => repo.saveSetpoints(sp));

  Future<String?> saveSchedule(ScheduleDevice d, int slot, Schedule? s) =>
      _guard(() => repo.saveSchedule(d, slot, s));

  Future<String?> startBatch() => _guard(repo.startBatch);

  Future<String?> finishBatch(String id, {double? weightG, String notes = ''}) =>
      _guard(() => repo.finishBatch(id, weightG: weightG, notes: notes));

  Future<String?> _guard(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } on ArgumentError catch (e) {
      return e.message?.toString() ?? e.toString();
    } catch (e) {
      return 'Could not save: $e';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _messages.close();
    super.dispose();
  }
}
