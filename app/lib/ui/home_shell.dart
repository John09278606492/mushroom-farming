import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../data/farm_repository.dart';
import '../state/farm_state.dart';
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

  @override
  void dispose() {
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

  @override
  void initState() {
    super.initState();
    _messages = context.read<FarmState>().messages.listen((m) {
      if (mounted) showMessage(context, m);
    });
  }

  @override
  void dispose() {
    _messages?.cancel();
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
          HarvestScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: alerts > 0,
              label: Text('$alerts'),
              child: const Icon(Icons.dashboard_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: alerts > 0,
              label: Text('$alerts'),
              child: const Icon(Icons.dashboard),
            ),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'History',
          ),
          const NavigationDestination(
            icon: Icon(Icons.spa_outlined),
            selectedIcon: Icon(Icons.spa),
            label: 'Harvest',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
