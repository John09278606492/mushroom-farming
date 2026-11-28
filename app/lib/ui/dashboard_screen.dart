import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/alerts.dart';
import '../logic/insights.dart';
import '../models/farm_models.dart';
import '../state/farm_state.dart';
import 'notifications_screen.dart';
import 'theme.dart';
import 'widgets/gauge.dart';
import 'widgets/motion.dart';
import 'widgets/status_chip.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final problems = s.alerts.where((a) => a.severity.index >= Severity.warning.index).toList();
    return AppScaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(DateFormat('EEE, MMM d').format(s.now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkDim, fontWeight: FontWeight.w500)),
              ),
              // The tag sits up here so the bell and status fit beside the title.
              const DemoBadge(),
            ]),
            const SizedBox(height: 2),
            const Text('Grow room', maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: const [NotificationBell(), ConnectionChip()],
      ),
      body: !s.liveLoaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              children: [
                const _HeroCard(),
                if (problems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final a in problems)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: _AlertCard(a)),
                ],
                const SectionTitle('Climate'),
                const _Readings(),
                const SectionTitle('Mode'),
                const _ModeCard(),
                const SectionTitle('Devices'),
                const _DevicesGrid(),
                const SizedBox(height: 18),
                if (s.live.rtc != null)
                  Center(
                    child: Text('Controller clock  ${s.live.rtc}',
                        style: const TextStyle(color: AppColors.inkDim, fontSize: 12)),
                  ),
              ],
            ),
    );
  }
}

// ───────────────────────── Hero ─────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final insight = computeInsight(s.live, s.setpoints, s.now, openBatch: s.openBatch);
    final batch = s.openBatch;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.night,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Room condition',
                        style: TextStyle(fontSize: 13, color: AppColors.onNightDim)),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(insight.headline,
                          key: ValueKey(insight.headline),
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.2,
                              letterSpacing: -0.3)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedNumber(
                    value: insight.score?.toDouble(),
                    style: numberStyle(46, color: AppColors.lime, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  const Text('score', style: TextStyle(fontSize: 12, color: AppColors.onNightDim)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final tip in insight.tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(top: 7, right: 10),
                  decoration: const BoxDecoration(color: AppColors.lime, shape: BoxShape.circle),
                ),
                Expanded(
                  child: Text(tip,
                      style: const TextStyle(fontSize: 13.5, color: Color(0xFFD9DED5), height: 1.4)),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _NightChip(
              icon: s.modeDisplay == FarmMode.auto ? Icons.autorenew_rounded : Icons.back_hand_rounded,
              text: s.modeDisplay == FarmMode.auto ? 'Auto mode' : 'Manual mode',
            ),
            _NightChip(icon: Icons.eco_rounded, text: s.setpoints.stage.label),
            if (batch != null)
              _NightChip(icon: Icons.event_rounded, text: 'Batch day ${batch.dayNumber(s.now)}'),
          ]),
        ],
      ),
    );
  }
}

class _NightChip extends StatelessWidget {
  const _NightChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: AppColors.nightSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.lime),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard(this.alert);
  final FarmAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = alert.severity.color(context);
    return Panel(
      fill: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.30),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: alert.severity.icon, color: color, background: color.withValues(alpha: 0.14), size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.title,
                    style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(alert.message, style: const TextStyle(color: AppColors.inkDim, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Readings ─────────────────────────

/// Short status word for a reading against its target band.
String _word(double? v, double? low, double? high) {
  if (v == null) return 'No data';
  if (low != null && v < low) return 'Low';
  if (high != null && v > high) return 'High';
  return 'In range';
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _Readings extends StatelessWidget {
  const _Readings();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final live = s.live;
    final sp = s.setpoints;
    final co2Max = (sp.co2On * 1.6).clamp(1500, 8000).toDouble();
    const tMin = 10.0, tMax = 40.0;

    final humidity = _HumidityCard(
      rh: live.rh,
      target: 'Target ${sp.humOn.toStringAsFixed(0)}–${sp.humOff.toStringAsFixed(0)} %',
      status: _word(live.rh, sp.humOn, sp.humOff),
      severity: humidityStatus(live.rh, sp),
      mistOn: live.deviceOn(DeviceId.mist),
    );
    final temp = _SmallReading(
      icon: Icons.thermostat_rounded,
      label: 'Temperature',
      value: live.temp,
      decimals: 1,
      unit: '°C',
      caption: '${sp.tempMin.toStringAsFixed(0)}–${sp.tempMax.toStringAsFixed(0)} °C',
      status: _word(live.temp, sp.tempMin, sp.tempMax),
      severity: tempStatus(live.temp, sp),
      fraction: live.temp == null ? null : (live.temp! - tMin) / (tMax - tMin),
      targetFrom: (sp.tempMin - tMin) / (tMax - tMin),
      targetTo: (sp.tempMax - tMin) / (tMax - tMin),
      color: AppColors.clay,
    );
    final co2 = _SmallReading(
      icon: Icons.co2_rounded,
      label: 'CO2',
      value: live.co2?.toDouble(),
      decimals: 0,
      unit: 'ppm',
      caption: 'Fan above ${sp.co2On}',
      status: _word(live.co2?.toDouble(), null, sp.co2On.toDouble()),
      severity: co2Status(live.co2, sp),
      fraction: live.co2 == null ? null : live.co2! / co2Max,
      targetFrom: 0,
      targetTo: sp.co2On / co2Max,
      color: AppColors.plum,
    );
    final water = _WaterCard(live: live);

    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      if (c.maxWidth >= 640) {
        final w = (c.maxWidth - gap * 2) / 3;
        return Column(children: [
          Row(children: [
            Expanded(flex: 2, child: humidity),
            const SizedBox(width: gap),
            Expanded(child: water),
          ]),
          const SizedBox(height: gap),
          Row(children: [
            SizedBox(width: w * 1.5 + gap / 2, child: temp),
            const SizedBox(width: gap),
            Expanded(child: co2),
          ]),
        ]);
      }
      return Column(children: [
        humidity,
        const SizedBox(height: gap),
        Row(children: [
          Expanded(child: temp),
          const SizedBox(width: gap),
          Expanded(child: co2),
        ]),
        const SizedBox(height: gap),
        water,
      ]);
    });
  }
}

