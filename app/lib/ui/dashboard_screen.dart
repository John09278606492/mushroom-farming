import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/alerts.dart';
import '../logic/insights.dart';
import '../models/farm_models.dart';
import '../state/farm_state.dart';
import 'theme.dart';
import 'widgets/gauge.dart';
import 'widgets/status_chip.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final problems = s.alerts.where((a) => a.severity.index >= Severity.warning.index).toList();
    return AiScaffold(
      appBar: AppBar(
        title: const PageTitle('My Farm'),
        actions: const [ConnectionChip()],
      ),
      body: !s.liveLoaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                const _AssistantCard(),
                if (problems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final a in problems)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: _AlertCard(a)),
                ],
                const SectionTitle('Grow room now'),
                const _ReadingsGrid(),
                const SectionTitle('Control mode'),
                const _ModeCard(),
                const SectionTitle('Devices'),
                const _DevicesGrid(),
                const SizedBox(height: 16),
                if (s.live.rtc != null)
                  Center(
                    child: Text('Controller clock · ${s.live.rtc}',
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ),
              ],
            ),
    );
  }
}

// ───────────────────────── Farm Assistant ─────────────────────────

class _AssistantCard extends StatelessWidget {
  const _AssistantCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final insight = computeInsight(s.live, s.setpoints, s.now, openBatch: s.openBatch);
    final moodColor = insight.mood.color(context);

