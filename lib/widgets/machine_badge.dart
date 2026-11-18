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
// permission), Pour Over a filled V60 dripper with rim and foot, Espresso
// (a machine the app does not talk to) a filled portafilter. Thin lines
// disappear at 17 px.
enum MachineGlyph { letterM, gaggiMate, v60, portafilter }

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
        MachineGlyph.portafilter => CustomPaint(
          size: Size.square(size),
          painter: const _PortafilterPainter(_glyphColor),
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
    final paint = Paint()..color = color;
    // Rim.
    canvas.drawRRect(
      RRect.fromLTRBR(17, 24, 83, 32, const Radius.circular(4)),
      paint,
    );
    // Cone with its tip cut off.
    canvas.drawPath(
      Path()
        ..moveTo(22, 32)
        ..lineTo(78, 32)
        ..lineTo(59, 68)
        ..lineTo(41, 68)
        ..close(),
      paint,
    );
    // Foot, right under the cone.
    canvas.drawRRect(
      RRect.fromLTRBR(27.6, 67, 72.4, 77, const Radius.circular(3)),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _V60Painter old) => old.color != color;
}

// Portafilter seen from the side (user's draft 2026-11-07, cream on the
// left): basket with its two ears, short neck and a handle that widens to a
// round end. Filled throughout, on the same 100 grid as the V60.
class _PortafilterPainter extends CustomPainter {
  const _PortafilterPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100);
    // Wider than tall: a little smaller so it keeps off the badge's edges.
    canvas.translate(4, 4);
    canvas.scale(0.92);
    final paint = Paint()..color = color;
    // Basket: flat top, rounded bottom.
    canvas.drawPath(
      Path()
        ..moveTo(11, 38)
        ..lineTo(51, 38)
        ..lineTo(50, 57)
        ..quadraticBezierTo(49, 67, 40, 67)
        ..lineTo(22, 67)
        ..quadraticBezierTo(13, 67, 12, 57)
        ..close(),
      paint,
    );
    // Rim, a little wider than the basket.
    canvas.drawRRect(
      RRect.fromLTRBR(8, 33, 54, 41, const Radius.circular(4)),
      paint,
    );
    // Ears on both sides of the rim.
    canvas.drawRRect(
      RRect.fromLTRBR(4, 34, 10, 45, const Radius.circular(2.5)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(52, 34, 58, 45, const Radius.circular(2.5)),
      paint,
    );
    // Neck between basket and handle.
    canvas.drawRect(const Rect.fromLTRB(56, 43, 64, 55), paint);
    // Handle: narrow at the neck, wide and round at the end.
    canvas.drawPath(
      Path()
        ..moveTo(62, 42)
        ..lineTo(84, 36)
        ..arcToPoint(const Offset(84, 62), radius: const Radius.circular(13))
        ..lineTo(62, 56)
        ..close(),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PortafilterPainter old) => old.color != color;
}
