import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../logic/alerts.dart';
import '../../state/farm_state.dart';
import '../theme.dart';

/// "● Online · 3 s ago" / "● Offline" status for app bars.
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
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.fromLTRB(2, 5, 10, 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(color: color, size: 7),
            Text(text,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkDim)),
          ],
        ),
      ),
    );
  }
}

/// Small "Demo" tag shown next to page titles while in demo mode.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    if (!s.repo.isDemo) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.ochre.withValues(alpha: 0.6)),
      ),
      child: const Text('Demo',
          style: TextStyle(fontSize: 11, color: AppColors.ochre, fontWeight: FontWeight.w700)),
    );
  }
}

/// App bar title with the demo tag.
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
