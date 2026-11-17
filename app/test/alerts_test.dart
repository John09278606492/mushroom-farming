import 'package:flutter_test/flutter_test.dart';
import 'package:mushroom_farm/logic/alerts.dart';
import 'package:mushroom_farm/models/farm_models.dart';

void main() {
  final now = DateTime(2026, 11, 17, 12);
  const sp = Setpoints.fruiting;

  LiveData good({
    double rh = 90,
    int? co2 = 700,
    double temp = 25,
    bool lowWater = false,
    bool? cutoff = false,
    FarmMode mode = FarmMode.auto,
    Duration age = const Duration(seconds: 3),
  }) =>
      LiveData(
        updatedAt: now.subtract(age),
        rh: rh,
        co2: co2,
        temp: temp,
        lowWater: lowWater,
        waterCutoff: cutoff,
        mode: mode,
      );

  test('no alerts when everything is in range', () {
    expect(computeAlerts(good(), sp, now), isEmpty);
  });

  test('no data yet is critical', () {
    final a = computeAlerts(LiveData.empty, sp, now);
    expect(a.single.severity, Severity.critical);
  });

  test('offline controller is reported first', () {
    final a = computeAlerts(good(age: const Duration(minutes: 2), rh: 60), sp, now);
    expect(a.first.title, 'Controller offline');
    expect(a.map((x) => x.title), contains('Humidity is low'));
  });

  test('small humidity dip below mist-on is not an alert', () {
    expect(computeAlerts(good(rh: 82), sp, now), isEmpty);
    expect(humidityStatus(82, sp), Severity.info);
    expect(computeAlerts(good(rh: 78), sp, now).single.title, 'Humidity is low');
  });

  test('water cutoff beats low water', () {
    final a = computeAlerts(good(lowWater: true, cutoff: true), sp, now);
    expect(a.single.severity, Severity.critical);
    expect(a.single.title, contains('pumps stopped'));
  });

  test('co2 and temperature limits', () {
    expect(computeAlerts(good(co2: 1100), sp, now).single.title, 'CO2 is high');
    expect(computeAlerts(good(co2: null), sp, now).single.title, contains('sensor'));
    expect(computeAlerts(good(temp: 31), sp, now).single.title, 'Too hot');
    expect(computeAlerts(good(temp: 19), sp, now).single.title, 'Too cold');
  });

  group('deviceLockReason', () {
    test('auto mode locks mist, fan and refill only', () {
      final live = good();
      expect(deviceLockReason(DeviceId.mist, live, now), isNotNull);
      expect(deviceLockReason(DeviceId.fan, live, now), isNotNull);
      expect(deviceLockReason(DeviceId.refill, live, now), isNotNull);
      expect(deviceLockReason(DeviceId.sprinkler, live, now), isNull);
      expect(deviceLockReason(DeviceId.light, live, now), isNull);
    });

    test('manual mode unlocks everything', () {
      final live = good(mode: FarmMode.manual);
      for (final d in DeviceId.values) {
        expect(deviceLockReason(d, live, now), isNull, reason: d.name);
      }
    });

    test('offline locks everything; cutoff blocks the pumps', () {
      final off = good(mode: FarmMode.manual, age: const Duration(minutes: 1));
      for (final d in DeviceId.values) {
        expect(deviceLockReason(d, off, now), 'Controller offline');
      }
      final dry = good(mode: FarmMode.manual, cutoff: true);
      expect(deviceLockReason(DeviceId.sprinkler, dry, now), contains('water'));
      expect(deviceLockReason(DeviceId.mist, dry, now), contains('water'));
      expect(deviceLockReason(DeviceId.refill, dry, now), isNull);
    });
  });
}
