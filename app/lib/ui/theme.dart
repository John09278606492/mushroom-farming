import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../logic/alerts.dart';

/// Smart-farm look: soft sage background, white rounded cards, a near-black
/// hero card and bottom bar, and lime as the one bright accent. Each kind of
/// reading keeps its own calm tone.
abstract final class AppColors {
  static const bg = Color(0xFFEEF0EA); // soft sage grey
  static const surface = Color(0xFFFFFFFF); // card
  static const surfaceAlt = Color(0xFFF3F4EF); // inset / pressed
  static const line = Color(0xFFE3E6DD); // hairline
  static const track = Color(0xFFE6E9E1); // empty bar / switch track
  static const ink = Color(0xFF121512);
  static const inkDim = Color(0xFF7A8075);

  static const night = Color(0xFF151916); // hero card, bottom bar
  static const nightSoft = Color(0xFF242A25);
  static const onNightDim = Color(0xFFA3AA9F);

  static const lime = Color(0xFFC8F04B); // accent
  static const primary = Color(0xFF151916); // buttons are near-black
  static const primarySoft = Color(0xFFEAF7C6);

  // states
  static const ok = Color(0xFF4F9A2E);
  static const ochre = Color(0xFFD08A1E);
  static const brick = Color(0xFFD1493A);

  // reading / device tones
  static const slate = Color(0xFF3B7DD8); // humidity, water
  static const clay = Color(0xFFE0773A); // temperature
  static const plum = Color(0xFF8C62C9); // CO2, exhaust fan
  static const mustard = Color(0xFFD9A400); // grow light
  static const teal = Color(0xFF2BA39B); // mist

  // Analytics zones (checked for colour-blind contrast as a set):
  // below target = slate, on target = leaf, above target = mustard.
  static const leaf = Color(0xFF2E7D4F);
}

const _tabular = [FontFeature.tabularFigures()];

/// Text style for big numbers (digits line up and do not jump around).
TextStyle numberStyle(double size, {Color color = AppColors.ink, FontWeight weight = FontWeight.w600}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.0,
      letterSpacing: -0.5,
      fontFeatures: _tabular,
    );

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.primary,
    secondary: AppColors.clay,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFF1DFD3),
    onSecondaryContainer: const Color(0xFF6B2E14),
    tertiary: AppColors.slate,
    tertiaryContainer: const Color(0xFFD9E5EF),
    onTertiaryContainer: const Color(0xFF173A55),
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkDim,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.bg,
    surfaceContainerHigh: AppColors.surfaceAlt,
    surfaceContainerHighest: AppColors.surfaceAlt,
    outline: const Color(0xFFB9B4A6),
    outlineVariant: AppColors.line,
    error: AppColors.brick,
  );

  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  const base = TextStyle(color: AppColors.ink);

  return ThemeData(
    colorScheme: scheme,
    brightness: Brightness.light,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.surface,
    dividerColor: AppColors.line,
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
    splashFactory: InkRipple.splashFactory,
    textTheme: TextTheme(
      headlineSmall: base.copyWith(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: base.copyWith(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: base.copyWith(fontSize: 15, height: 1.4),
      bodyMedium: base.copyWith(fontSize: 14, height: 1.4),
      bodySmall: const TextStyle(fontSize: 12.5, color: AppColors.inkDim, height: 1.35),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: AppColors.ink,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      iconColor: AppColors.inkDim,
      textColor: AppColors.ink,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: AppColors.primarySoft,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.inkDim,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.inkDim,
          )),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.track,
        disabledForegroundColor: AppColors.inkDim,
        shape: rounded,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: Color(0xFFD5D9CF)),
        backgroundColor: AppColors.surface,
        shape: rounded,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.ink : AppColors.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled)
            ? AppColors.inkDim
            : s.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.ink),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 12)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? AppColors.night
          : const Color(0xFF9CA396)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? AppColors.lime.withValues(alpha: s.contains(WidgetState.disabled) ? 0.45 : 1)
          : AppColors.track),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.transparent : const Color(0xFFD5D9CF)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.night,
      inactiveTrackColor: AppColors.track,
      thumbColor: AppColors.night,
      overlayColor: AppColors.primary.withValues(alpha: 0.12),
      valueIndicatorColor: AppColors.ink,
      valueIndicatorTextStyle: const TextStyle(color: Colors.white),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.track,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primarySoft,
      side: const BorderSide(color: AppColors.line),
      labelStyle: const TextStyle(color: AppColors.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Color(0xFFD5D9CF),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      prefixIconColor: AppColors.inkDim,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD5D9CF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD5D9CF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: AppColors.brick),
  );
}

/// Status colours.
extension SeverityColors on Severity {
  Color color(BuildContext context) => switch (this) {
        Severity.ok => AppColors.ok,
        Severity.info => AppColors.slate,
        Severity.warning => AppColors.ochre,
        Severity.critical => AppColors.brick,
      };

  Color background(BuildContext context) => color(context).withValues(alpha: 0.10);

  IconData get icon => switch (this) {
        Severity.ok => Icons.check_circle_outline,
        Severity.info => Icons.info_outline,
        Severity.warning => Icons.warning_amber_rounded,
        Severity.critical => Icons.error_outline,
      };
}

/// Page scaffold on the paper background.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: appBar,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// Flat card with a hairline border.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.radius = 22,
    this.fill,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? fill;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? AppColors.line),
    );
    return Material(
      color: fill ?? AppColors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Full-width main action button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? () {} : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
      ),
      child: busy
          ? const SizedBox.square(
              dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
              Text(label),
            ]),
    );
  }
}

/// Small solid status dot.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: EdgeInsets.symmetric(horizontal: size * 0.6),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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

/// Section heading used on list pages.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 26, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: -0.1,
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
