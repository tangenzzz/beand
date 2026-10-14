import 'package:flutter/material.dart';

// The badge that assigns a shot in the History to its machine.
//
// Rounded square in the machine's color, glyph dark. A square instead of a
// circle because it stands apart from the round profile images and leaves
// more room for the letter at the same width.
//
// It is shown at 17 px, the glyph inside about 11 px. At that size little
// works: Meticulous and GaggiMate therefore get their initial, Pour Over a
// V60 dripper — a letter would be arbitrary there, and of the motifs tried
// (kettle, ribbed cone, cone with foot) only the plain dripper with a rim
// survived 17 px.
enum MachineGlyph { letterM, letterG, v60 }

class MachineBadge extends StatelessWidget {
  const MachineBadge({
    super.key,
    required this.glyph,
    required this.color,
    this.size = 17,
    this.ringColor,
  });

  final MachineGlyph glyph;
  final Color color;
  final double size;

  // Border in the background color — sets the badge apart from the profile
  // image.
  final Color? ringColor;

  static const _glyphColor = Color(0xFF17171A);

  @override
  Widget build(BuildContext context) {
    final ring = ringColor;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.30),
        border: ring == null ? null : Border.all(color: ring, width: 2),
      ),
      alignment: Alignment.center,
      child: glyph == MachineGlyph.v60
          ? CustomPaint(
              size: Size.square(size * 0.62),
              painter: const _V60Painter(_glyphColor),
            )
          : Text(
              glyph == MachineGlyph.letterM ? 'M' : 'G',
              style: TextStyle(
                color: _glyphColor,
                fontSize: size * 0.66,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
    );
  }
}

// V60 dripper: wide rim, below it the cone with a narrow outlet. Dimensions
// in the 24 grid so they match the other icons.
class _V60Painter extends CustomPainter {
  const _V60Painter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final paint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromLTRBR(
        1.6 * u,
        3.4 * u,
        22.4 * u,
        6.8 * u,
        Radius.circular(1.6 * u),
      ),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(3.2 * u, 6.8 * u)
        ..lineTo(20.8 * u, 6.8 * u)
        ..lineTo(13.2 * u, 20.6 * u)
        ..lineTo(10.8 * u, 20.6 * u)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _V60Painter old) => old.color != color;
}
