import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/farm_models.dart';
import '../state/farm_state.dart';
import 'theme.dart';

/// Edit humidity / CO2 thresholds and temperature alert limits.
class ThresholdsScreen extends StatefulWidget {
  const ThresholdsScreen({super.key});

  @override
  State<ThresholdsScreen> createState() => _ThresholdsScreenState();
}

class _ThresholdsScreenState extends State<ThresholdsScreen> {
  late Setpoints _original;
  late Setpoints _sp;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _original = context.read<FarmState>().setpoints;
    _sp = _original;
  }

  bool get _dirty => _sp != _original;

  Future<void> _save() async {
    final err = _sp.validate();
    if (err != null) {
      showMessage(context, err);
      return;
    }
    setState(() => _saving = true);
    final result = await context.read<FarmState>().saveSetpoints(_sp);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result != null) {
      showMessage(context, result);
    } else {
      _original = _sp;
      showMessage(context, 'Saved. The controller will use the new targets.');
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your new targets have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Targets & thresholds')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _RangeCard(
              icon: Icons.water_drop,
              title: 'Humidity (mist maker)',
              help: 'Mist turns ON below the low value and OFF above the high value.',
              min: 50,
              max: 100,
              divisions: 50,
              values: RangeValues(_sp.humOn, _sp.humOff),
              label: (v) => '${v.round()}%',
              lowLabel: 'Mist ON below',
              highLabel: 'Mist OFF above',
              onChanged: (r) => setState(() =>
                  _sp = _sp.copyWith(humOn: r.start.roundToDouble(), humOff: r.end.roundToDouble())),
            ),
            const SizedBox(height: 12),
            _RangeCard(
              icon: Icons.co2,
              title: 'CO2 (exhaust fan)',
              help: 'Fan turns ON above the high value and OFF below the low value. '
                  'Fruiting needs under 800–1,000 ppm.',
              min: 400,
              max: 6000,
              divisions: 112,
              values: RangeValues(_sp.co2Off.toDouble(), _sp.co2On.toDouble()),
              label: (v) => '${v.round()} ppm',
              lowLabel: 'Fan OFF below',
              highLabel: 'Fan ON above',
              onChanged: (r) => setState(
                  () => _sp = _sp.copyWith(co2Off: r.start.round(), co2On: r.end.round())),
            ),
            const SizedBox(height: 12),
            _RangeCard(
              icon: Icons.thermostat,
              title: 'Temperature alert',
              help: 'The app warns you outside this range. The controller has no heater '
                  'or cooler, so this is an alert only.',
              min: 10,
              max: 40,
              divisions: 60,
              values: RangeValues(_sp.tempMin, _sp.tempMax),
              label: (v) => '${v.toStringAsFixed(1)} °C',
              lowLabel: 'Too cold below',
              highLabel: 'Too hot above',
              onChanged: (r) =>
                  setState(() => _sp = _sp.copyWith(tempMin: r.start, tempMax: r.end)),
            ),
            const SizedBox(height: 16),
            Text('Stage: ${_sp.stage.label}', style: t.bodySmall, textAlign: TextAlign.center),
            TextButton.icon(
              onPressed: () => setState(() => _sp = Setpoints.preset(_sp.stage)),
              icon: const Icon(Icons.restart_alt),
              label: Text('Reset to ${_sp.stage.label} defaults'),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: _dirty && !_saving ? _save : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_dirty ? 'Save changes' : 'No changes'),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeCard extends StatelessWidget {
  const _RangeCard({
    required this.icon,
    required this.title,
    required this.help,
    required this.min,
    required this.max,
    required this.divisions,
    required this.values,
    required this.label,
    required this.lowLabel,
    required this.highLabel,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String help;
  final double min;
  final double max;
  final int divisions;
  final RangeValues values;
  final String Function(double) label;
  final String lowLabel;
  final String highLabel;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final v = RangeValues(values.start.clamp(min, max), values.end.clamp(min, max));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: t.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text(help, style: t.bodySmall),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Value(lowLabel, label(v.start))),
              Expanded(child: _Value(highLabel, label(v.end), end: true)),
            ]),
            RangeSlider(
              min: min,
              max: max,
              divisions: divisions,
              values: v,
              labels: RangeLabels(label(v.start), label(v.end)),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.caption, this.value, {this.end = false});
  final String caption;
  final String value;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(caption, style: t.labelMedium),
        Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
