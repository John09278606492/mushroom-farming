import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/farm_models.dart';
import '../state/farm_state.dart';
import 'theme.dart';

/// Sprinkler and grow-light schedules (up to 5 each, run by the controller's RTC).
class SchedulesScreen extends StatelessWidget {
  const SchedulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AiScaffold(
      appBar: AppBar(title: const Text('Schedules')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'The controller follows these using its own clock, even without internet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final d in ScheduleDevice.values) _DeviceSchedules(d),
        ],
      ),
    );
  }
}

class _DeviceSchedules extends StatelessWidget {
  const _DeviceSchedules(this.device);
  final ScheduleDevice device;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final slots = s.schedules[device]!;
    final used = [for (var i = 0; i < slots.length; i++) if (slots[i] != null) i];
    final free = [for (var i = 0; i < slots.length; i++) if (slots[i] == null) i];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          device.label,
          trailing: TextButton.icon(
            onPressed: free.isEmpty
                ? null
                : () => _edit(context, device, free.first, Schedule.newFor(device), isNew: true),
            icon: const Icon(Icons.add),
            label: Text(free.isEmpty ? 'Max $maxScheduleSlots' : 'Add'),
          ),
        ),
        Card(
          child: used.isEmpty
              ? ListTile(
                  leading: Icon(device.icon),
                  title: const Text('No schedule'),
                  subtitle: const Text('Tap Add to run it at set times.'),
                )
              : Column(children: [
                  for (final (n, i) in used.indexed) ...[
                    if (n > 0) const Divider(height: 1, indent: 16),
                    _SlotTile(device: device, slot: i, schedule: slots[i]!),
                  ],
                ]),
        ),
      ],
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.device, required this.slot, required this.schedule});
  final ScheduleDevice device;
  final int slot;
  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final s = context.read<FarmState>();
    return ListTile(
      leading: Icon(device.icon),
      title: Text('${formatClock(schedule.hour, schedule.minute)} · '
          '${schedule.duration} ${device.unit}'),
      subtitle: Text(schedule.enabled ? schedule.daysLabel : 'Off · ${schedule.daysLabel}'),
      onTap: () => _edit(context, device, slot, schedule),
      trailing: Switch(
        value: schedule.enabled,
        onChanged: (v) async {
          final err = await s.saveSchedule(device, slot, schedule.copyWith(enabled: v));
          if (err != null && context.mounted) showMessage(context, err);
        },
      ),
    );
  }
}

Future<void> _edit(BuildContext context, ScheduleDevice device, int slot, Schedule initial,
    {bool isNew = false}) async {
  final state = context.read<FarmState>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScheduleEditor(
      device: device,
      initial: initial,
      isNew: isNew,
      onSave: (sch) => state.saveSchedule(device, slot, sch),
      onDelete: isNew ? null : () => state.saveSchedule(device, slot, null),
    ),
  );
}

class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({
    required this.device,
    required this.initial,
    required this.isNew,
    required this.onSave,
    required this.onDelete,
  });

  final ScheduleDevice device;
  final Schedule initial;
  final bool isNew;
  final Future<String?> Function(Schedule) onSave;
  final Future<String?> Function()? onDelete;

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late Schedule _s = widget.initial;
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action, String done) async {
    setState(() => _busy = true);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    showMessage(context, err ?? done);
    if (err == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = widget.device;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${widget.isNew ? 'New' : 'Edit'} ${d.label.toLowerCase()} schedule',
              style: t.titleLarge),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: _s.hour, minute: _s.minute),
                  );
                  if (picked != null) {
                    setState(() => _s = _s.copyWith(hour: picked.hour, minute: picked.minute));
                  }
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                icon: const Icon(Icons.schedule),
                label: Text('Start ${formatClock(_s.hour, _s.minute)}', style: t.titleMedium),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Run for', style: t.titleMedium)),
            IconButton.filledTonal(
              onPressed: _s.duration > 1
                  ? () => setState(() => _s = _s.copyWith(duration: _s.duration - 1))
                  : null,
              icon: const Icon(Icons.remove),
              tooltip: 'Shorter',
            ),
            SizedBox(
              width: 72,
              child: Text('${_s.duration} ${d.unit}',
                  textAlign: TextAlign.center, style: t.titleMedium),
            ),
            IconButton.filledTonal(
              onPressed: _s.duration < d.maxDuration
                  ? () => setState(() => _s = _s.copyWith(duration: _s.duration + 1))
                  : null,
              icon: const Icon(Icons.add),
              tooltip: 'Longer',
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Days', style: t.titleMedium)),
            TextButton(
              onPressed: () => setState(() => _s = _s.copyWith(days: List.filled(7, true))),
              child: const Text('Every day'),
            ),
            TextButton(
              onPressed: () => setState(() => _s = _s.copyWith(
                  days: [false, true, true, true, true, true, false])),
              child: const Text('Mon–Fri'),
            ),
          ]),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < 7; i++)
                FilterChip(
                  label: Text(dayShortNames[i]),
                  selected: _s.days[i],
                  showCheckmark: false,
                  onSelected: (v) {
                    final days = List<bool>.of(_s.days)..[i] = v;
                    setState(() => _s = _s.copyWith(days: days));
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            value: _s.enabled,
            onChanged: (v) => setState(() => _s = _s.copyWith(enabled: v)),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy || !_s.days.contains(true)
                ? null
                : () => _run(() => widget.onSave(_s), 'Schedule saved.'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_s.days.contains(true) ? 'Save' : 'Pick at least one day'),
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : () => _run(widget.onDelete!, 'Schedule deleted.'),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete schedule'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
