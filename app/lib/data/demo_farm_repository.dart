import 'dart:async';
import 'dart:math';

import '../models/farm_models.dart';
import 'farm_repository.dart';

/// A simulated farm. It runs the same control rules as the ESP32 firmware
/// (firmware/original/esp_32/esp_32_body), so the app can be tried and demoed
/// before the hardware and Firebase are ready.
class DemoFarmRepository implements FarmRepository {
  DemoFarmRepository({
    bool autoTick = true,
    this.commandDelay = const Duration(milliseconds: 900),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _seed();
    if (autoTick) {
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => tick());
    }
  }

  /// How long a command takes to "reach" the controller (shows the
  /// pending state in the UI). Zero applies commands immediately.
  final Duration commandDelay;
  final DateTime Function() _clock;
  Timer? _timer;
  final _rng = Random(42);

  // Simulated physical state.
  double _temp = 26.4;
  double _rh = 83;
  double _co2 = 960;
  double _water = 0.55; // 0 = empty, 1 = full
  FarmMode _mode = FarmMode.auto;
  final Map<DeviceId, bool> _actual = {for (final d in DeviceId.values) d: false};
  DateTime? _sprinklerStop;
  DateTime? _lightStop;
  int _lastScheduleMinute = -1;
  final Set<String> _firedThisMinute = {};
  DateTime? _lastHistoryAt;

  final _live = _Subject<LiveData>(LiveData.empty);
  final _control = _Subject<ControlState>(ControlState.empty);
  final _setpoints = _Subject<Setpoints>(Setpoints.fruiting);
  final _schedules = _Subject<ScheduleTable>(emptyScheduleTable());
  final _history = _Subject<List<HistoryPoint>>(const []);
  final _camera = _Subject<CameraShot?>(null);
  final _harvest = _Subject<HarvestResult?>(null);
  final _batches = _Subject<List<Batch>>(const []);

  static const _lowWaterLevel = 0.3;
  static const _cutoffLevel = 0.08;

  @override
  String get farmName => 'Demo farm';

  @override
  bool get isDemo => true;

  void _seed() {
    final now = _clock();

    // A week of history every 10 minutes, with a daily temperature swing.
    final points = <HistoryPoint>[];
    for (var t = now.subtract(const Duration(days: 7));
        t.isBefore(now);
        t = t.add(const Duration(minutes: 10))) {
      final hourAngle = (t.hour + t.minute / 60) / 24 * 2 * pi;
      points.add(HistoryPoint(
        ts: t,
        temp: 25.5 + 2.2 * sin(hourAngle - pi / 2) + _noise(0.3),
        rh: 89 + 3.5 * sin(hourAngle * 3) + _noise(1.2),
        co2: (820 + 180 * sin(hourAngle * 2) + _noise(40)).round(),
      ));
    }
    _history.value = points;
    _lastHistoryAt = now;

    // Light 6:00 AM for 12 h every day; sprinkler 3 min at 8 AM and 2 PM.
    final table = emptyScheduleTable();
    table[ScheduleDevice.light]![0] = Schedule.newFor(ScheduleDevice.light);
    table[ScheduleDevice.sprinkler]![0] =
        Schedule.newFor(ScheduleDevice.sprinkler).copyWith(hour: 8);
    table[ScheduleDevice.sprinkler]![1] =
        Schedule.newFor(ScheduleDevice.sprinkler).copyWith(hour: 14);
    _schedules.value = table;
    if (now.hour >= 6 && now.hour < 18) {
      _actual[DeviceId.light] = true;
      _lightStop = DateTime(now.year, now.month, now.day, 18);
    }

    _batches.value = [
      Batch(id: 'demo-2', pinnedAt: now.subtract(const Duration(days: 4, hours: 3))),
      Batch(
        id: 'demo-1',
        pinnedAt: now.subtract(const Duration(days: 19)),
        harvestedAt: now.subtract(const Duration(days: 13)),
        weightG: 1250,
        notes: 'First flush',
      ),
    ];
    _updateHarvest();
    _control.value = ControlState(mode: _mode, devices: Map.of(_actual));
    _publishLive();
  }

  double _noise(double amp) => (_rng.nextDouble() * 2 - 1) * amp;

  bool get _cutoff => _water < _cutoffLevel;
  bool get _lowWater => _water < _lowWaterLevel;

