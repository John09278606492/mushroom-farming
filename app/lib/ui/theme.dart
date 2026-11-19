import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../logic/alerts.dart';

/// "AI dashboard" look: deep navy background, glass cards, cyan→violet glow.
abstract final class AppColors {
  static const bg0 = Color(0xFF060914);
  static const bg1 = Color(0xFF0C1226);
  static const bg2 = Color(0xFF141C38);
  static const glass = Color(0x0FFFFFFF); // 6% white
  static const glassStrong = Color(0x1AFFFFFF); // 10% white
  static const glassBorder = Color(0x1FFFFFFF); // 12% white
  static const text = Color(0xFFE8ECFF);
  static const textDim = Color(0xFF8E97B8);

  static const cyan = Color(0xFF22D3EE);
  static const violet = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const green = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);
  static const red = Color(0xFFF87171);
  static const blue = Color(0xFF60A5FA);

  static const aiGradient = LinearGradient(
    colors: [cyan, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const aiGradientWide = LinearGradient(
    colors: [cyan, violet, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.violet,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.cyan,
    onPrimary: AppColors.bg0,
    secondary: AppColors.violet,
    onSecondary: Colors.white,
    tertiary: AppColors.pink,
    surface: AppColors.bg1,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textDim,
    surfaceContainerHighest: AppColors.bg2,
    outline: const Color(0xFF3A4366),
    outlineVariant: AppColors.glassBorder,
    error: AppColors.red,
    primaryContainer: const Color(0xFF123A4A),
    onPrimaryContainer: AppColors.cyan,
    tertiaryContainer: const Color(0xFF3B1F5C),
    onTertiaryContainer: const Color(0xFFD8C4FF),
    secondaryContainer: const Color(0xFF221A45),
    onSecondaryContainer: const Color(0xFFD8C4FF),
  );

  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

  return ThemeData(
    colorScheme: scheme,
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg0,
    canvasColor: AppColors.bg1,
    dividerColor: AppColors.glassBorder,
    dividerTheme: const DividerThemeData(color: AppColors.glassBorder, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: AppColors.text,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.glass,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      iconColor: AppColors.cyan,
      textColor: AppColors.text,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xE60A0F22),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: AppColors.cyan.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? AppColors.cyan : AppColors.textDim,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.cyan : AppColors.textDim,
          )),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.bg0,
        disabledBackgroundColor: AppColors.glassStrong,
        disabledForegroundColor: AppColors.textDim,
        shape: rounded,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.glassBorder),
        backgroundColor: AppColors.glass,
        shape: rounded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? AppColors.cyan.withValues(alpha: 0.18)
            : AppColors.glass),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled)
            ? AppColors.textDim
            : s.contains(WidgetState.selected)
                ? AppColors.cyan
                : AppColors.text),
        side: WidgetStateProperty.resolveWith((s) => BorderSide(
              color: s.contains(WidgetState.selected)
                  ? AppColors.cyan.withValues(alpha: 0.6)
                  : AppColors.glassBorder,
            )),
        shape: WidgetStatePropertyAll(rounded),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 12)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? Colors.white.withValues(alpha: s.contains(WidgetState.disabled) ? 0.7 : 1)
          : AppColors.textDim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? AppColors.cyan.withValues(alpha: s.contains(WidgetState.disabled) ? 0.35 : 0.9)
          : AppColors.glassStrong),
      trackOutlineColor: const WidgetStatePropertyAll(AppColors.glassBorder),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.cyan,
      inactiveTrackColor: AppColors.glassStrong,
      thumbColor: Colors.white,
      overlayColor: AppColors.cyan.withValues(alpha: 0.15),
      valueIndicatorColor: AppColors.violet,
      valueIndicatorTextStyle: const TextStyle(color: Colors.white),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.cyan,
      linearTrackColor: AppColors.glassStrong,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.glass,
      selectedColor: AppColors.cyan.withValues(alpha: 0.2),
      side: const BorderSide(color: AppColors.glassBorder),
      labelStyle: const TextStyle(color: AppColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bg2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.bg1,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: AppColors.textDim,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.bg2,
      contentTextStyle: const TextStyle(color: AppColors.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.glass,
      prefixIconColor: AppColors.textDim,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
      ),
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: AppColors.pink),
  );
}

