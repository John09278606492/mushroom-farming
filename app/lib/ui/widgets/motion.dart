import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// A number that glides to its new value instead of jumping.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.style,
    this.decimals = 0,
    this.placeholder = '--',
    this.duration = const Duration(milliseconds: 900),
  });

  final double? value;
  final TextStyle style;
  final int decimals;
  final String placeholder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null) return Text(placeholder, style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: v),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, x, _) => Text(x.toStringAsFixed(decimals), style: style),
    );
  }
}

/// Water that fills a box to [level] (0..1) with two slow, overlapping waves.
/// The level eases to new values and the surface keeps moving gently.
class LiquidFill extends StatefulWidget {
  const LiquidFill({
    super.key,
    required this.level,
    required this.color,
    this.child,
    this.borderRadius = 22,
  });

  final double? level;
  final Color color;
  final Widget? child;
  final double borderRadius;

  @override
  State<LiquidFill> createState() => _LiquidFillState();
}

class _LiquidFillState extends State<LiquidFill> with SingleTickerProviderStateMixin {
  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: (widget.level ?? 0).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeInOutCubic,
        builder: (context, level, child) => AnimatedBuilder(
          animation: _wave,
          builder: (context, child) => CustomPaint(
            painter: _WavePainter(level: level, phase: _wave.value, color: widget.color),
            child: child,
          ),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.level, required this.phase, required this.color});
  final double level;
  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (level <= 0) return;
    final base = size.height * (1 - level);
    void wave(double amp, double shift, double alpha, double length) {
      final path = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width + 1; x += 4) {
        final y = base + sin((x / size.width * 2 * pi * length) + (phase * 2 * pi) + shift) * amp;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
    }

    wave(6, 0, 0.16, 1.2);
    wave(4.5, pi * 0.8, 0.22, 0.9);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.level != level || old.phase != phase || old.color != color;
}

/// Round icon badge used on cards.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.color = AppColors.ink,
    this.background = AppColors.surfaceAlt,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: background),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}