class _HumidityCard extends StatelessWidget {
  const _HumidityCard({
    required this.rh,
    required this.target,
    required this.status,
    required this.severity,
    required this.mistOn,
  });

  final double? rh;
  final String target;
  final String status;
  final Severity severity;
  final bool mistOn;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Humidity ${rh?.toStringAsFixed(1) ?? 'no data'} percent. $target',
      child: Container(
        height: 176,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
        ),
        child: LiquidFill(
          level: rh == null ? null : rh! / 100,
          color: AppColors.slate,
          borderRadius: 24,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const IconBadge(
                      icon: Icons.water_drop_rounded,
                      color: AppColors.slate,
                      background: Color(0xFFE6EEFA),
                      size: 36),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Humidity',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                  ),
                  _StatusPill(status, severity.color(context)),
                ]),
                const Spacer(),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  AnimatedNumber(value: rh, decimals: 1, style: numberStyle(56, weight: FontWeight.w700)),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text('%', style: TextStyle(fontSize: 20, color: AppColors.inkDim)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(mistOn ? '$target  ·  mist maker on' : target,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallReading extends StatelessWidget {
  const _SmallReading({
    required this.icon,
    required this.label,
    required this.value,
    required this.decimals,
    required this.unit,
    required this.caption,
    required this.status,
    required this.severity,
    required this.fraction,
    required this.color,
    this.targetFrom,
    this.targetTo,
  });

  final IconData icon;
  final String label;
  final double? value;
  final int decimals;
  final String unit;
  final String caption;
  final String status;
  final Severity severity;
  final double? fraction;
  final Color color;
  final double? targetFrom;
  final double? targetTo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label ${value?.toStringAsFixed(decimals) ?? 'no data'} $unit. $caption',
      child: Panel(
        radius: 24,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconBadge(icon: icon, color: color, background: color.withValues(alpha: 0.12), size: 34),
              const Spacer(),
              _StatusPill(status, severity.color(context)),
            ]),
            const SizedBox(height: 14),
            Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.inkDim, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AnimatedNumber(
                      value: value, decimals: decimals, style: numberStyle(32, weight: FontWeight.w700)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 3),
                child: Text(unit, style: const TextStyle(fontSize: 13, color: AppColors.inkDim)),
              ),
            ]),
            const SizedBox(height: 12),
            RangeBar(fraction: fraction, color: color, targetFrom: targetFrom, targetTo: targetTo),
            const SizedBox(height: 6),
            Text(caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.inkDim)),
          ],
        ),
      ),
    );
  }
}

class _WaterCard extends StatelessWidget {
  const _WaterCard({required this.live});
  final LiveData live;

