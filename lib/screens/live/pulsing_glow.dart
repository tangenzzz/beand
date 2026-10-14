import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// Gentle "press now" pulsing for the pre-shot/shot button (noticeable, but
// not too extreme) — slight scaling plus a softening glow, only while
// [active] is true.
//
// Scale and radius are deliberately kept small: the glow may extend beyond
// the button at most as far as the card's padding (14), otherwise the
// scrolling cards to the left and right clip it.
class PulsingGlow extends StatefulWidget {
  const PulsingGlow({
    super.key,
    required this.active,
    required this.color,
    required this.child,
    this.borderRadius = AppRadii.button,
  });

  final bool active;
  final Color color;
  final Widget child;
  final double borderRadius;

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PulsingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = widget.active ? _controller.value : 0.0;
        return Transform.scale(
          scale: 1.0 + t * 0.02,
          child: CustomPaint(
            painter: _GlowPainter(
              color: widget.color,
              strength: t,
              radius: widget.borderRadius,
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// The glow sits ON the edge, not behind the surface: since the buttons no
// longer have a fill, a normal drop shadow would shine through the button
// and look like an accent fill. Hence a softly drawn outline. At rest it is
// invisible.
class _GlowPainter extends CustomPainter {
  const _GlowPainter({
    required this.color,
    required this.strength,
    required this.radius,
  });

  final Color color;
  final double strength;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + strength * 2
        ..color = color.withValues(alpha: 0.25 + strength * 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + strength * 5),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.strength != strength || old.color != color || old.radius != radius;
}
