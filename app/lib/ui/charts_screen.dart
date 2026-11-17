import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/farm_models.dart';
import '../state/farm_state.dart';
import 'widgets/status_chip.dart';

enum _Range {
  h6('6 h', Duration(hours: 6)),
  h24('24 h', Duration(hours: 24)),
  d7('7 days', Duration(days: 7));

  const _Range(this.label, this.duration);
  final String label;
  final Duration duration;
}

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  _Range _range = _Range.h24;
  Stream<List<HistoryPoint>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _makeStream();
  }

  Stream<List<HistoryPoint>> _makeStream() =>
      context.read<FarmState>().repo.watchHistory(_range.duration);

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<FarmState>().setpoints;
    return Scaffold(
      appBar: AppBar(title: const PageTitle('History'), actions: const [ConnectionChip()]),
      body: StreamBuilder<List<HistoryPoint>>(
        stream: _stream,
        builder: (context, snap) {
          final points = snap.data ?? const <HistoryPoint>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
              const SizedBox(height: 12),
              if (!snap.hasData)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (points.isEmpty)
                const _EmptyHistory()
              else ...[
                _ChartCard(
                  title: 'Humidity',
                  unit: '%',
                  decimals: 0,
                  color: Colors.blue,
                  points: points,
                  value: (p) => p.rh,
                  range: _range,
                  bands: [sp.humOn, sp.humOff],
                ),
                const SizedBox(height: 12),
                _ChartCard(
                  title: 'Temperature',
                  unit: '°C',
                  decimals: 1,
                  color: Colors.orange,
                  points: points,
                  value: (p) => p.temp,
                  range: _range,
                  bands: [sp.tempMin, sp.tempMax],
                ),
                const SizedBox(height: 12),
                _ChartCard(
                  title: 'CO2',
                  unit: 'ppm',
                  decimals: 0,
                  color: Colors.purple,
                  points: points,
                  value: (p) => p.co2?.toDouble(),
                  range: _range,
                  bands: [sp.co2On.toDouble()],
                ),
                const SizedBox(height: 8),
                Text('Dashed lines are your targets.',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Icon(Icons.show_chart, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        const Text('No readings in this time range yet.', textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('The controller saves a reading every 10 minutes.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.unit,
    required this.decimals,
    required this.color,
    required this.points,
    required this.value,
    required this.range,
    required this.bands,
  });

  final String title;
  final String unit;
  final int decimals;
  final Color color;
  final List<HistoryPoint> points;
  final double? Function(HistoryPoint) value;
  final _Range range;
  final List<double> bands;

  /// Keeps charts fast on phones: at most ~300 points per line.
  static List<FlSpot> _spots(List<HistoryPoint> pts, double? Function(HistoryPoint) f) {
    final step = max(1, (pts.length / 300).ceil());
    final out = <FlSpot>[];
    for (var i = 0; i < pts.length; i += step) {
      final v = f(pts[i]);
      if (v != null) out.add(FlSpot(pts[i].ts.millisecondsSinceEpoch.toDouble(), v));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final spots = _spots(points, value);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (spots.isEmpty) return const SizedBox.shrink();

    final values = spots.map((s) => s.y).toList();
    final lo = values.reduce(min);
    final hi = values.reduce(max);
    final avg = values.reduce((a, b) => a + b) / values.length;

    final all = [...values, ...bands];
    var minY = all.reduce(min);
    var maxY = all.reduce(max);
    final pad = max((maxY - minY) * 0.1, 1.0);
    minY -= pad;
    maxY += pad;

    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final minX = now - range.duration.inMilliseconds;
    final xFormat = range == _Range.d7 ? DateFormat('EEE') : DateFormat('h a');
    String fmt(double v) => v.toStringAsFixed(decimals);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: t.titleMedium)),
                Text('${fmt(spots.last.y)} $unit',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text('Min ${fmt(lo)} · Avg ${fmt(avg)} · Max ${fmt(hi)} $unit',
                  style: t.bodySmall),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: now,
                  minY: minY,
                  maxY: maxY,
                  clipData: const FlClipData.all(),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(horizontalLines: [
                    for (final b in bands)
                      HorizontalLine(
                        y: b,
                        color: scheme.outline,
                        strokeWidth: 1,
                        dashArray: const [5, 4],
                      ),
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
                            : Text(v.toStringAsFixed(0), style: t.labelSmall),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: range.duration.inMilliseconds / 4,
                        getTitlesWidget: (v, meta) {
                          if (v == meta.min || v == meta.max) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              xFormat.format(DateTime.fromMillisecondsSinceEpoch(v.toInt())),
                              style: t.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final s in spots)
                          LineTooltipItem(
                            '${fmt(s.y)} $unit\n${DateFormat('MMM d, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(s.x.toInt()))}',
                            TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: color,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
                    ),
                  ],
                ),
                duration: Duration.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
