import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/demo_farm_repository.dart';
import '../models/farm_models.dart';
import '../state/farm_state.dart';
import 'home_shell.dart';
import 'schedules_screen.dart';
import 'theme.dart';
import 'thresholds_screen.dart';
import 'widgets/status_chip.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final session = context.read<Session>();
    final sp = s.setpoints;
    final sprinklers = s.schedules[ScheduleDevice.sprinkler]!.whereType<Schedule>().length;
    final lights = s.schedules[ScheduleDevice.light]!.whereType<Schedule>().length;

    return Scaffold(
      appBar: AppBar(title: const PageTitle('Settings'), actions: const [ConnectionChip()]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const SectionTitle('Growth stage'),
          Row(children: [
            for (final (i, stage) in GrowthStage.values.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: _StageCard(stage, selected: sp.stage == stage)),
            ],
          ]),
          const SectionTitle('Automation'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Targets & thresholds'),
                subtitle: Text('Mist ${sp.humOn.toStringAsFixed(0)}–${sp.humOff.toStringAsFixed(0)}% '
                    '· Fan above ${sp.co2On} ppm'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => pushFarmPage(context, const ThresholdsScreen()),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.event_repeat),
                title: const Text('Schedules'),
                subtitle: Text('$sprinklers sprinkler · $lights light'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => pushFarmPage(context, const SchedulesScreen()),
              ),
            ]),
          ),
          const SectionTitle('Controller'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('Farm'),
                subtitle: Text(s.repo.farmName),
              ),
              if (s.live.rssi != null)
                ListTile(
                  leading: const Icon(Icons.wifi),
                  title: const Text('Wi-Fi signal'),
                  subtitle: Text('${s.live.rssi} dBm (${_signal(s.live.rssi!)})'),
                ),
              if (s.live.updatedAt != null)
                ListTile(
                  leading: const Icon(Icons.update),
                  title: const Text('Last update'),
                  subtitle: Text(formatDateTime(s.live.updatedAt!)),
                ),
            ]),
          ),
          if (s.repo is DemoFarmRepository) ...[
            const SectionTitle('Demo tools'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.water_damage_outlined),
                title: const Text('Simulate low water'),
                subtitle: const Text('Drains the demo tank to show the water alerts.'),
                onTap: () => (s.repo as DemoFarmRepository).drainWater(),
              ),
            ),
          ],
          const SectionTitle('Account'),
          Card(
            child: ListTile(
              leading: Icon(session.isDemo ? Icons.science_outlined : Icons.person_outline),
              title: Text(session.isDemo ? 'Demo mode' : (session.email ?? 'Signed in')),
              subtitle: Text(session.isDemo ? 'Simulated farm, nothing is real' : 'Firebase account'),
              trailing: TextButton(
                onPressed: session.signOut,
                child: Text(session.isDemo ? 'Exit demo' : 'Sign out'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('Smart Mushroom Farm · v1.0.0',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  static String _signal(int rssi) => rssi >= -60
      ? 'strong'
      : rssi >= -70
          ? 'good'
          : rssi >= -80
              ? 'weak'
              : 'very weak';
}

class _StageCard extends StatelessWidget {
  const _StageCard(this.stage, {required this.selected});
  final GrowthStage stage;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      color: selected ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: selected ? null : () => _apply(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(stage == GrowthStage.spawnRun ? Icons.dark_mode_outlined : Icons.spa,
                      color: selected ? scheme.onPrimaryContainer : scheme.primary),
                  const Spacer(),
                  if (selected) Icon(Icons.check_circle, color: scheme.onPrimaryContainer),
                ]),
                const SizedBox(height: 8),
                Text(stage.label,
                    style: t.titleMedium?.copyWith(
                        color: selected ? scheme.onPrimaryContainer : null,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(stage.summary,
                    style: t.bodySmall?.copyWith(color: selected ? scheme.onPrimaryContainer : null)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _apply(BuildContext context) async {
    final p = Setpoints.preset(stage);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Switch to ${stage.label}?'),
        content: Text(
          'This sets:\n'
          '• Mist ON below ${p.humOn.toStringAsFixed(0)}%, OFF above ${p.humOff.toStringAsFixed(0)}%\n'
          '• Fan ON above ${p.co2On} ppm, OFF below ${p.co2Off} ppm\n'
          '• Temperature alert ${p.tempMin.toStringAsFixed(0)}–${p.tempMax.toStringAsFixed(0)} °C\n\n'
          '${stage == GrowthStage.spawnRun ? 'Also turn off the grow-light schedule: spawn run should be dark.' : 'Make sure the grow light has a 12 h schedule.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await context.read<FarmState>().saveSetpoints(p);
    if (context.mounted) showMessage(context, err ?? '${stage.label} targets applied.');
  }
}
