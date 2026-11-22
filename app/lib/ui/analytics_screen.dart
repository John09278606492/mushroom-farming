import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/analytics.dart';
import '../models/farm_models.dart';
import '../state/farm_state.dart';
import 'theme.dart';
import 'widgets/motion.dart';
import 'widgets/status_chip.dart';

enum _Range {
  day('24 h', Duration(hours: 24)),
  week('7 days', Duration(days: 7));

  const _Range(this.label, this.duration);
  final String label;
  final Duration duration;
}

const _lowColor = AppColors.slate;
const _inColor = AppColors.leaf;
const _highColor = AppColors.mustard;

Color _zoneColor(int z) => z < 0 ? _lowColor : (z > 0 ? _highColor : _inColor);

String _hour(int h) {
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12 ${h < 12 ? 'AM' : 'PM'}';
}

String _duration(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final h = d.inMinutes / 60;
  return '${h.toStringAsFixed(h < 10 ? 1 : 0)} h';
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  _Range _range = _Range.day;
  Stream<List<HistoryPoint>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _makeStream();
  }

  // Twice the range: the older half is the "previous period" to compare with.
  Stream<List<HistoryPoint>> _makeStream() =>
      context.read<FarmState>().repo.watchHistory(_range.duration * 2);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final metrics = Metric.all(s.setpoints);
    return AppScaffold(
      appBar: AppBar(title: const PageTitle('Analytics'), actions: const [ConnectionChip()]),
      body: StreamBuilder<List<HistoryPoint>>(
        stream: _stream,
        builder: (context, snap) {
          final all = snap.data ?? const <HistoryPoint>[];
          final split = s.now.subtract(_range.duration);
          final cur = all.where((p) => !p.ts.isBefore(split)).toList();
          final prev = all.where((p) => p.ts.isBefore(split)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              SegmentedButton<_Range>(
                segments: [
                  for (final r in _Range.values) ButtonSegment(value: r, label: Text(r.label)),
                ],
                selected: {_range},
                onSelectionChanged: (sel) => setState(() {
                  _range = sel.first;
                  _stream = _makeStream();
                }),
              ),
              const SizedBox(height: 14),
              if (!snap.hasData)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (cur.isEmpty)
                const _Empty()
              else ...[
                _ScoreHero(
                  share: idealShare(cur, metrics),
                  previous: prev.length >= 12 ? idealShare(prev, metrics) : null,
                  readings: cur.length,
                  range: _range,
                ),
                const SizedBox(height: 12),
                _Findings(findings(cur, metrics)),
                const SectionTitle('Time on target'),
                _TimeInRange(points: cur, metrics: metrics),
                const SectionTitle('Readings summary'),
                _StatsList(points: cur, metrics: metrics),
                const SectionTitle('Daily pattern'),
                _HourlyPattern(points: cur, metrics: metrics),
              ],
              const SectionTitle('Harvest'),
              _HarvestCard(harvestStats(s.batches)),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Panel(
      padding: EdgeInsets.all(28),
      child: Column(children: [
        Icon(Icons.insights_rounded, size: 40, color: AppColors.inkDim),
        SizedBox(height: 10),
        Text('No readings in this period yet.', style: TextStyle(fontWeight: FontWeight.w600)),
        SizedBox(height: 4),
        Text('The controller saves a reading every 10 minutes.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkDim, fontSize: 13)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

class _ScoreHero extends StatelessWidget {
  const _ScoreHero({required this.share, required this.previous, required this.readings, required this.range});
  final double? share;
  final double? previous;
  final int readings;
  final _Range range;

  @override
  Widget build(BuildContext context) {
    final pct = share == null ? null : share! * 100;
    final delta = (share != null && previous != null) ? (share! - previous!) * 100 : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(color: AppColors.night, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ideal conditions',
            style: TextStyle(color: AppColors.onNightDim, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          AnimatedNumber(value: pct, style: numberStyle(64, color: AppColors.lime, weight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text('%', style: numberStyle(24, color: AppColors.lime)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'of the last ${range.label} had humidity, temperature and CO2 all on target.',
          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
        ),
        if (delta != null) ...[
          const SizedBox(height: 12),
          _DeltaChip(delta: delta, range: range),
        ],
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: (share ?? 0).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              color: AppColors.lime,
              backgroundColor: AppColors.nightSoft,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text('Based on $readings saved readings',
            style: const TextStyle(color: AppColors.onNightDim, fontSize: 12)),
      ]),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.delta, required this.range});
  final double delta;
  final _Range range;

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(color: AppColors.nightSoft, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 14, color: up ? AppColors.lime : const Color(0xFFFF8A7A)),
          const SizedBox(width: 4),
          Flexible(
            child: Text('${delta.abs().round()} ${delta.abs().round() == 1 ? 'pt' : 'pts'} vs the previous ${range.label}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _Findings extends StatelessWidget {
  const _Findings(this.items);
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          IconBadge(icon: Icons.lightbulb_outline_rounded, background: AppColors.primarySoft, size: 34),
          SizedBox(width: 10),
          Text('What the data says', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        const SizedBox(height: 10),
        for (final f in items)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                margin: const EdgeInsets.only(top: 7, right: 10),
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
              ),
              Expanded(child: Text(f, style: const TextStyle(fontSize: 14, height: 1.4))),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

class _Legend extends StatelessWidget {
  const _Legend({this.showLow = true});
  final bool showLow;

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 12, color: AppColors.inkDim, fontWeight: FontWeight.w600)),
        ]);
    return Wrap(spacing: 14, runSpacing: 6, children: [
      if (showLow) item(_lowColor, 'Below target'),
      item(_inColor, 'On target'),
      item(_highColor, 'Above target'),
    ]);
  }
}

class _TimeInRange extends StatelessWidget {
  const _TimeInRange({required this.points, required this.metrics});
  final List<HistoryPoint> points;
  final List<Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Legend(),
        for (final m in metrics)
          if (metricStats(points, m) case final s?) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700))),
              AnimatedNumber(
                value: s.inShare * 100,
                style: numberStyle(16, weight: FontWeight.w700),
              ),
              const Text('% on target', style: TextStyle(fontSize: 13, color: AppColors.inkDim)),
            ]),
            const SizedBox(height: 8),
            _ZoneBar(low: s.lowShare, mid: s.inShare, high: s.highShare),
            const SizedBox(height: 6),
            Text(
              [
                if (m.low != null) '${(s.lowShare * 100).round()}% below',
                '${(s.highShare * 100).round()}% above',
                'target ${m.low == null ? 'under ${m.fmt(m.high!)}' : '${m.fmt(m.low!)}–${m.fmt(m.high!)}'} ${m.unit}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.inkDim),
            ),
          ],
      ]),
    );
  }
}

