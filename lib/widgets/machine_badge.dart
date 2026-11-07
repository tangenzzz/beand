import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// The badge that assigns a shot in the History to its machine.
//
// Rounded square in the machine's color, glyph dark. A square instead of a
// circle because it stands apart from the round profile images and leaves
// more room for the letter at the same width.
//
// It is shown at 17 px, the glyph inside about 11 px. At that size little
// works: Meticulous therefore gets its initial, GaggiMate "GM" cut from its
// wordmark (bold G of GAGGI, thin M of MATE, as in the Home pill; used with
// permission), Pour Over a V60 dripper in thick lines: rim, cone, handle and
// foot. Thinner lines disappear at 17 px.
enum MachineGlyph { letterM, gaggiMate, v60 }

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
      child: switch (glyph) {
        MachineGlyph.v60 => CustomPaint(
          size: Size.square(size),
          painter: const _V60Painter(_glyphColor),
        ),
        // Two letters side by side: as wide as the inner area allows.
        MachineGlyph.gaggiMate => SvgPicture.asset(
          'assets/gaggimate/badge_gm.svg',
          width: size * 0.66,
          semanticsLabel: 'GaggiMate',
          colorFilter: const ColorFilter.mode(_glyphColor, BlendMode.srcIn),
        ),
        MachineGlyph.letterM => Text(
          'M',
          style: TextStyle(
            color: _glyphColor,
            fontSize: size * 0.66,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      },
    );
  }
}

// V60 dripper, drawn on a 100 grid that fills the badge.
class _V60Painter extends CustomPainter {
  const _V60Painter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        // Rim.
        ..moveTo(16, 27)
        ..lineTo(78, 27)
        // Cone.
        ..moveTo(20, 28)
        ..lineTo(39, 66)
        ..lineTo(57, 66)
        ..lineTo(75, 28)
        // Handle.
        ..moveTo(75, 36)
        ..cubicTo(84, 32, 91, 36, 90, 43)
        ..cubicTo(89, 50, 79, 55, 66, 57)
        // Foot.
        ..moveTo(27, 74)
        ..lineTo(69, 74),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _V60Painter old) => old.color != color;
}
