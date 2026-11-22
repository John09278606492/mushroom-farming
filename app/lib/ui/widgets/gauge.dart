import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// A thin horizontal scale: the target band is shaded and a dot marks the
/// current reading. Reads like a field instrument rather than a dial.
class RangeBar extends StatelessWidget {
  const RangeBar({
    super.key,
    required this.fraction,
    required this.color,
    this.targetFrom,
    this.targetTo,
  });

  /// 0..1, or null when there is no reading.
  final double? fraction;
  final Color color;
  final double? targetFrom;
  final double? targetTo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: (fraction ?? 0).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RangePainter(
            value: fraction == null ? null : v,
            color: color,
            from: targetFrom,
            to: targetTo,
          ),
        ),
      ),
    );
  }
}

class _RangePainter extends CustomPainter {
  _RangePainter({required this.value, required this.color, this.from, this.to});

  final double? value;
  final Color color;
  final double? from;
  final double? to;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 6.0;
    const r = 7.0; // marker radius
    final y = size.height / 2;
    const left = r;
    final width = size.width - r * 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, y - h / 2, width, h), const Radius.circular(h / 2)),
      Paint()..color = AppColors.track,
    );

    if (from != null && to != null) {
      final a = from!.clamp(0.0, 1.0);
      final b = to!.clamp(0.0, 1.0);
      if (b > a) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left + width * a, y - h / 2, width * (b - a), h),
            const Radius.circular(h / 2),
          ),
          Paint()..color = color.withValues(alpha: 0.30),
        );
      }
    }

    final v = value;
    if (v == null) return;
    final c = Offset(left + width * v, y);
    canvas.drawCircle(c, r, Paint()..color = AppColors.surface);
    canvas.drawCircle(c, r - 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.value != value || old.color != color || old.from != from || old.to != to;
}