    return GlassCard(
      gradientBorder: true,
      glow: AppColors.violet,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.aiGradient),
              child: const Icon(Icons.auto_awesome, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const GradientText('Farm Assistant',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
            const Spacer(),
            PulseDot(color: s.online ? AppColors.green : AppColors.red, animate: s.online),
            Text(s.online ? 'Live' : 'Offline',
                style: TextStyle(fontSize: 12, color: s.online ? AppColors.green : AppColors.red)),
          ]),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RingGauge(
                size: 84,
                stroke: 8,
                fraction: insight.score == null ? null : insight.score! / 100,
                colors: [moodColor, AppColors.violet],
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(insight.score?.toString() ?? '--',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text, height: 1)),
                  const Text('health', style: TextStyle(fontSize: 10, color: AppColors.textDim)),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(insight.headline,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.25)),
                    const SizedBox(height: 8),
                    for (final tip in insight.tips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 6, right: 8),
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle, gradient: AppColors.aiGradient),
                          ),
                          Expanded(
                            child: Text(tip,
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.textDim, height: 1.35)),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard(this.alert);
  final FarmAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = alert.severity.color(context);
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 18, spreadRadius: -6)],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(alert.severity.icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.title,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(alert.message, style: const TextStyle(color: AppColors.text, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Readings ─────────────────────────

/// Lays out [children] in 2 columns on phones, 4 on wide screens.
class _Grid extends StatelessWidget {
  const _Grid({required this.children, this.wideColumns = 4});
  final List<Widget> children;
  final int wideColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 640 ? wideColumns : 2;
      const gap = 12.0;
      final w = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}

class _ReadingsGrid extends StatelessWidget {
  const _ReadingsGrid();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final live = s.live;
    final sp = s.setpoints;
    final co2Max = (sp.co2On * 1.6).clamp(1500, 8000).toDouble();
    const tMin = 10.0, tMax = 40.0;

    final water = waterStatus(live);
    final waterText = live.waterCutoff == true
        ? 'Empty'
        : live.lowWater
            ? 'Low'
            : 'OK';

    return _Grid(children: [
      _GaugeCard(
        label: 'Humidity',
        value: live.rh?.toStringAsFixed(1) ?? '--',
        unit: '%',
        caption: 'Target ${sp.humOn.toStringAsFixed(0)}–${sp.humOff.toStringAsFixed(0)}%',
        severity: humidityStatus(live.rh, sp),
        fraction: live.rh == null ? null : live.rh! / 100,
        targetFrom: sp.humOn / 100,
        targetTo: sp.humOff / 100,
        colors: const [AppColors.blue, AppColors.cyan],
        icon: Icons.water_drop,
      ),
      _GaugeCard(
        label: 'Temperature',
        value: live.temp?.toStringAsFixed(1) ?? '--',
        unit: '°C',
        caption: 'Target ${sp.tempMin.toStringAsFixed(0)}–${sp.tempMax.toStringAsFixed(0)} °C',
        severity: tempStatus(live.temp, sp),
        fraction: live.temp == null ? null : (live.temp! - tMin) / (tMax - tMin),
        targetFrom: (sp.tempMin - tMin) / (tMax - tMin),
        targetTo: (sp.tempMax - tMin) / (tMax - tMin),
        colors: const [AppColors.amber, AppColors.pink],
        icon: Icons.thermostat,
      ),
      _GaugeCard(
        label: 'CO2',
        value: live.co2?.toString() ?? '--',
        unit: 'ppm',
        caption: 'Fan on above ${sp.co2On}',
        severity: co2Status(live.co2, sp),
        fraction: live.co2 == null ? null : live.co2! / co2Max,
        targetFrom: 0,
        targetTo: sp.co2On / co2Max,
        colors: const [AppColors.violet, AppColors.pink],
        icon: Icons.co2,
      ),
      _GaugeCard(
        label: 'Water tank',
        value: waterText,
        unit: '',
        caption: live.deviceOn(DeviceId.refill) ? 'Refilling…' : 'Float switch',
        severity: water,
        fraction: switch (water) {
          Severity.critical => 0.06,
          Severity.warning => 0.3,
          _ => 0.88,
        },
        colors: [water.color(context), AppColors.cyan],
        icon: Icons.water,
      ),
    ]);
  }
}

class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.caption,
    required this.severity,
    required this.fraction,
    required this.colors,
    required this.icon,
    this.targetFrom,
    this.targetTo,
  });

  final String label;
  final String value;
  final String unit;
  final String caption;
  final Severity severity;
  final double? fraction;
  final List<Color> colors;
  final IconData icon;
  final double? targetFrom;
  final double? targetTo;

  @override
  Widget build(BuildContext context) {
    final color = severity.color(context);
    return Semantics(
      label: '$label $value $unit. $caption',
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        glow: severity.index >= Severity.warning.index ? color : null,
        child: Column(
          children: [
            Row(children: [
              Icon(icon, size: 16, color: colors.last),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
              Icon(severity.icon, size: 15, color: color),
            ]),
            const SizedBox(height: 6),
            RingGauge(
              fraction: fraction,
              colors: colors,
              targetFrom: targetFrom,
              targetTo: targetTo,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FittedBox(
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text, height: 1.1)),
                ),
                if (unit.isNotEmpty)
                  Text(unit, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
              ]),
            ),
            const SizedBox(height: 2),
            Text(caption,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Mode ─────────────────────────

class _ModeCard extends StatelessWidget {
  const _ModeCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final mode = s.modeDisplay;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<FarmMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: FarmMode.auto, icon: Icon(Icons.auto_awesome), label: Text('Auto')),
              ButtonSegment(value: FarmMode.manual, icon: Icon(Icons.touch_app), label: Text('Manual')),
            ],
            selected: {mode},
            onSelectionChanged:
                !s.online || s.modePending ? null : (sel) => _changeMode(context, s, sel.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (s.modePending) ...[
                const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  s.modePending
                      ? 'Sending to the controller…'
                      : mode == FarmMode.auto
                          ? 'The controller runs the mist maker, exhaust fan and refill pump '
                              'from your thresholds. You can still switch the sprinkler and light.'
                          : 'You control every device yourself. Remember to switch back to Auto.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textDim, height: 1.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeMode(BuildContext context, FarmState s, FarmMode mode) async {
    if (mode == FarmMode.manual) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Switch to Manual?'),
          content: const Text('Humidity, CO2 and water will no longer be controlled automatically '
              'until you switch back to Auto.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Switch')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final err = await s.setMode(mode);
    if (err != null && context.mounted) showMessage(context, err);
  }
}

// ───────────────────────── Devices ─────────────────────────

class _DevicesGrid extends StatelessWidget {
  const _DevicesGrid();

  @override
  Widget build(BuildContext context) {
    return _Grid(
      wideColumns: 3,
      children: [for (final d in DeviceId.values) _DeviceTile(d)],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(this.device);
  final DeviceId device;

  static const _accent = {
    DeviceId.mist: AppColors.cyan,
    DeviceId.fan: AppColors.violet,
    DeviceId.refill: AppColors.blue,
    DeviceId.sprinkler: AppColors.green,
    DeviceId.light: AppColors.amber,
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final on = s.deviceDisplayState(device);
    final pending = s.isDevicePending(device);
    final lock = s.lockReason(device);
    final accent = _accent[device]!;

    Future<void> toggle(bool v) async {
      final err = await s.setDevice(device, v);
      if (err != null && context.mounted) showMessage(context, err);
    }

    final canToggle = lock == null && !pending;
    final status = pending ? 'Sending…' : (on ? 'ON' : 'OFF');

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      glow: on ? accent : null,
      fill: on ? accent.withValues(alpha: 0.10) : null,
      onTap: canToggle ? () => toggle(!on) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? accent.withValues(alpha: 0.22) : AppColors.glassStrong,
                boxShadow: on ? [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 14)] : null,
              ),
              child: Icon(device.icon, size: 20, color: on ? accent : AppColors.textDim),
            ),
            const Spacer(),
            if (pending)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Transform.scale(
              scale: 0.85,
              child: Switch(value: on, onChanged: canToggle ? toggle : null),
            ),
          ]),
          const SizedBox(height: 10),
          Text(device.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: status,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: on ? accent : AppColors.textDim),
              ),
              TextSpan(text: ' · ${lock ?? device.description}'),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textDim, height: 1.3),
          ),
        ],
      ),
    );
  }
}