/// Stacked bar: below / on / above target, with a 2 px gap between parts.
class _ZoneBar extends StatelessWidget {
  const _ZoneBar({required this.low, required this.mid, required this.high});
  final double low, mid, high;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => LayoutBuilder(builder: (context, c) {
        final parts = [(low, _lowColor), (mid, _inColor), (high, _highColor)]
            .where((p) => p.$1 > 0.004)
            .toList();
        final gaps = (parts.length - 1) * 2.0;
        final w = (c.maxWidth - gaps) * t;
        return Container(
          height: 12,
          decoration: BoxDecoration(color: AppColors.track, borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            for (final (i, p) in parts.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(
                width: max(0, w * p.$1),
                decoration: BoxDecoration(color: p.$2, borderRadius: BorderRadius.circular(4)),
              ),
            ],
          ]),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------

class _StatsList extends StatelessWidget {
  const _StatsList({required this.points, required this.metrics});
  final List<HistoryPoint> points;
  final List<Metric> metrics;

  static const _icons = [Icons.water_drop_outlined, Icons.thermostat_rounded, Icons.co2_rounded];
  static const _tones = [AppColors.slate, AppColors.clay, AppColors.plum];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final (i, m) in metrics.indexed)
        if (metricStats(points, m) case final s?)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconBadge(icon: _icons[i], color: _tones[i], background: _tones[i].withValues(alpha: 0.12)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${m.name} average', style: const TextStyle(color: AppColors.inkDim, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      AnimatedNumber(value: s.avg, decimals: m.decimals, style: numberStyle(28, weight: FontWeight.w700)),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 3),
                        child: Text(m.unit, style: const TextStyle(color: AppColors.inkDim, fontSize: 13)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _Fact('Low', '${m.fmt(s.min)} ${m.unit}'),
                      _Fact('High', '${m.fmt(s.max)} ${m.unit}'),
                      _Fact('Swing', '±${m.fmt(s.spread)}'),
                      _Fact(
                        'Off target',
                        s.excursions == 0
                            ? 'never'
                            : '${s.excursions}× · longest ${_duration(s.longestExcursion)}',
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
    ]);
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label  ', style: const TextStyle(color: AppColors.inkDim, fontSize: 12)),
        TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      ])),
    );
  }
}

// ---------------------------------------------------------------------------

class _HourlyPattern extends StatefulWidget {
  const _HourlyPattern({required this.points, required this.metrics});
  final List<HistoryPoint> points;
  final List<Metric> metrics;

  @override
  State<_HourlyPattern> createState() => _HourlyPatternState();
}

