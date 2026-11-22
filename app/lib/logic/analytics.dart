// Numbers for the Analytics tab, computed from saved readings and batches.
// Pure Dart so it is unit-tested.

import 'dart:math';

import '../models/farm_models.dart';

/// One reading type (humidity, temperature, CO2) and its target band.
class Metric {
  const Metric({
    required this.name,
    required this.unit,
    required this.decimals,
    required this.value,
    this.low,
    this.high,
  });

  final String name;
  final String unit;
  final int decimals;
  final double? Function(HistoryPoint) value;

  /// Below this is "low"; null means there is no lower limit (CO2).
  final double? low;

  /// Above this is "high".
  final double? high;

  /// -1 low, 0 in range, 1 high.
  int zone(double v) {
    if (low != null && v < low!) return -1;
    if (high != null && v > high!) return 1;
    return 0;
  }

  String fmt(double v) => v.toStringAsFixed(decimals);

  static List<Metric> all(Setpoints sp) => [
        Metric(name: 'Humidity', unit: '%', decimals: 0, value: (p) => p.rh, low: sp.humOn, high: sp.humOff),
        Metric(
            name: 'Temperature', unit: '°C', decimals: 1, value: (p) => p.temp, low: sp.tempMin, high: sp.tempMax),
        Metric(name: 'CO2', unit: 'ppm', decimals: 0, value: (p) => p.co2?.toDouble(), high: sp.co2On.toDouble()),
      ];
}

/// Readings further apart than this are a gap (controller was off), not one
/// long stretch.
const maxReadingGap = Duration(minutes: 30);

class MetricStats {
  const MetricStats({
    required this.count,
    required this.min,
    required this.max,
    required this.avg,
    required this.spread,
    required this.lowShare,
    required this.inShare,
    required this.highShare,
    required this.excursions,
    required this.longestExcursion,
  });

  final int count;
  final double min;
  final double max;
  final double avg;

  /// Standard deviation: how much the reading swings.
  final double spread;

  /// Shares of readings (0..1) below, inside and above the target band.
  final double lowShare;
  final double inShare;
  final double highShare;

  /// How many times the reading left the target band.
  final int excursions;
  final Duration longestExcursion;
}

MetricStats? metricStats(List<HistoryPoint> pts, Metric m) {
  final vals = <(DateTime, double)>[
    for (final p in pts)
      if (m.value(p) case final v?) (p.ts, v),
  ];
  if (vals.isEmpty) return null;

  var lo = double.infinity, hi = -double.infinity, sum = 0.0;
  var nLow = 0, nHigh = 0;
  for (final (_, v) in vals) {
    lo = min(lo, v);
    hi = max(hi, v);
    sum += v;
    final z = m.zone(v);
    if (z < 0) nLow++;
    if (z > 0) nHigh++;
  }
  final avg = sum / vals.length;
  var sq = 0.0;
  for (final (_, v) in vals) {
    sq += (v - avg) * (v - avg);
  }

  // Excursions: runs of out-of-range readings.
  var excursions = 0;
  var longest = Duration.zero;
  DateTime? start;
  DateTime? prevTs;
  void close(DateTime end) {
    final d = end.difference(start!);
    if (d > longest) longest = d;
    start = null;
  }

  for (final (ts, v) in vals) {
    final out = m.zone(v) != 0;
    if (start != null && prevTs != null && ts.difference(prevTs) > maxReadingGap) close(prevTs);
    if (out && start == null) {
      start = ts;
      excursions++;
    } else if (!out && start != null) {
      close(ts);
    }
    prevTs = ts;
  }
  if (start != null) close(prevTs!);

  final n = vals.length;
  return MetricStats(
    count: n,
    min: lo,
    max: hi,
    avg: avg,
    spread: sqrt(sq / n),
    lowShare: nLow / n,
    inShare: (n - nLow - nHigh) / n,
    highShare: nHigh / n,
    excursions: excursions,
    longestExcursion: longest,
  );
}

/// Share of readings (0..1) where every reading that exists is on target.
/// Null when there are no readings.
double? idealShare(List<HistoryPoint> pts, List<Metric> metrics) {
  var n = 0, good = 0;
  for (final p in pts) {
    var any = false, ok = true;
    for (final m in metrics) {
      final v = m.value(p);
      if (v == null) continue;
      any = true;
      if (m.zone(v) != 0) ok = false;
    }
    if (!any) continue;
    n++;
    if (ok) good++;
  }
  return n == 0 ? null : good / n;
}

