import 'package:flutter/material.dart';

/// My Coffee Desk: a shelf with a jar and a cup. Color and size come from the
/// surrounding [IconTheme], as with [Icon].
class DeskIcon extends StatelessWidget {
  const DeskIcon({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(side),
        painter: _DeskPainter(theme.color ?? Colors.white),
      ),
    );
  }
}

// On a 24 grid, like the Material icons around it.
class _DeskPainter extends CustomPainter {
  const _DeskPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Frame and two shelves.
    canvas.drawPath(
      Path()
        ..moveTo(3, 3)
        ..lineTo(3, 21)
        ..moveTo(21, 3)
        ..lineTo(21, 21)
        ..moveTo(3, 9.5)
        ..lineTo(21, 9.5)
        ..moveTo(3, 16.5)
        ..lineTo(21, 16.5),
      paint,
    );
    // Jar on the upper shelf.
    canvas.drawRRect(
      RRect.fromLTRBR(13.5, 4, 17.5, 9.5, const Radius.circular(1)),
      paint,
    );
    // Cup on the lower one.
    canvas.drawPath(
      Path()
        ..moveTo(6.5, 11.5)
        ..lineTo(12, 11.5)
        ..lineTo(12, 13.5)
        ..arcToPoint(const Offset(9, 16.5), radius: const Radius.circular(3))
        ..arcToPoint(
          const Offset(6.5, 13.5),
          radius: const Radius.elliptical(2.5, 3),
        )
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DeskPainter old) => old.color != color;
}
