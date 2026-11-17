// Data models that mirror docs/firebase-schema.md.
//
// Firebase Realtime Database returns loosely typed maps (and turns maps with
// integer keys into lists), so every fromMap() here is defensive.

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

/// Every actuator the ESP32 controller drives.
enum DeviceId { mist, fan, refill, sprinkler, light }

extension DeviceIdInfo on DeviceId {
  /// Key used in Firebase (`live/devices/<key>`, `control/devices/<key>`).
  String get key => name;

  String get label => switch (this) {
        DeviceId.mist => 'Mist maker',
        DeviceId.fan => 'Exhaust fan',
        DeviceId.refill => 'Refill pump',
        DeviceId.sprinkler => 'Sprinkler pump',
        DeviceId.light => 'Grow light',
      };

  String get description => switch (this) {
        DeviceId.mist => 'Raises humidity',
        DeviceId.fan => 'Removes CO2, brings fresh air',
        DeviceId.refill => 'Fills the water reservoir',
        DeviceId.sprinkler => 'High-pressure misting',
        DeviceId.light => 'Light for fruiting',
      };

  IconData get icon => switch (this) {
        DeviceId.mist => Icons.water_drop_outlined,
        DeviceId.fan => Icons.air,
        DeviceId.refill => Icons.water,
        DeviceId.sprinkler => Icons.shower_outlined,
        DeviceId.light => Icons.lightbulb_outline,
      };

  /// In auto mode the controller decides these itself from the thresholds,
  /// so manual commands for them are ignored (see firebase-schema.md).
  bool get autoControlled =>
      this == DeviceId.mist || this == DeviceId.fan || this == DeviceId.refill;
}

enum FarmMode { auto, manual }

FarmMode parseMode(Object? v) => v == 'manual' ? FarmMode.manual : FarmMode.auto;

double? _toDouble(Object? v) => v is num ? v.toDouble() : null;
int? _toInt(Object? v) => v is num ? v.toInt() : null;
bool _toBool(Object? v) => v == true || v == 1;

