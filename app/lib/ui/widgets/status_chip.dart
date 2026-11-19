import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../logic/alerts.dart';
import '../../state/farm_state.dart';
import '../theme.dart';

/// "● Online · 3 s ago" / "● Offline" pill for app bars.
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
        padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseDot(color: color, size: 7, animate: sev == Severity.ok),
            Text(text,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Small "DEMO" badge shown next to page titles while in demo mode.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    if (!s.repo.isDemo) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppColors.aiGradient,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('DEMO',
          style: TextStyle(
              fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
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
