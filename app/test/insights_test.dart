import 'package:flutter_test/flutter_test.dart';
import 'package:mushroom_farm/logic/alerts.dart';
import 'package:mushroom_farm/logic/insights.dart';
import 'package:mushroom_farm/models/farm_models.dart';

void main() {
  final now = DateTime(2026, 11, 19, 9);
  const sp = Setpoints.fruiting;

  LiveData live({
    double rh = 90,
    int? co2 = 700,
    double temp = 25,
    bool lowWater = false,
    bool cutoff = false,
    FarmMode mode = FarmMode.auto,
    Map<DeviceId, bool> devices = const {},
    Duration age = const Duration(seconds: 2),
  }) =>
      LiveData(
        updatedAt: now.subtract(age),
        rh: rh,
        co2: co2,
        temp: temp,
        lowWater: lowWater,
        waterCutoff: cutoff,
        mode: mode,
        devices: devices,
      );

  test('perfect conditions score 100 with an all-good tip', () {
    final i = computeInsight(live(), sp, now);
    expect(i.score, 100);
    expect(i.mood, Severity.ok);
    expect(i.headline, contains('ideal for fruiting'));
    expect(i.tips, ['All readings are inside your targets.']);
  });

  test('no data and offline have no score', () {
    expect(computeInsight(LiveData.empty, sp, now).score, isNull);
    final off = computeInsight(live(age: const Duration(minutes: 5)), sp, now);
    expect(off.score, isNull);
    expect(off.mood, Severity.critical);
  });

  test('low humidity with mist running explains what is happening', () {
    final i = computeInsight(live(rh: 80, devices: {DeviceId.mist: true}), sp, now);
    expect(i.score, 85);
    expect(i.tips.first, contains('mist maker is raising it'));
  });

  test('several problems lower the score and are capped at 3 tips', () {
    final i = computeInsight(
      live(rh: 70, co2: 1500, temp: 32, cutoff: true, mode: FarmMode.manual),
      sp,
      now,
      openBatch: Batch(id: 'b', pinnedAt: now.subtract(const Duration(days: 6))),
    );
    expect(i.score, lessThan(60));
    expect(i.mood, Severity.critical);
    expect(i.tips.length, maxInsightTips);
    expect(i.tips.first, contains('water tank is empty'));
  });

  test('batch day appears in tips', () {
    final i = computeInsight(live(), sp, now,
        openBatch: Batch(id: 'b', pinnedAt: now.subtract(const Duration(days: 5, hours: 1))));
    expect(i.tips.single, contains('day 6'));
    expect(i.tips.single, contains('harvest window'));
  });
}