class _HourlyPatternState extends State<_HourlyPattern> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics[_i];
    final hourly = hourlyAverages(widget.points, m);
    final spots = [
      for (var h = 0; h < 24; h++)
        if (hourly[h] case final v?) FlSpot(h.toDouble(), v),
    ];
    final worst = worstHour(hourly, m);

    final ys = [...spots.map((s) => s.y), ?m.low, ?m.high];
    var minY = ys.reduce(min), maxY = ys.reduce(max);
    final pad = max((maxY - minY) * 0.15, m.decimals == 0 ? 2.0 : 0.5);
    minY -= pad;
    maxY += pad;

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, children: [
          for (final (i, x) in widget.metrics.indexed)
            ChoiceChip(
              label: Text(x.name),
              selected: i == _i,
              onSelected: (_) => setState(() => _i = i),
              showCheckmark: false,
              selectedColor: AppColors.night,
              labelStyle: TextStyle(
                color: i == _i ? Colors.white : AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
              shape: const StadiumBorder(side: BorderSide(color: AppColors.line)),
            ),
        ]),
        const SizedBox(height: 12),
        Text(
          worst == null
              ? 'Average ${m.name.toLowerCase()} by hour of day.'
              : 'Average ${m.name.toLowerCase()} by hour of day. '
                  'Hardest hour: ${_hour(worst.hour)} (${m.fmt(worst.value)} ${m.unit}).',
          style: const TextStyle(color: AppColors.inkDim, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 190,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 23,
              minY: minY,
              maxY: maxY,
              clipData: const FlClipData.all(),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.line, strokeWidth: 1),
              ),
              rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
                HorizontalRangeAnnotation(
                  y1: m.low ?? minY,
                  y2: m.high ?? maxY,
                  color: _inColor.withValues(alpha: 0.07),
                ),
              ]),
              extraLinesData: ExtraLinesData(horizontalLines: [
                for (final b in [?m.low, ?m.high])
                  HorizontalLine(y: b, color: AppColors.inkDim.withValues(alpha: 0.6), strokeWidth: 1, dashArray: const [5, 4]),
              ]),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, meta) => v == meta.min || v == meta.max
                        ? const SizedBox.shrink()
                        : Text(v.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 11, color: AppColors.inkDim)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 6,
                    // Only 12 AM, 6 AM, 12 PM, 6 PM: the 11 PM edge label would be cut off.
                    getTitlesWidget: (v, meta) => v.toInt() % 6 != 0
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_hour(v.toInt()),
                                style: const TextStyle(fontSize: 11, color: AppColors.inkDim)),
                          ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.night,
                  getTooltipItems: (ss) => [
                    for (final s in ss)
                      LineTooltipItem(
                        '${_hour(s.x.toInt())}\n${m.fmt(s.y)} ${m.unit}',
                        const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: AppColors.ink,
                  barWidth: 2,
                  dotData: FlDotData(
                    getDotPainter: (s, _, _, _) => FlDotCirclePainter(
                      radius: 4,
                      color: _zoneColor(m.zone(s.y)),
                      strokeWidth: 2,
                      strokeColor: AppColors.surface,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: 10),
        _Legend(showLow: m.low != null),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------

class _HarvestCard extends StatelessWidget {
  const _HarvestCard(this.h);
  final HarvestStats h;

  @override
  Widget build(BuildContext context) {
    if (h.harvested == 0) {
      return const Panel(
        child: Text('No finished batches yet. Yield numbers appear after the first harvest.',
            style: TextStyle(color: AppColors.inkDim)),
      );
    }
    final kg = h.totalG / 1000;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _Big(label: 'Total yield', value: kg, decimals: 2, unit: 'kg')),
          Expanded(child: _Big(label: 'Batches', value: h.harvested.toDouble(), unit: '')),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Big(label: 'Average per batch', value: h.avgG, unit: 'g', small: true)),
          Expanded(child: _Big(label: 'Pinning to harvest', value: h.avgDays, decimals: 1, unit: 'days', small: true)),
        ]),
        if (h.recent.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Yield per batch', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(height: 150, child: _YieldChart(h.recent)),
        ],
      ]),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value, required this.unit, this.decimals = 0, this.small = false});
  final String label;
  final double? value;
  final String unit;
  final int decimals;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.inkDim, fontSize: 12.5)),
      const SizedBox(height: 4),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        AnimatedNumber(
            value: value, decimals: decimals, style: numberStyle(small ? 22 : 30, weight: FontWeight.w700)),
        if (unit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Text(unit, style: const TextStyle(color: AppColors.inkDim, fontSize: 13)),
          ),
      ]),
    ]);
  }
}

class _YieldChart extends StatelessWidget {
  const _YieldChart(this.batches);
  final List<Batch> batches;

  @override
  Widget build(BuildContext context) {
    final top = batches.map((b) => b.weightG!).reduce(max);
    return BarChart(
      BarChartData(
        maxY: top * 1.2,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => v == meta.max
                  ? const SizedBox.shrink()
                  : Text('${v.toStringAsFixed(0)} g', style: const TextStyle(fontSize: 10, color: AppColors.inkDim)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) {
                final b = batches[v.toInt()];
                final d = b.harvestedAt!;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${d.month}/${d.day}', style: const TextStyle(fontSize: 11, color: AppColors.inkDim)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.night,
            getTooltipItem: (g, _, rod, _) => BarTooltipItem(
              '${rod.toY.toStringAsFixed(0)} g',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ),
        barGroups: [
          for (final (i, b) in batches.indexed)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: b.weightG!,
                width: 22,
                color: AppColors.night,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
      duration: const Duration(milliseconds: 600),
    );
  }
}
