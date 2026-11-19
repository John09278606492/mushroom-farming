import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/alerts.dart';
import '../models/farm_models.dart';
import '../state/farm_state.dart';
import 'theme.dart';
import 'widgets/status_chip.dart';

/// Oyster mushrooms are usually ready 5–7 days after pinning (handoff.md §6).
const readyFromDay = 5;
const readyToDay = 7;

class HarvestScreen extends StatelessWidget {
  const HarvestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final past = s.batches.where((b) => !b.isOpen).toList();
    return AiScaffold(
      appBar: AppBar(title: const PageTitle('Harvest'), actions: const [ConnectionChip()]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _CameraCard(),
          const SectionTitle('Current batch'),
          const _BatchCard(),
          if (past.isNotEmpty) ...[
            const SectionTitle('Past harvests'),
            Card(
              child: Column(children: [
                for (final (i, b) in past.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(b.weightG != null
                        ? '${(b.weightG! / 1000).toStringAsFixed(2)} kg'
                        : 'No weight logged'),
                    subtitle: Text([
                      'Pinned ${formatDate(b.pinnedAt)}',
                      'harvested ${formatDate(b.harvestedAt!)} '
                          '(day ${b.harvestedAt!.difference(b.pinnedAt).inDays + 1})',
                      if (b.notes.isNotEmpty) b.notes,
                    ].join(' · ')),
                  ),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final shot = s.camera;
    final result = s.harvest;
    final t = Theme.of(context).textTheme;

    return GlassCard(
      gradientBorder: true,
      glow: AppColors.cyan,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(children: [
              const Icon(Icons.center_focus_strong, color: AppColors.cyan, size: 20),
              const SizedBox(width: 8),
              const GradientText('AI Harvest Vision',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (shot != null)
                Text(timeAgo(shot.ts, s.now),
                    style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
            ]),
          ),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: shot == null
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.cyan.withValues(alpha: 0.08), AppColors.violet.withValues(alpha: 0.10)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_camera_outlined, size: 48, color: AppColors.cyan.withValues(alpha: 0.7)),
                        const SizedBox(height: 8),
                        const Text('No photo yet'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          child: Text(
                            'The grow room camera uploads a photo every 1–2 hours.',
                            textAlign: TextAlign.center,
                            style: t.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: () => _openFull(context, shot),
                    child: Image.memory(shot.jpeg, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (shot != null)
                  Text('Photo taken ${timeAgo(shot.ts, s.now)} (${formatDateTime(shot.ts)})',
                      style: t.bodySmall),
                const SizedBox(height: 6),
                if (result == null)
                  Text('AI harvest check: waiting for the first result.', style: t.bodyMedium)
                else
                  _ResultRow(result),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openFull(BuildContext context, CameraShot shot) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(formatDateTime(shot.ts)),
        ),
        body: InteractiveViewer(child: Center(child: Image.memory(shot.jpeg))),
      ),
    ));
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(this.result);
  final HarvestResult result;

  @override
  Widget build(BuildContext context) {
    final sev = switch (result.label) {
      HarvestLabel.ready => Severity.ok,
      HarvestLabel.overMature => Severity.critical,
      _ => Severity.info,
    };
    final color = sev.color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
      Icon(sev == Severity.ok ? Icons.celebration : sev.icon, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(result.label.label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ),
      Text('${(result.confidence * 100).round()}% sure',
          style: Theme.of(context).textTheme.bodySmall),
    ]),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final batch = s.openBatch;
    final t = Theme.of(context).textTheme;

    if (batch == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No batch running', style: t.titleMedium),
              const SizedBox(height: 4),
              Text(
                'When you see the first pins (tiny mushrooms), tap the button. '
                'The app will count the days and remind you when to harvest.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 12),
              GradientButton(
                onPressed: () async {
                  final err = await s.startBatch();
                  if (context.mounted) showMessage(context, err ?? 'Pinning day saved.');
                },
                icon: Icons.spa,
                label: 'Pinning started today',
              ),
            ],
          ),
        ),
      );
    }

    final day = batch.dayNumber(s.now);
    final Severity sev;
    final String advice;
    if (day < readyFromDay) {
      sev = Severity.info;
      advice = 'Growing. Usually ready from day $readyFromDay '
          '(${readyFromDay - day} more day${readyFromDay - day == 1 ? '' : 's'}).';
    } else if (day <= readyToDay) {
      sev = Severity.ok;
      advice = 'Harvest window! Pick when caps are flat and the edges still curl down.';
    } else {
      sev = Severity.critical;
      advice = 'Past day $readyToDay. Harvest now before the edges curl up and drop spores.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                GradientText('Day $day',
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('since pinning', style: t.bodyMedium),
                ),
              ],
            ),
            Text('Pinned ${formatDate(batch.pinnedAt)}', style: t.bodySmall),
            const SizedBox(height: 12),
            _GlowBar(value: (day / readyToDay).clamp(0, 1).toDouble(), color: sev.color(context)),
            const SizedBox(height: 4),
            Row(children: [
              Text('Day 1', style: t.labelSmall),
              const Spacer(),
              Text('Ready day $readyFromDay–$readyToDay', style: t.labelSmall),
            ]),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(sev.icon, color: sev.color(context), size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(advice, style: t.bodyMedium)),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _harvestDialog(context, s, batch),
              icon: const Icon(Icons.agriculture),
              label: const Text('Mark as harvested'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _harvestDialog(BuildContext context, FarmState s, Batch batch) async {
    final weight = TextEditingController();
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Harvest logged'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: weight,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Weight (grams)', hintText: 'e.g. 1250'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await s.finishBatch(batch.id,
        weightG: double.tryParse(weight.text), notes: notes.text.trim());
    if (context.mounted) showMessage(context, err ?? 'Harvest saved. Nice work!');
  }
}

/// Rounded progress bar with a glowing gradient fill.
class _GlowBar extends StatelessWidget {
  const _GlowBar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return Stack(children: [
        Container(
          height: 10,
          decoration: BoxDecoration(
            color: AppColors.glassStrong,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        Container(
          height: 10,
          width: c.maxWidth * value,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.cyan, color]),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10)],
          ),
        ),
      ]);
    });
  }
}
