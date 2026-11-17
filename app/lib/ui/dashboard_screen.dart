import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/alerts.dart';
import '../models/farm_models.dart';
import '../state/farm_state.dart';
import 'theme.dart';
import 'widgets/status_chip.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    return Scaffold(
      appBar: AppBar(
        title: const PageTitle('My Farm'),
        actions: const [ConnectionChip()],
      ),
      body: !s.liveLoaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _AlertsSection(alerts: s.alerts),
                const SectionTitle('Grow room now'),
                const _ReadingsGrid(),
                const SectionTitle('Control mode'),
                const _ModeCard(),
                const SectionTitle('Devices'),
                const _DevicesCard(),
                const SizedBox(height: 12),
                if (s.live.rtc != null)
                  Center(
                    child: Text('Controller clock: ${s.live.rtc}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
    );
  }
}

class _AlertsSection extends StatelessWidget {
  const _AlertsSection({required this.alerts});
  final List<FarmAlert> alerts;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: _AlertCard(
          FarmAlert(Severity.ok, 'Everything looks good', 'All readings are within your targets.'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (final a in alerts)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: _AlertCard(a)),
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
        color: alert.severity.background(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(alert.severity.icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(alert.message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingsGrid extends StatelessWidget {
  const _ReadingsGrid();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final live = s.live;
    final sp = s.setpoints;
    final water = waterStatus(live);

    final cards = [
      _ReadingCard(
        icon: Icons.water_drop,
        label: 'Humidity',
        value: live.rh?.toStringAsFixed(1) ?? '--',
        unit: '%',
        caption: 'Target ${sp.humOn.toStringAsFixed(0)}–${sp.humOff.toStringAsFixed(0)}%',
        severity: humidityStatus(live.rh, sp),
      ),
      _ReadingCard(
        icon: Icons.thermostat,
        label: 'Temperature',
        value: live.temp?.toStringAsFixed(1) ?? '--',
        unit: '°C',
        caption: 'Target ${sp.tempMin.toStringAsFixed(0)}–${sp.tempMax.toStringAsFixed(0)} °C',
        severity: tempStatus(live.temp, sp),
      ),
      _ReadingCard(
        icon: Icons.co2,
        label: 'CO2',
        value: live.co2?.toString() ?? '--',
        unit: 'ppm',
        caption: 'Fan on above ${sp.co2On}',
        severity: co2Status(live.co2, sp),
      ),
      _ReadingCard(
        icon: Icons.water,
        label: 'Water tank',
        value: live.waterCutoff == true
            ? 'Empty'
            : live.lowWater
                ? 'Low'
                : 'OK',
        unit: '',
        caption: live.deviceOn(DeviceId.refill) ? 'Refilling…' : 'Float switch',
        severity: water,
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 640 ? 4 : 2;
      const gap = 12.0;
      final w = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final card in cards) SizedBox(width: w, child: card)],
      );
    });
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.caption,
    required this.severity,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String caption;
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = severity.color(context);
    return Semantics(
      label: '$label $value $unit. $caption',
      child: Card(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label, style: t.labelLarge)),
                  Icon(severity.icon, size: 16, color: color),
                ]),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(value,
                          style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(unit, style: t.titleSmall),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(caption, style: t.bodySmall?.copyWith(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final mode = s.modeDisplay;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<FarmMode>(
              segments: const [
                ButtonSegment(
                    value: FarmMode.auto, icon: Icon(Icons.autorenew), label: Text('Auto')),
                ButtonSegment(
                    value: FarmMode.manual, icon: Icon(Icons.touch_app), label: Text('Manual')),
              ],
              selected: {mode},
              onSelectionChanged: !s.online || s.modePending
                  ? null
                  : (sel) => _changeMode(context, s, sel.first),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (s.modePending) ...[
                  const SizedBox.square(
                      dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
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
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeMode(BuildContext context, FarmState s, FarmMode mode) async {
    if (mode == FarmMode.manual) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Switch to Manual?'),
          content: const Text(
              'Humidity, CO2 and water will no longer be controlled automatically '
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

class _DevicesCard extends StatelessWidget {
  const _DevicesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final (i, d) in DeviceId.values.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 72),
            _DeviceTile(d),
          ],
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(this.device);
  final DeviceId device;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final scheme = Theme.of(context).colorScheme;
    final on = s.deviceDisplayState(device);
    final pending = s.isDevicePending(device);
    final lock = s.lockReason(device);

    final status = [
      pending ? 'Sending…' : (on ? 'ON' : 'OFF'),
      lock ?? device.description,
    ].join(' · ');

    return ListTile(
      minVerticalPadding: 12,
      leading: CircleAvatar(
        backgroundColor: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        foregroundColor: on ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        child: Icon(device.icon),
      ),
      title: Text(device.label),
      subtitle: Text(status),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox.square(
                  dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Switch(
            value: on,
            onChanged: lock != null || pending
                ? null
                : (v) async {
                    final err = await s.setDevice(device, v);
                    if (err != null && context.mounted) showMessage(context, err);
                  },
          ),
        ],
      ),
    );
  }
}