  /// Advances the simulation by one controller cycle (2 s).
  void tick() {
    final now = _clock();
    _runSchedules(now);
    if (_mode == FarmMode.auto) _runAutoLogic();
    _enforceSafety();

    // Physics.
    _rh += _actual[DeviceId.mist]! ? 1.6 : -0.5;
    if (_actual[DeviceId.sprinkler]!) _rh += 2.5;
    if (_actual[DeviceId.fan]!) _rh -= 0.4;
    _rh = (_rh + _noise(0.3)).clamp(40, 99.5);

    _co2 += _actual[DeviceId.fan]! ? -55 : 18;
    _co2 = (_co2 + _noise(8)).clamp(420, 6000);

    final hourAngle = (now.hour + now.minute / 60) / 24 * 2 * pi;
    final target = 25.5 + 2.2 * sin(hourAngle - pi / 2) - (_actual[DeviceId.mist]! ? 0.6 : 0);
    _temp += (target - _temp) * 0.1 + _noise(0.05);

    if (_actual[DeviceId.mist]!) _water -= 0.004;
    if (_actual[DeviceId.sprinkler]!) _water -= 0.02;
    if (_actual[DeviceId.refill]!) _water += 0.05;
    _water = _water.clamp(0, 1);

    if (_lastHistoryAt == null || now.difference(_lastHistoryAt!) >= const Duration(minutes: 1)) {
      _lastHistoryAt = now;
      final cutoff = now.subtract(const Duration(days: 7));
      _history.value = [
        ..._history.value.where((p) => p.ts.isAfter(cutoff)),
        HistoryPoint(ts: now, temp: _temp, rh: _rh, co2: _co2.round()),
      ];
    }
    _publishLive();
  }

  void _runAutoLogic() {
    final sp = _setpoints.value;
    if (_rh < sp.humOn) _actual[DeviceId.mist] = true;
    if (_rh > sp.humOff) _actual[DeviceId.mist] = false;
    if (_co2 > sp.co2On) _actual[DeviceId.fan] = true;
    if (_co2 < sp.co2Off) _actual[DeviceId.fan] = false;
    _actual[DeviceId.refill] = _lowWater;
  }

  void _enforceSafety() {
    if (_cutoff) {
      _actual[DeviceId.mist] = false;
      _actual[DeviceId.sprinkler] = false;
    }
    if (_water >= 0.98) _actual[DeviceId.refill] = false;
  }

  void _runSchedules(DateTime now) {
    final minuteKey = now.hour * 60 + now.minute;
    if (minuteKey != _lastScheduleMinute) {
      _lastScheduleMinute = minuteKey;
      _firedThisMinute.clear();
    }
    final day = now.weekday % 7; // DateTime: Mon=1..Sun=7 -> Sun=0
    for (final dev in ScheduleDevice.values) {
      final slots = _schedules.value[dev]!;
      for (var i = 0; i < slots.length; i++) {
        final s = slots[i];
        final id = '${dev.key}$i';
        if (s == null || !s.enabled || !s.days[day] || _firedThisMinute.contains(id)) continue;
        if (s.hour == now.hour && s.minute == now.minute) {
          _firedThisMinute.add(id);
          if (dev == ScheduleDevice.sprinkler) {
            _actual[DeviceId.sprinkler] = true;
            _sprinklerStop = now.add(Duration(minutes: s.duration));
          } else {
            _actual[DeviceId.light] = true;
            _lightStop = now.add(Duration(hours: s.duration));
          }
        }
      }
    }
    if (_sprinklerStop != null && !now.isBefore(_sprinklerStop!)) {
      _actual[DeviceId.sprinkler] = false;
      _sprinklerStop = null;
    }
    if (_lightStop != null && !now.isBefore(_lightStop!)) {
      _actual[DeviceId.light] = false;
      _lightStop = null;
    }
  }

  void _publishLive() {
    _live.value = LiveData(
      updatedAt: _clock(),
      temp: double.parse(_temp.toStringAsFixed(1)),
      rh: double.parse(_rh.toStringAsFixed(1)),
      co2: _co2.round(),
      lowWater: _lowWater,
      waterCutoff: _cutoff,
      mode: _mode,
      devices: Map.unmodifiable(_actual),
      rtc: _clock().toIso8601String().substring(0, 19).replaceFirst('T', ' '),
      rssi: -58,
    );
  }

