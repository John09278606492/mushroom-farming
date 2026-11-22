import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/farm_repository.dart';
import '../logic/notices.dart';
import '../services/notification_service.dart';
import '../state/farm_state.dart';
import 'analytics_screen.dart';
import 'charts_screen.dart';
import 'dashboard_screen.dart';
import 'harvest_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// Opens [page] as a new screen that can still read [FarmState] and [Session].
///
/// Routes live under the app's root Navigator, above [FarmScope], so the
/// providers have to be passed along explicitly.
Future<void> pushFarmPage(BuildContext context, Widget page) {
  final state = context.read<FarmState>();
  final session = context.read<Session>();
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => MultiProvider(
      providers: [
        Provider<Session>.value(value: session),
        ChangeNotifierProvider<FarmState>.value(value: state),
      ],
      child: page,
    ),
  ));
}

/// Who is using the app and how to leave.
class Session {
  const Session({required this.isDemo, required this.signOut, this.email});
  final bool isDemo;
  final String? email;
  final VoidCallback signOut;
}

/// Owns the repository + [FarmState] for one signed-in (or demo) session.
class FarmScope extends StatefulWidget {
  const FarmScope({super.key, required this.createRepository, required this.session});

  /// Called once; the scope owns and disposes the repository.
  final FarmRepository Function() createRepository;
  final Session session;

  @override
  State<FarmScope> createState() => _FarmScopeState();
}

class _FarmScopeState extends State<FarmScope> {
  late final FarmRepository _repo = widget.createRepository();
  late final FarmState _state = FarmState(_repo);
  late final StreamSubscription<Notice> _notices =
      _state.notices.listen(NotificationService.instance.show);

  @override
  void initState() {
    super.initState();
    _notices; // start forwarding alerts to the phone
    final n = NotificationService.instance;
    // Android 13+ and iOS ask once; a browser only asks after a tap (Settings).
    if (n.ready && !n.allowed && n.enabled && !kIsWeb) n.requestPermission();
  }

  @override
  void dispose() {
    _notices.cancel();
    _state.dispose();
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Session>.value(value: widget.session),
        ChangeNotifierProvider<FarmState>.value(value: _state),
      ],
      child: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription<String>? _messages;
  StreamSubscription<Notice>? _alerts;

  @override
  void initState() {
    super.initState();
    final s = context.read<FarmState>();
    _messages = s.messages.listen((m) {
      if (mounted) showMessage(context, m);
    });
    // When the system tray can't show it (browser without permission,
    // notifications off), still tell the user inside the app.
    _alerts = s.notices.listen((n) {
      final svc = NotificationService.instance;
      if (!mounted || (svc.canShow && svc.wants(n))) return;
      showMessage(context, '${n.title}. ${n.body}');
    });
  }

  @override
  void dispose() {
    _messages?.cancel();
    _alerts?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = context.select<FarmState, int>((s) => s.alerts.length);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          ChartsScreen(),
          AnalyticsScreen(),
          HarvestScreen(),
          SettingsScreen(),
        ],
      ),
      backgroundColor: AppColors.bg,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: _PillBar(
            index: _index,
            alerts: alerts,
            onSelect: (i) => setState(() => _index = i),
          ),
        ),
      ),
    );
  }
}

/// Floating black bottom bar. The selected tab grows into a lime pill with
/// its label; the others stay as icons.
class _PillBar extends StatelessWidget {
  const _PillBar({required this.index, required this.alerts, required this.onSelect});
  final int index;
  final int alerts;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.show_chart_rounded, 'History'),
    (Icons.insights_rounded, 'Analytics'),
    (Icons.eco_rounded, 'Harvest'),
    (Icons.tune_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.night,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(children: [
        for (var i = 0; i < _items.length; i++)
          Expanded(
            flex: i == index ? 2 : 1,
            child: _PillItem(
              icon: _items[i].$1,
              label: _items[i].$2,
              selected: i == index,
              badge: i == 0 ? alerts : 0,
              onTap: () => onSelect(i),
            ),
          ),
      ]),
    );
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const dur = Duration(milliseconds: 380);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: dur,
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? AppColors.lime : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              child: Icon(icon, size: 22, color: selected ? AppColors.night : AppColors.onNightDim),
            ),
            if (selected)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                          color: AppColors.night, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
