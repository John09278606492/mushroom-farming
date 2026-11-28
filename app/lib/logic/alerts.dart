// Pure functions that turn the latest readings into user-facing alerts and
// per-reading status colors. No Flutter widgets here, so it is unit-tested.

import '../models/farm_models.dart';

enum Severity { ok, info, warning, critical }

class FarmAlert {
  const FarmAlert(this.severity, this.title, this.message);
  final Severity severity;
  final String title;
  final String message;

  @override
  String toString() => '$severity: $title';
}

/// How far humidity may drop below the mist-ON threshold before we warn.
/// Small dips are normal: the mist maker is already running then.
const humidityWarnMargin = 5.0;

/// How far CO2 may rise above the fan-ON threshold before we warn.
const co2WarnMargin = 200;

List<FarmAlert> computeAlerts(LiveData live, Setpoints sp, DateTime now) {
  if (!live.hasData) {
    return const [
      FarmAlert(Severity.critical, 'No data from the controller yet',
          'Check that the ESP32 is powered and connected to the pocket WiFi.'),
    ];
  }

  final alerts = <FarmAlert>[];

  if (!live.isOnline(now)) {
    alerts.add(const FarmAlert(Severity.critical, 'Controller offline',
        'No update for over a minute. The farm keeps running on its own, '
            'but readings below are old and controls are paused.'));
  }

  if (live.waterCutoff == true) {
    alerts.add(const FarmAlert(Severity.critical, 'Water too low: pumps stopped',
        'The low-level float switch tripped. Refill the reservoir.'));
  } else if (live.lowWater) {
    alerts.add(FarmAlert(
        Severity.warning,
        'Reservoir water is low',
        live.deviceOn(DeviceId.refill)
            ? 'The refill pump is running.'
            : 'Refill the reservoir or turn on the refill pump.'));
  }

  final rh = live.rh;
  if (rh == null) {
    alerts.add(const FarmAlert(Severity.warning, 'Humidity sensor not reading',
        'Check the temperature/humidity sensor wiring.'));
  } else if (rh < sp.humOn - humidityWarnMargin) {
    alerts.add(FarmAlert(Severity.warning, 'Humidity is low',
        '${rh.toStringAsFixed(0)}% (target ${sp.humOn.toStringAsFixed(0)}–${sp.humOff.toStringAsFixed(0)}%).'));
  }

  final co2 = live.co2;
  if (co2 == null) {
    alerts.add(const FarmAlert(Severity.warning, 'CO2 sensor not reading',
        'Check the CO2 sensor wiring.'));
  } else if (co2 > sp.co2On + co2WarnMargin) {
    alerts.add(FarmAlert(Severity.warning, 'CO2 is high',
        '$co2 ppm (fan turns on above ${sp.co2On} ppm).'));
  }

  final t = live.temp;
  if (t != null && t > sp.tempMax) {
    alerts.add(FarmAlert(Severity.warning, 'Too hot',
        '${t.toStringAsFixed(1)} °C (max ${sp.tempMax.toStringAsFixed(0)} °C). Add shade or airflow.'));
  } else if (t != null && t < sp.tempMin) {
    alerts.add(FarmAlert(Severity.warning, 'Too cold',
        '${t.toStringAsFixed(1)} °C (min ${sp.tempMin.toStringAsFixed(0)} °C).'));
  }

  alerts.sort((a, b) => b.severity.index.compareTo(a.severity.index));
  return alerts;
}

Severity humidityStatus(double? rh, Setpoints sp) {
  if (rh == null) return Severity.warning;
  if (rh < sp.humOn - humidityWarnMargin) return Severity.warning;
  if (rh < sp.humOn || rh > sp.humOff) return Severity.info;
  return Severity.ok;
}

Severity co2Status(int? co2, Setpoints sp) {
  if (co2 == null) return Severity.warning;
  if (co2 > sp.co2On + co2WarnMargin) return Severity.warning;
  if (co2 > sp.co2On) return Severity.info;
  return Severity.ok;
}

Severity tempStatus(double? t, Setpoints sp) {
  if (t == null) return Severity.warning;
  if (t > sp.tempMax || t < sp.tempMin) return Severity.warning;
  return Severity.ok;
}

Severity waterStatus(LiveData live) {
  if (live.waterCutoff == true) return Severity.critical;
  if (live.lowWater) return Severity.warning;
  return Severity.ok;
}

/// Whether the app may send a manual command for [d] right now.
/// Returns null if allowed, or the reason it is not.
String? deviceLockReason(DeviceId d, LiveData live, DateTime now) {
  if (!live.isOnline(now)) return 'Controller offline';
  if (live.mode == FarmMode.auto && d.autoControlled) return 'Controlled by Auto mode';
  if (live.waterCutoff == true && (d == DeviceId.mist || d == DeviceId.sprinkler)) {
    return 'Blocked: water too low';
  }
  return null;
}