  @override
  Widget build(BuildContext context) {
    final sev = waterStatus(live);
    final refilling = live.deviceOn(DeviceId.refill);
    final (text, level) = live.waterCutoff == true
        ? ('Empty', 0.08)
        : live.lowWater
            ? ('Low', 0.32)
            : ('Full enough', 0.78);
    final status = live.waterCutoff == true ? 'Refill now' : live.lowWater ? 'Low' : 'Normal';
    return Container(
      // Grows when the refill line shows or the phone uses large text.
      constraints: const BoxConstraints(minHeight: 104),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: LiquidFill(
        level: live.hasData ? level : null,
        color: sev == Severity.ok ? AppColors.teal : sev.color(context),
        borderRadius: 24,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            const IconBadge(
                icon: Icons.water_rounded, color: AppColors.teal, background: Color(0xFFE0F2EF), size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Water tank', style: TextStyle(fontSize: 13, color: AppColors.inkDim)),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(live.hasData ? text : '--',
                        key: ValueKey(text),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                  if (refilling)
                    const Text('Refill pump is running',
                        style: TextStyle(fontSize: 12, color: AppColors.ink)),
                ],
              ),
            ),
            _StatusPill(status, sev.color(context)),
          ]),
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
    final enabled = s.online && !s.modePending;
    return Panel(
      radius: 24,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModeSwitch(
            auto: mode == FarmMode.auto,
            onChanged: enabled ? (auto) => _changeMode(context, s, auto ? FarmMode.auto : FarmMode.manual) : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
            child: Row(
              children: [
                if (s.modePending) ...[
                  const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      s.modePending
                          ? 'Sending to the controller…'
                          : mode == FarmMode.auto
                              ? 'The controller runs the mist maker, exhaust fan and refill pump '
                                  'from your thresholds. You can still switch the sprinkler and light.'
                              : 'You control every device yourself. Remember to switch back to Auto.',
                      key: ValueKey('${s.modePending}$mode'),
                      style: const TextStyle(fontSize: 13, color: AppColors.inkDim, height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeMode(BuildContext context, FarmState s, FarmMode mode) async {
    if (mode == s.modeDisplay) return;
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

/// Two-option pill with a black thumb that slides between Auto and Manual.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.auto, required this.onChanged});
  final bool auto;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    Widget label(String text, IconData icon, bool selected, bool value) => Expanded(
          child: Semantics(
            button: true,
            selected: selected,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: onChanged == null ? null : () => onChanged!(value),
              child: SizedBox(
                height: 48,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.inkDim,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 18, color: selected ? AppColors.lime : AppColors.inkDim),
                      const SizedBox(width: 6),
                      Text(text),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );

    return Opacity(
      opacity: onChanged == null ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.all(4),
        child: Stack(children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            alignment: auto ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                height: 48,
                decoration: BoxDecoration(color: AppColors.night, borderRadius: BorderRadius.circular(26)),
              ),
            ),
          ),
          Row(children: [
            label('Auto', Icons.autorenew_rounded, auto, true),
            label('Manual', Icons.back_hand_rounded, !auto, false),
          ]),
        ]),
      ),
    );
  }
}

// ───────────────────────── Devices ─────────────────────────

class _DevicesGrid extends StatelessWidget {
  const _DevicesGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 640 ? 3 : 2;
      const gap = 12.0;
      final w = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final d in DeviceId.values) SizedBox(width: w, child: _DeviceTile(d))],
      );
    });
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(this.device);
  final DeviceId device;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final on = s.deviceDisplayState(device);
    final pending = s.isDevicePending(device);
    final lock = s.lockReason(device);

    Future<void> toggle(bool v) async {
      final err = await s.setDevice(device, v);
      if (err != null && context.mounted) showMessage(context, err);
    }

    final canToggle = lock == null && !pending;
    final status = pending ? 'Sending…' : (on ? 'On' : 'Off');
    const curve = Curves.easeOutCubic;
    const dur = Duration(milliseconds: 380);

    return Semantics(
      toggled: on,
      label: '${device.label}, $status${lock != null ? ', $lock' : ''}',
      child: AnimatedContainer(
        duration: dur,
        curve: curve,
        height: 148,
        decoration: BoxDecoration(
          color: on ? AppColors.night : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: on ? AppColors.night : AppColors.line),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: canToggle ? () => toggle(!on) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    IconBadge(
                      icon: device.icon,
                      size: 42,
                      color: on ? AppColors.night : AppColors.ink,
                      background: on ? AppColors.lime : AppColors.surfaceAlt,
                    ),
                    const Spacer(),
                    if (pending)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    Transform.scale(
                      scale: 0.82,
                      child: Switch(value: on, onChanged: canToggle ? toggle : null),
                    ),
                  ]),
                  const Spacer(),
                  AnimatedDefaultTextStyle(
                    duration: dur,
                    curve: curve,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.ink),
                    child: Text(device.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: dur,
                    curve: curve,
                    style: TextStyle(fontSize: 12, color: on ? AppColors.onNightDim : AppColors.inkDim),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: status,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: on ? AppColors.lime : AppColors.inkDim),
                        ),
                        TextSpan(text: '  ${lock ?? device.description}'),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