DateTime? _toTime(Object? v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

Map<Object?, Object?> _asMap(Object? v) {
  if (v is Map) return v.cast<Object?, Object?>();
  if (v is List) {
    return {for (var i = 0; i < v.length; i++) if (v[i] != null) '$i': v[i]};
  }
  return const {};
}

Map<DeviceId, bool> _parseDevices(Object? v) {
  final m = _asMap(v);
  return {for (final d in DeviceId.values) d: _toBool(m[d.key])};
}

/// `farm1/live`: what the controller reports right now.
class LiveData {
  const LiveData({
    this.updatedAt,
    this.temp,
    this.rh,
    this.co2,
    this.lowWater = false,
    this.waterCutoff,
    this.mode = FarmMode.auto,
    this.devices = const {},
    this.rtc,
    this.rssi,
  });

  final DateTime? updatedAt;
  final double? temp;
  final double? rh;

  /// ppm; null when the sensor has no reading (firmware sends -1).
  final int? co2;
  final bool lowWater;

  /// Null when the 2nd (cutoff) float switch is not installed.
  final bool? waterCutoff;
  final FarmMode mode;
  final Map<DeviceId, bool> devices;
  final String? rtc;
  final int? rssi;

  static const empty = LiveData();

  /// The controller writes every 5 s; older than this means it is offline.
  static const staleAfter = Duration(seconds: 30);

  bool get hasData => updatedAt != null;

  bool isOnline(DateTime now) =>
      updatedAt != null && now.difference(updatedAt!) < staleAfter;

  bool deviceOn(DeviceId d) => devices[d] ?? false;

  factory LiveData.fromMap(Object? raw) {
    final m = _asMap(raw);
    if (m.isEmpty) return empty;
    final co2 = _toInt(m['co2']);
    return LiveData(
      updatedAt: _toTime(m['updatedAt']),
      temp: _toDouble(m['temp']),
      rh: _toDouble(m['rh']),
      co2: (co2 == null || co2 < 0) ? null : co2,
      lowWater: _toBool(m['lowWater']),
      waterCutoff: m.containsKey('waterCutoff') ? _toBool(m['waterCutoff']) : null,
      mode: parseMode(m['mode']),
      devices: _parseDevices(m['devices']),
      rtc: m['rtc'] as String?,
      rssi: _toInt(m['rssi']),
    );
  }
}

/// `farm1/control`: what the app asked for.
class ControlState {
  const ControlState({this.mode, this.devices = const {}});

  /// Null when the app has never written a mode.
  final FarmMode? mode;
  final Map<DeviceId, bool?> devices;

  static const empty = ControlState();

  factory ControlState.fromMap(Object? raw) {
    final m = _asMap(raw);
    final dm = _asMap(m['devices']);
    return ControlState(
      mode: m['mode'] == null ? null : parseMode(m['mode']),
      devices: {
        for (final d in DeviceId.values)
          if (dm[d.key] != null) d: _toBool(dm[d.key]),
      },
    );
  }
}

enum GrowthStage { spawnRun, fruiting }

extension GrowthStageInfo on GrowthStage {
  String get key => this == GrowthStage.spawnRun ? 'spawn_run' : 'fruiting';
  String get label => this == GrowthStage.spawnRun ? 'Spawn run' : 'Fruiting';
  String get summary => this == GrowthStage.spawnRun
      ? 'Dark, 70–80% RH, CO2 can stay high'
      : 'Light 12 h/day, 85–95% RH, CO2 below 800 ppm';
}

/// `farm1/setpoints`.
class Setpoints {
  const Setpoints({
    required this.humOn,
    required this.humOff,
    required this.co2On,
    required this.co2Off,
    required this.tempMin,
    required this.tempMax,
    this.stage = GrowthStage.fruiting,
  });

  /// Mist ON below this % RH.
  final double humOn;

  /// Mist OFF above this % RH.
  final double humOff;

  /// Fan ON above this ppm.
  final int co2On;

  /// Fan OFF below this ppm.
  final int co2Off;

  /// Alert limits only; the controller has no heater or cooler.
  final double tempMin;
  final double tempMax;
  final GrowthStage stage;

  /// Oyster mushroom presets from handoff.md section 5.
  static const fruiting = Setpoints(
    humOn: 85, humOff: 95, co2On: 800, co2Off: 700,
    tempMin: 22, tempMax: 28, stage: GrowthStage.fruiting,
  );
  static const spawnRun = Setpoints(
    humOn: 70, humOff: 80, co2On: 5000, co2Off: 4000,
    tempMin: 24, tempMax: 28, stage: GrowthStage.spawnRun,
  );

  static Setpoints preset(GrowthStage s) =>
      s == GrowthStage.spawnRun ? spawnRun : fruiting;

  /// Returns an error message, or null if the values are usable.
  String? validate() {
    if (humOn >= humOff) {
      return 'Mist ON humidity must be lower than mist OFF humidity.';
    }
    if (co2Off >= co2On) {
      return 'Fan OFF CO2 must be lower than fan ON CO2.';
    }
    if (tempMin >= tempMax) {
      return 'Minimum temperature must be lower than maximum temperature.';
    }
    return null;
  }

  Setpoints copyWith({
    double? humOn,
    double? humOff,
    int? co2On,
    int? co2Off,
    double? tempMin,
    double? tempMax,
    GrowthStage? stage,
  }) =>
      Setpoints(
        humOn: humOn ?? this.humOn,
        humOff: humOff ?? this.humOff,
        co2On: co2On ?? this.co2On,
        co2Off: co2Off ?? this.co2Off,
        tempMin: tempMin ?? this.tempMin,
        tempMax: tempMax ?? this.tempMax,
        stage: stage ?? this.stage,
      );

  Map<String, Object> toMap() => {
        'humOn': humOn,
        'humOff': humOff,
        'co2On': co2On,
        'co2Off': co2Off,
        'tempMin': tempMin,
        'tempMax': tempMax,
        'stage': stage.key,
      };

  factory Setpoints.fromMap(Object? raw) {
    final m = _asMap(raw);
    const d = fruiting;
    return Setpoints(
      humOn: _toDouble(m['humOn']) ?? d.humOn,
      humOff: _toDouble(m['humOff']) ?? d.humOff,
      co2On: _toInt(m['co2On']) ?? d.co2On,
      co2Off: _toInt(m['co2Off']) ?? d.co2Off,
      tempMin: _toDouble(m['tempMin']) ?? d.tempMin,
      tempMax: _toDouble(m['tempMax']) ?? d.tempMax,
      stage: m['stage'] == 'spawn_run' ? GrowthStage.spawnRun : GrowthStage.fruiting,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Setpoints &&
      other.humOn == humOn &&
      other.humOff == humOff &&
      other.co2On == co2On &&
      other.co2Off == co2Off &&
      other.tempMin == tempMin &&
      other.tempMax == tempMax &&
      other.stage == stage;

  @override
  int get hashCode =>
      Object.hash(humOn, humOff, co2On, co2Off, tempMin, tempMax, stage);
}

/// Devices that have time schedules on the controller.
enum ScheduleDevice { sprinkler, light }

extension ScheduleDeviceInfo on ScheduleDevice {
  String get key => name;
  String get label => this == ScheduleDevice.sprinkler ? 'Sprinkler pump' : 'Grow light';
  IconData get icon =>
      this == ScheduleDevice.sprinkler ? Icons.shower_outlined : Icons.lightbulb_outline;

  /// Firebase field name: sprinkler runs for minutes, the light for hours.
  String get durationKey => this == ScheduleDevice.sprinkler ? 'durationMin' : 'durationHr';
  String get unit => this == ScheduleDevice.sprinkler ? 'min' : 'h';
  int get maxDuration => this == ScheduleDevice.sprinkler ? 120 : 24;
  int get defaultDuration => this == ScheduleDevice.sprinkler ? 3 : 12;
}

const maxScheduleSlots = 5;
const dayShortNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// One schedule slot (`farm1/schedules/<device>/<slot>`).
class Schedule {
  const Schedule({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.duration,
    required this.days,
  });

  final bool enabled;
  final int hour;
  final int minute;

  /// Minutes for the sprinkler, hours for the light.
  final int duration;

  /// 7 entries, index 0 = Sunday.
  final List<bool> days;

  factory Schedule.newFor(ScheduleDevice d) => Schedule(
        enabled: true,
        hour: 6,
        minute: 0,
        duration: d.defaultDuration,
        days: List.filled(7, true),
      );

  Schedule copyWith({bool? enabled, int? hour, int? minute, int? duration, List<bool>? days}) =>
      Schedule(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        duration: duration ?? this.duration,
        days: days ?? this.days,
      );

  Map<String, Object> toMap(ScheduleDevice d) => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        d.durationKey: duration,
        'days': days,
      };

  static Schedule? fromMap(Object? raw, ScheduleDevice d) {
    final m = _asMap(raw);
    if (m.isEmpty) return null;
    final rawDays = m['days'];
    final days = List<bool>.filled(7, false);
    if (rawDays is List) {
      for (var i = 0; i < 7 && i < rawDays.length; i++) {
        days[i] = _toBool(rawDays[i]);
      }
    } else if (rawDays is Map) {
      for (var i = 0; i < 7; i++) {
        days[i] = _toBool(rawDays['$i']);
      }
    }
    return Schedule(
      enabled: _toBool(m['enabled']),
      hour: (_toInt(m['hour']) ?? 0).clamp(0, 23),
      minute: (_toInt(m['minute']) ?? 0).clamp(0, 59),
      duration: (_toInt(m[d.durationKey]) ?? d.defaultDuration).clamp(1, d.maxDuration),
      days: days,
    );
  }

  /// "Every day", "Mon–Fri" or a list like "Mon, Wed, Fri".
  String get daysLabel {
    if (days.every((d) => d)) return 'Every day';
    if (!days.contains(true)) return 'No days';
    final weekdays = [false, true, true, true, true, true, false];
    if (List.generate(7, (i) => days[i] == weekdays[i]).every((x) => x)) {
      return 'Mon–Fri';
    }
    return [for (var i = 0; i < 7; i++) if (days[i]) dayShortNames[i]].join(', ');
  }

  @override
  bool operator ==(Object other) =>
      other is Schedule &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute &&
      other.duration == duration &&
      List.generate(7, (i) => other.days[i] == days[i]).every((x) => x);

  @override
  int get hashCode => Object.hash(enabled, hour, minute, duration, Object.hashAll(days));
}

/// Slots 0..4 per device; null = empty slot.
typedef ScheduleTable = Map<ScheduleDevice, List<Schedule?>>;

ScheduleTable emptyScheduleTable() => {
      for (final d in ScheduleDevice.values) d: List<Schedule?>.filled(maxScheduleSlots, null),
    };

ScheduleTable parseSchedules(Object? raw) {
  final m = _asMap(raw);
  final table = emptyScheduleTable();
  for (final d in ScheduleDevice.values) {
    final slots = _asMap(m[d.key]);
    for (var i = 0; i < maxScheduleSlots; i++) {
      table[d]![i] = Schedule.fromMap(slots['$i'], d);
    }
  }
  return table;
}

/// One reading in `farm1/history`.
class HistoryPoint {
  const HistoryPoint({required this.ts, this.temp, this.rh, this.co2});

  final DateTime ts;
  final double? temp;
  final double? rh;
  final int? co2;

  static HistoryPoint? fromMap(Object? raw) {
    final m = _asMap(raw);
    final ts = _toTime(m['ts']);
    if (ts == null) return null;
    final co2 = _toInt(m['co2']);
    return HistoryPoint(
      ts: ts,
      temp: _toDouble(m['temp']),
      rh: _toDouble(m['rh']),
      co2: (co2 == null || co2 < 0) ? null : co2,
    );
  }
}

/// `farm1/camera/latest`.
class CameraShot {
  const CameraShot({required this.ts, required this.jpeg});
  final DateTime ts;
  final Uint8List jpeg;
}

enum HarvestLabel { empty, notReady, ready, overMature }

extension HarvestLabelInfo on HarvestLabel {
  String get label => switch (this) {
        HarvestLabel.empty => 'No mushrooms yet',
        HarvestLabel.notReady => 'Not ready',
        HarvestLabel.ready => 'Ready to harvest',
        HarvestLabel.overMature => 'Over-mature: harvest now',
      };
}

HarvestLabel? parseHarvestLabel(Object? v) => switch (v) {
      'empty' => HarvestLabel.empty,
      'not_ready' => HarvestLabel.notReady,
      'ready' => HarvestLabel.ready,
      'over_mature' => HarvestLabel.overMature,
      _ => null,
    };

/// `farm1/harvest/latest`.
class HarvestResult {
  const HarvestResult({required this.ts, required this.label, required this.confidence});
  final DateTime ts;
  final HarvestLabel label;
  final double confidence;

  static HarvestResult? fromMap(Object? raw) {
    final m = _asMap(raw);
    final ts = _toTime(m['ts']);
    final label = parseHarvestLabel(m['label']);
    if (ts == null || label == null) return null;
    return HarvestResult(ts: ts, label: label, confidence: _toDouble(m['confidence']) ?? 0);
  }
}

/// `farm1/batches/<id>`: one flush, from pinning to harvest.
class Batch {
  const Batch({
    required this.id,
    required this.pinnedAt,
    this.harvestedAt,
    this.weightG,
    this.notes = '',
  });

  final String id;
  final DateTime pinnedAt;
  final DateTime? harvestedAt;
  final double? weightG;
  final String notes;

  bool get isOpen => harvestedAt == null;

  /// Day 1 is the day pinning started.
  int dayNumber(DateTime now) => now.difference(pinnedAt).inDays + 1;

  static Batch? fromMap(String id, Object? raw) {
    final m = _asMap(raw);
    final pinned = _toTime(m['pinnedAt']);
    if (pinned == null) return null;
    return Batch(
      id: id,
      pinnedAt: pinned,
      harvestedAt: _toTime(m['harvestedAt']),
      weightG: _toDouble(m['weightG']),
      notes: (m['notes'] as String?) ?? '',
    );
  }
}
