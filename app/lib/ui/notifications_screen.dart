import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/alerts.dart';
import '../logic/notices.dart';
import '../state/farm_state.dart';
import 'home_shell.dart';
import 'theme.dart';
import 'widgets/status_chip.dart';

/// Bell for app bars, with the number of unread notices.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<FarmState, int>((s) => s.unread);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => pushFarmPage(context, const NotificationsScreen()),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 9 ? '9+' : '$unread'),
                backgroundColor: AppColors.brick,
                child: Icon(
                  unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                  size: 21,
                  color: AppColors.ink,
                  semanticLabel: 'Notifications, $unread unread',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FarmState>().markInboxRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FarmState>();
    final active = s.alerts.where((a) => a.severity.index >= Severity.warning.index).toList();
    return AppScaffold(
      appBar: AppBar(
        title: const PageTitle('Notifications'),
        actions: [
          if (s.inbox.isNotEmpty)
            TextButton(onPressed: s.clearInbox, child: const Text('Clear')),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const SectionTitle('Happening now'),
          if (active.isEmpty)
            const Panel(
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: AppColors.ok),
                SizedBox(width: 12),
                Expanded(child: Text('No problems right now.', style: TextStyle(fontWeight: FontWeight.w600))),
              ]),
            )
          else
            for (final a in active) ...[
              _NoticeTile(
                severity: a.severity,
                title: a.title,
                body: a.message,
                trailing: 'Now',
                highlight: true,
              ),
              const SizedBox(height: 8),
            ],
          const SectionTitle('Earlier'),
          if (s.inbox.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('Problems and recoveries show up here as they happen.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkDim)),
            )
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (i, n) in s.inbox.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 64),
                  _NoticeRow(n, now: s.now),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({
    required this.severity,
    required this.title,
    required this.body,
    required this.trailing,
    this.highlight = false,
  });
  final Severity severity;
  final String title;
  final String body;
  final String trailing;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = severity.color(context);
    return Panel(
      borderColor: highlight ? c.withValues(alpha: 0.45) : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Dot(severity: severity),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text(body, style: const TextStyle(color: AppColors.inkDim, fontSize: 13, height: 1.35)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(trailing, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow(this.n, {required this.now});
  final Notice n;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Dot(severity: n.resolved ? Severity.ok : n.severity),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 2),
            Text(n.body, style: const TextStyle(color: AppColors.inkDim, fontSize: 13, height: 1.35)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(timeAgo(n.at, now), style: const TextStyle(color: AppColors.inkDim, fontSize: 12)),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.severity});
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final c = severity.color(context);
    final icon = switch (severity) {
      Severity.critical => Icons.error_outline_rounded,
      Severity.warning => Icons.warning_amber_rounded,
      Severity.ok => Icons.check_rounded,
      Severity.info => Icons.info_outline_rounded,
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, size: 19, color: c),
    );
  }
}
