import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';

import 'data/auth_service.dart';
import 'data/demo_farm_repository.dart';
import 'data/firebase_farm_repository.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase not available, demo mode only: $e');
  }
  await NotificationService.instance.init();
  runApp(MushroomApp(firebaseReady: firebaseReady));
}

class MushroomApp extends StatelessWidget {
  const MushroomApp({super.key, required this.firebaseReady});
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Mushroom Farm',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: AppRoot(firebaseReady: firebaseReady),
    );
  }
}

/// Chooses between the login screen, the real farm and demo mode.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.firebaseReady});
  final bool firebaseReady;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _demo = false;
  late final AuthService? _auth =
      widget.firebaseReady ? AuthService(FirebaseAuth.instance) : null;
  late final Stream<User?>? _userStream = _auth?.watchUser();

  @override
  Widget build(BuildContext context) {
    if (_demo) {
      return FarmScope(
        key: const ValueKey('demo'),
        createRepository: DemoFarmRepository.new,
        session: Session(isDemo: true, signOut: () => setState(() => _demo = false)),
      );
    }
    final auth = _auth;
    final login = LoginScreen(auth: auth, onDemo: () => setState(() => _demo = true));
    if (auth == null) return login;

    return StreamBuilder<User?>(
      stream: _userStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const AppScaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return login;
        return FarmScope(
          key: ValueKey(user.uid),
          createRepository: FirebaseFarmRepository.new,
          session: Session(isDemo: false, email: user.email, signOut: auth.signOut),
        );
      },
    );
  }
}