  void _updateHarvest() {
    final open = _batches.value.where((b) => b.isOpen).toList();
    final now = _clock();
    if (open.isEmpty) {
      _harvest.value = HarvestResult(ts: now, label: HarvestLabel.empty, confidence: 0.93);
      return;
    }
    final day = open.first.dayNumber(now);
    _harvest.value = day >= 8
        ? HarvestResult(ts: now, label: HarvestLabel.overMature, confidence: 0.81)
        : day >= 5
            ? HarvestResult(ts: now, label: HarvestLabel.ready, confidence: 0.87)
            : HarvestResult(ts: now, label: HarvestLabel.notReady, confidence: 0.9);
  }

  /// Runs [apply] after [commandDelay], like a command travelling to the ESP32.
  void _deliver(void Function() apply) {
    void run() {
      apply();
      _enforceSafety();
      _publishLive();
    }

    if (commandDelay == Duration.zero) {
      run();
    } else {
      Timer(commandDelay, run);
    }
  }

  @override
  Stream<LiveData> watchLive() => _live.stream;

  @override
  Stream<ControlState> watchControl() => _control.stream;

  @override
  Stream<Setpoints> watchSetpoints() => _setpoints.stream;

  @override
  Stream<ScheduleTable> watchSchedules() => _schedules.stream;

  @override
  Stream<List<HistoryPoint>> watchHistory(Duration range) => _history.stream.map((all) {
        final since = _clock().subtract(range);
        return all.where((p) => p.ts.isAfter(since)).toList();
      });

  @override
  Stream<CameraShot?> watchCamera() => _camera.stream;

  @override
  Stream<HarvestResult?> watchHarvest() => _harvest.stream;

  @override
  Stream<List<Batch>> watchBatches() => _batches.stream;

  @override
  Stream<bool> watchConnection() => Stream.value(true);

  @override
  Future<void> setMode(FarmMode mode) async {
    _control.value = ControlState(mode: mode, devices: _control.value.devices);
    _deliver(() {
      _mode = mode;
      if (mode == FarmMode.auto) _runAutoLogic();
    });
  }

  @override
  Future<void> setDevice(DeviceId device, bool on) async {
    _control.value = ControlState(
      mode: _control.value.mode,
      devices: {..._control.value.devices, device: on},
    );
    _deliver(() {
      // Same rule as the firmware: in auto mode, mist/fan/refill ignore commands.
      if (_mode == FarmMode.auto && device.autoControlled) return;
      _actual[device] = on;
      if (device == DeviceId.sprinkler) _sprinklerStop = null;
      if (device == DeviceId.light) _lightStop = null;
    });
  }

  @override
  Future<void> saveSetpoints(Setpoints sp) async {
    final error = sp.validate();
    if (error != null) throw ArgumentError(error);
    _setpoints.value = sp;
  }

  @override
  Future<void> saveSchedule(ScheduleDevice device, int slot, Schedule? schedule) async {
    RangeError.checkValueInInterval(slot, 0, maxScheduleSlots - 1, 'slot');
    final table = {
      for (final e in _schedules.value.entries) e.key: List<Schedule?>.of(e.value),
    };
    table[device]![slot] = schedule;
    _schedules.value = table;
  }

  @override
  Future<void> startBatch() async {
    _batches.value = [
      Batch(id: 'demo-${_clock().millisecondsSinceEpoch}', pinnedAt: _clock()),
      ..._batches.value,
    ];
    _updateHarvest();
  }

  @override
  Future<void> finishBatch(String batchId, {double? weightG, String notes = ''}) async {
    _batches.value = [
      for (final b in _batches.value)
        b.id == batchId
            ? Batch(
                id: b.id,
                pinnedAt: b.pinnedAt,
                harvestedAt: _clock(),
                weightG: weightG,
                notes: notes,
              )
            : b,
    ];
    _updateHarvest();
  }

  /// Demo helper: drain the reservoir to show the low-water alerts.
  void drainWater() {
    _water = 0.05;
    _enforceSafety();
    _publishLive();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final s in [_live, _control, _setpoints, _schedules, _history, _camera, _harvest, _batches]) {
      s.close();
    }
  }
}

/// A broadcast stream that replays its latest value to each new listener.
class _Subject<T> {
  _Subject(this._value);

  T _value;
  final _ctrl = StreamController<T>.broadcast();

  T get value => _value;

  set value(T v) {
    _value = v;
    if (!_ctrl.isClosed) _ctrl.add(v);
  }

  Stream<T> get stream async* {
    yield _value;
    yield* _ctrl.stream;
  }

  void close() => _ctrl.close();
}
