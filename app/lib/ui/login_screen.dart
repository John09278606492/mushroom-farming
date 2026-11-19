import 'package:material_ui/material_ui.dart';

import '../data/auth_service.dart';
import 'theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.onDemo});

  /// Null when Firebase is not configured in this build (demo only).
  final AuthService? auth;
  final VoidCallback onDemo;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.auth!.signIn(_email.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Type your email first, then tap "Forgot password".');
      return;
    }
    final err = await widget.auth!.sendPasswordReset(_email.text);
    if (mounted) showMessage(context, err ?? 'Password reset email sent.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final firebaseReady = widget.auth != null;

    return AiScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: _Orb()),
                    const SizedBox(height: 22),
                    const Center(
                      child: GradientText('Smart Mushroom Farm',
                          gradient: AppColors.aiGradientWide,
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    ),
                    const SizedBox(height: 6),
                    const Text('Intelligent grow-room monitoring and control',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                    const SizedBox(height: 32),
                    if (!firebaseReady)
                      const GlassCard(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.cloud_off, color: AppColors.cyan, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This build is not connected to Firebase yet, so sign-in is off. '
                              'You can still try the app in demo mode.\n\n'
                              'Setup steps: app/README.md',
                              style: TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.4),
                            ),
                          ),
                        ]),
                      )
                    else ...[
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                        validator: (v) =>
                            (v == null || !v.contains('@')) ? 'Enter your email' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _hidePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _busy ? null : _signIn(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _hidePassword ? 'Show password' : 'Hide password',
                            icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _hidePassword = !_hidePassword),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: t.bodyMedium?.copyWith(color: scheme.error)),
                      ],
                      const SizedBox(height: 20),
                      GradientButton(
                        label: 'Sign in',
                        icon: Icons.login,
                        busy: _busy,
                        onPressed: _signIn,
                      ),
                      TextButton(onPressed: _busy ? null : _reset, child: const Text('Forgot password?')),
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: t.bodySmall),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 16),
                    if (firebaseReady)
                      OutlinedButton.icon(
                        onPressed: widget.onDemo,
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Try demo mode'),
                      )
                    else
                      GradientButton(
                        label: 'Try demo mode',
                        icon: Icons.science_outlined,
                        onPressed: widget.onDemo,
                      ),
                    const SizedBox(height: 8),
                    Text('A simulated farm. Nothing real is controlled.',
                        textAlign: TextAlign.center, style: t.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glowing logo with a slowly rotating gradient ring.
class _Orb extends StatefulWidget {
  const _Orb();

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 112,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
            BoxShadow(color: AppColors.violet.withValues(alpha: 0.45), blurRadius: 40),
            BoxShadow(color: AppColors.cyan.withValues(alpha: 0.25), blurRadius: 60, spreadRadius: 6),
          ]),
        ),
        RotationTransition(
          turns: _c,
          child: Container(
            width: 104,
            height: 104,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [AppColors.cyan, AppColors.violet, AppColors.pink, AppColors.cyan],
              ),
            ),
          ),
        ),
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bg1),
          child: const Icon(Icons.spa, size: 46, color: AppColors.cyan),
        ),
      ]),
    );
  }
}