/// Average per hour of the day (index 0 = midnight). Null where no data.
List<double?> hourlyAverages(List<HistoryPoint> pts, Metric m) {
  final sums = List<double>.filled(24, 0);
  final counts = List<int>.filled(24, 0);
  for (final p in pts) {
    final v = m.value(p);
    if (v == null) continue;
    final h = p.ts.toLocal().hour;
    sums[h] += v;
    counts[h]++;
  }
  return [for (var h = 0; h < 24; h++) counts[h] == 0 ? null : sums[h] / counts[h]];
}

/// The hour whose average is furthest outside the band (or closest to its
/// edge), so the screen can say "Humidity dips most around 3 PM".
({int hour, double value})? worstHour(List<double?> hourly, Metric m) {
  ({int hour, double value})? best;
  var bestScore = -double.infinity;
  for (var h = 0; h < 24; h++) {
    final v = hourly[h];
    if (v == null) continue;
    // How far past (positive) or inside (negative) the nearest limit.
    final belowLow = m.low == null ? -double.infinity : m.low! - v;
    final aboveHigh = m.high == null ? -double.infinity : v - m.high!;
    final score = max(belowLow, aboveHigh);
    if (score > bestScore) {
      bestScore = score;
      best = (hour: h, value: v);
    }
  }
  return best;
}

class HarvestStats {
  const HarvestStats({
    required this.harvested,
    required this.totalG,
    required this.avgG,
    required this.avgDays,
    required this.recent,
  });

  final int harvested;
  final double totalG;
  final double? avgG;

  /// Average days from pinning to harvest.
  final double? avgDays;

  /// Up to 8 harvested batches with a weight, oldest first.
  final List<Batch> recent;
}

HarvestStats harvestStats(List<Batch> batches) {
  final done = batches.where((b) => !b.isOpen).toList()
    ..sort((a, b) => a.harvestedAt!.compareTo(b.harvestedAt!));
  final weighed = done.where((b) => b.weightG != null).toList();
  final total = weighed.fold<double>(0, (s, b) => s + b.weightG!);
  final days = [for (final b in done) b.harvestedAt!.difference(b.pinnedAt).inHours / 24];
  return HarvestStats(
    harvested: done.length,
    totalG: total,
    avgG: weighed.isEmpty ? null : total / weighed.length,
    avgDays: days.isEmpty ? null : days.reduce((a, b) => a + b) / days.length,
    recent: weighed.length > 8 ? weighed.sublist(weighed.length - 8) : weighed,
  );
}

/// Plain-language takeaways, most useful first (at most three).
List<String> findings(List<HistoryPoint> pts, List<Metric> metrics) {
  final out = <(double, String)>[];
  for (final m in metrics) {
    final s = metricStats(pts, m);
    if (s == null) continue;
    final w = worstHour(hourlyAverages(pts, m), m);
    final at = w == null ? '' : ', mostly around ${_hourLabel(w.hour)}';
    if (s.lowShare >= 0.1) {
      out.add((
        s.lowShare,
        '${m.name} was below target ${_pct(s.lowShare)} of the time$at.'
            '${m.name == 'Humidity' ? ' A sprinkler schedule an hour before could help.' : ''}'
      ));
    }
    if (s.highShare >= 0.1) {
      out.add((
        s.highShare,
        '${m.name} was above target ${_pct(s.highShare)} of the time$at.'
            '${m.name == 'CO2' ? ' Check the exhaust fan and fresh-air gaps.' : ''}'
            '${m.name == 'Temperature' ? ' Add shade or airflow at that time.' : ''}'
      ));
    }
  }
  out.sort((a, b) => b.$1.compareTo(a.$1));
  final list = [for (final f in out.take(3)) f.$2];
  if (list.isEmpty && pts.isNotEmpty) {
    list.add('All readings stayed close to target. Keep the current settings.');
  }
  return list;
}

String _pct(double f) => '${(f * 100).round()}%';

String _hourLabel(int h) {
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12 ${h < 12 ? 'AM' : 'PM'}';
}
