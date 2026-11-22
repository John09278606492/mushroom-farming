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

    return AppScaffold(
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
                    const Center(child: _Mark()),
                    const SizedBox(height: 20),
                    const Text('Mushroom Farm',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            color: AppColors.ink)),
                    const SizedBox(height: 6),
                    const Text('Grow room monitoring and control',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkDim, fontSize: 15)),
                    const SizedBox(height: 32),
                    if (!firebaseReady)
                      const Panel(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.cloud_off_outlined, color: AppColors.inkDim, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This build is not connected to Firebase yet, so sign-in is off. '
                              'You can still try the app in demo mode.\n\n'
                              'Setup steps: app/README.md',
                              style: TextStyle(color: AppColors.ink, fontSize: 13.5, height: 1.4),
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
                      PrimaryButton(
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
                      PrimaryButton(
                        label: 'Try demo mode',
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

/// The app mark: a mushroom drawn with plain shapes on a moss tile.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const CustomPaint(painter: _MushroomPainter()),
    );
  }
}

class _MushroomPainter extends CustomPainter {
  const _MushroomPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cream = Paint()..color = AppColors.lime;
    // stem
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.40, h * 0.46, w * 0.20, h * 0.32),
        Radius.circular(w * 0.08),
      ),
      cream,
    );
    // cap
    final cap = Path()
      ..moveTo(w * 0.18, h * 0.52)
      ..quadraticBezierTo(w * 0.20, h * 0.20, w * 0.50, h * 0.20)
      ..quadraticBezierTo(w * 0.80, h * 0.20, w * 0.82, h * 0.52)
      ..close();
    canvas.drawPath(cap, cream);
    // spots
    final spot = Paint()..color = AppColors.primary;
    canvas.drawCircle(Offset(w * 0.38, h * 0.36), w * 0.045, spot);
    canvas.drawCircle(Offset(w * 0.58, h * 0.31), w * 0.035, spot);
    canvas.drawCircle(Offset(w * 0.66, h * 0.44), w * 0.03, spot);
  }

  @override
  bool shouldRepaint(_MushroomPainter old) => false;
}
