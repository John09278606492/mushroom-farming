import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// A 270° ring gauge with a glowing gradient arc.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.fraction,
    required this.colors,
    required this.child,
    this.size = 112,
    this.stroke = 10,
    this.targetFrom,
    this.targetTo,
  });

  /// 0..1, or null when there is no reading (empty ring).
  final double? fraction;
  final List<Color> colors;
  final Widget child;
  final double size;
  final double stroke;

  /// Optional target band (0..1) drawn as a faint arc on the track.
  final double? targetFrom;
  final double? targetTo;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: (fraction ?? 0).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(
            value: fraction == null ? null : v,
            colors: colors,
            stroke: stroke,
            targetFrom: targetFrom,
            targetTo: targetTo,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.colors,
    required this.stroke,
    this.targetFrom,
    this.targetTo,
  });

  final double? value;
  final List<Color> colors;
  final double stroke;
  final double? targetFrom;
  final double? targetTo;

  static const _start = 135 * pi / 180;
  static const _sweep = 270 * pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 4);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.glassStrong;
    canvas.drawArc(arcRect, _start, _sweep, false, track);

    if (targetFrom != null && targetTo != null) {
      final band = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = Colors.white.withValues(alpha: 0.10);
      final a = targetFrom!.clamp(0.0, 1.0);
      final b = targetTo!.clamp(0.0, 1.0);
      if (b > a) canvas.drawArc(arcRect, _start + _sweep * a, _sweep * (b - a), false, band);
    }

    final v = value;
    if (v == null || v <= 0) return;

    final shader = SweepGradient(
      startAngle: 0,
      endAngle: _sweep,
      colors: colors,
      transform: const GradientRotation(_start),
    ).createShader(arcRect);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 6
      ..strokeCap = StrokeCap.round
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawArc(arcRect, _start, _sweep * v, false, glow);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawArc(arcRect, _start, _sweep * v, false, arc);

    // Bright tip.
    final angle = _start + _sweep * v;
    final c = arcRect.center;
    final r = arcRect.width / 2;
    final tip = Offset(c.dx + r * cos(angle), c.dy + r * sin(angle));
    canvas.drawCircle(tip, stroke / 2.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.colors != colors ||
      old.targetFrom != targetFrom ||
      old.targetTo != targetTo;
}
