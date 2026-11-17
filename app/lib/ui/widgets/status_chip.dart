import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../logic/alerts.dart';
import '../../state/farm_state.dart';
import '../theme.dart';

/// "● Online · 3 s ago" / "● Offline" chip for app bars.
class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final String text;
    final Severity sev;
    if (!s.phoneConnected) {
      text = 'No internet';
      sev = Severity.critical;
    } else if (!s.liveLoaded || !s.live.hasData) {
      text = 'Waiting…';
      sev = Severity.info;
    } else if (s.online) {
      text = 'Online · ${timeAgo(s.live.updatedAt!, s.now)}';
      sev = Severity.ok;
    } else {
      text = 'Offline · ${timeAgo(s.live.updatedAt!, s.now)}';
      sev = Severity.critical;
    }
    final color = sev.color(context);
    return Semantics(
      label: 'Controller status: $text',
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sev.background(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 9, color: color),
            const SizedBox(width: 6),
            Text(text,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// Small "DEMO" badge shown in the app bar title while in demo mode.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    if (!s.repo.isDemo) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('DEMO',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onTertiaryContainer, fontWeight: FontWeight.bold)),
    );
  }
}

/// App bar title with the demo badge.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
      const DemoBadge(),
    ]);
  }
}
