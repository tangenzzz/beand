import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The bean from the wordmark (the apostrophe in "bean'd") as an icon.
///
/// Geometry is measured from the wordmark: an ellipse tilted by 13° with an
/// axis ratio of 1.56 and a fold shaped like a double S, cut out of the
/// bean. Because the fold is cut out rather than painted over, the icon
/// works on any background.
class BeanIcon extends StatelessWidget {
  const BeanIcon({super.key, this.size = 24, this.color});

  final double size;

  /// Defaults to the color of the surrounding [IconTheme] — so the icon in
  /// the tab bar picks up active/inactive automatically.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).iconTheme.color ??
        AppColors.of(context).textPrimary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BeanPainter(resolved)),
    );
  }
}

// Semi-axes of the ellipse and points of the fold, normalized to the width
// of the bean in the wordmark. Origin is the center of the bean.
const _semiMajor = 0.709;
const _semiMinor = 0.455;
const _tiltRadians = 13 * math.pi / 180;
const _creaseWidth = 0.125;

// Center line of the fold, top to bottom. Point-symmetric about the center.
const _crease = <Offset>[
  Offset(-0.129, -0.629),
  Offset(-0.142, -0.540),
  Offset(-0.159, -0.450),
  Offset(-0.134, -0.361),
  Offset(-0.072, -0.271),
  Offset(0.000, -0.182),
  Offset(0.035, -0.092),
  Offset(0.003, -0.002),
  Offset(-0.035, 0.087),
  Offset(-0.002, 0.177),
  Offset(0.067, 0.266),
  Offset(0.132, 0.356),
  Offset(0.159, 0.445),
  Offset(0.144, 0.535),
  Offset(0.129, 0.624),
];

class _BeanPainter extends CustomPainter {
  const _BeanPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The tilted ellipse is taller than wide; scale to the shorter side so
    // nothing gets clipped.
    final halfWidth =
        _semiMinor * math.cos(_tiltRadians) +
        _semiMajor * math.sin(_tiltRadians);
    final halfHeight =
        _semiMajor * math.cos(_tiltRadians) +
        _semiMinor * math.sin(_tiltRadians);
    final scale = math.min(
      size.width / (2 * halfWidth),
      size.height / (2 * halfHeight),
    );

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    // The fold cut-out needs its own layer, otherwise it also erases what
    // lies behind the icon.
    canvas.saveLayer(
      Rect.fromCircle(center: Offset.zero, radius: halfHeight * 1.2),
      Paint(),
    );
    canvas.rotate(-_tiltRadians);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: 2 * _semiMinor,
        height: 2 * _semiMajor,
      ),
      Paint()..color = color,
    );
    // The fold stands upright in the image, not along the ellipse's axis.
    canvas.rotate(_tiltRadians);
    canvas.drawPath(
      _creasePath(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _creaseWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.clear,
    );
    canvas.restore();
    canvas.restore();
  }

  // Smooth curve through the measured points (Catmull-Rom as Bézier).
  Path _creasePath() {
    final path = Path()..moveTo(_crease.first.dx, _crease.first.dy);
    for (var i = 0; i < _crease.length - 1; i++) {
      final p0 = _crease[i == 0 ? 0 : i - 1];
      final p1 = _crease[i];
      final p2 = _crease[i + 1];
      final p3 = _crease[i + 2 >= _crease.length ? _crease.length - 1 : i + 2];
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_BeanPainter oldDelegate) => oldDelegate.color != color;
}
