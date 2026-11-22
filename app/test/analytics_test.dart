import 'package:flutter_test/flutter_test.dart';
import 'package:mushroom_farm/logic/analytics.dart';
import 'package:mushroom_farm/models/farm_models.dart';

void main() {
  const sp = Setpoints.fruiting; // humidity 85-95, CO2 under 800
  final t0 = DateTime(2026, 11, 22, 0);
  final hum = Metric.all(sp)[0];

  List<HistoryPoint> series(List<double> rh, {Duration step = const Duration(minutes: 10)}) => [
        for (var i = 0; i < rh.length; i++) HistoryPoint(ts: t0.add(step * i), rh: rh[i], temp: 25, co2: 700),
      ];

  test('shares, min/max/avg and excursions', () {
    final s = metricStats(series([90, 80, 82, 90, 96, 90]), hum)!;
    expect(s.min, 80);
    expect(s.max, 96);
    expect(s.avg, closeTo(88, 0.01));
    expect(s.lowShare, closeTo(2 / 6, 1e-9));
    expect(s.highShare, closeTo(1 / 6, 1e-9));
    expect(s.inShare, closeTo(3 / 6, 1e-9));
    expect(s.excursions, 2);
    expect(s.longestExcursion, const Duration(minutes: 20));
  });

  test('a long gap ends an excursion', () {
    final pts = [
      HistoryPoint(ts: t0, rh: 80),
      HistoryPoint(ts: t0.add(const Duration(hours: 5)), rh: 80),
    ];
    final s = metricStats(pts, hum)!;
    expect(s.longestExcursion, Duration.zero);
  });

  test('no readings gives null', () {
    expect(metricStats(const [], hum), isNull);
    expect(idealShare(const [], Metric.all(sp)), isNull);
  });

  test('ideal share needs every reading on target', () {
    final pts = [
      HistoryPoint(ts: t0, rh: 90, temp: 25, co2: 700),
      HistoryPoint(ts: t0, rh: 90, temp: 25, co2: 1200),
    ];
    expect(idealShare(pts, Metric.all(sp)), 0.5);
  });

  test('hourly pattern finds the worst hour', () {
    final pts = [
      for (var h = 0; h < 24; h++) HistoryPoint(ts: t0.add(Duration(hours: h)), rh: h == 15 ? 78 : 90),
    ];
    final hourly = hourlyAverages(pts, hum);
    expect(worstHour(hourly, hum)!.hour, 15);
    expect(findings(pts, Metric.all(sp)), isNotEmpty);
  });

  test('harvest stats', () {
    final h = harvestStats([
      Batch(id: 'a', pinnedAt: t0, harvestedAt: t0.add(const Duration(days: 6)), weightG: 1000),
      Batch(id: 'b', pinnedAt: t0, harvestedAt: t0.add(const Duration(days: 8)), weightG: 1500),
      Batch(id: 'c', pinnedAt: t0),
    ]);
    expect(h.harvested, 2);
    expect(h.totalG, 2500);
    expect(h.avgG, 1250);
    expect(h.avgDays, 7);
  });
}