/// Neon status colors.
extension SeverityColors on Severity {
  Color color(BuildContext context) => switch (this) {
        Severity.ok => AppColors.green,
        Severity.info => AppColors.cyan,
        Severity.warning => AppColors.amber,
        Severity.critical => AppColors.red,
      };

  Color background(BuildContext context) => color(context).withValues(alpha: 0.12);

  IconData get icon => switch (this) {
        Severity.ok => Icons.check_circle,
        Severity.info => Icons.info,
        Severity.warning => Icons.warning_amber_rounded,
        Severity.critical => Icons.error,
      };
}

/// A screen with the glowing gradient background. Use instead of [Scaffold].
class AiScaffold extends StatelessWidget {
  const AiScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.bg1, AppColors.bg0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          const _Glow(top: -140, right: -100, color: AppColors.violet, size: 360, alpha: 0.30),
          const _Glow(top: 260, left: -160, color: AppColors.cyan, size: 340, alpha: 0.14),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: appBar,
            body: body,
            bottomNavigationBar: bottomNavigationBar,
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({this.top, this.left, this.right, required this.color, required this.size, required this.alpha});
  final double? top;
  final double? left;
  final double? right;
  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass panel. [gradientBorder] gives the cyan→violet "AI" outline,
/// [glow] adds a soft colored shadow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.gradientBorder = false,
    this.glow,
    this.onTap,
    this.radius = 20,
    this.fill,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool gradientBorder;
  final Color? glow;
  final VoidCallback? onTap;
  final double radius;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final inner = Material(
      color: fill ?? (gradientBorder ? AppColors.bg1 : AppColors.glass),
      borderRadius: BorderRadius.circular(gradientBorder ? radius - 1.2 : radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    return Container(
      padding: gradientBorder ? const EdgeInsets.all(1.2) : EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: gradientBorder ? AppColors.aiGradientWide : null,
        border: gradientBorder ? null : Border.all(color: AppColors.glassBorder),
        boxShadow: glow == null
            ? null
            : [BoxShadow(color: glow!.withValues(alpha: 0.28), blurRadius: 28, spreadRadius: -6)],
      ),
      child: inner,
    );
  }
}

/// Text painted with the cyan→violet gradient.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style, this.gradient = AppColors.aiGradient});
  final String text;
  final TextStyle? style;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(Offset.zero & bounds.size),
      child: Text(text, style: style),
    );
  }
}

/// Big gradient call-to-action button.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.aiGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: AppColors.violet.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 54,
              child: Center(
                child: busy
                    ? const SizedBox.square(
                        dimension: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.2)),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dot that softly pulses (live indicator).
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8, this.animate = true});
  final Color color;
  final double size;
  final bool animate;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox.square(
      dimension: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(alignment: Alignment.center, children: [
          if (widget.animate)
            Container(
              width: s + s * 1.4 * _c.value,
              height: s + s * 1.4 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.45 * (1 - _c.value)),
              ),
            ),
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.7), blurRadius: 6)],
            ),
          ),
        ]),
      ),
    );
  }
}

String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

String formatClock(int hour, int minute) =>
    DateFormat.jm().format(DateTime(2000, 1, 1, hour, minute));

String formatDateTime(DateTime t) => DateFormat('MMM d, h:mm a').format(t);

String formatDate(DateTime t) => DateFormat('MMM d, yyyy').format(t);

/// Section header used on list pages.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.cyan, AppColors.violet],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                  fontSize: 13,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDim,
                )),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
