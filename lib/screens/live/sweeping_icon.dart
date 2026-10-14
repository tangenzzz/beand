import 'package:flutter/material.dart';

// An icon whose fill lights up in one direction: the glow starts at the
// beginning of the drawing, grows to its end and then starts over. Meant
// for the arrows of the command row (Purge/Raise) while the machine is
// actually performing the movement.
//
// The tempo is deliberately the same as the breathing start button
// (PulsingGlow, 1100 ms), so the app has only one speed.
class SweepingIcon extends StatefulWidget {
  const SweepingIcon({
    super.key,
    required this.icon,
    required this.active,
    required this.baseColor,
    required this.glowColor,
    required this.direction,
    this.size = 24,
    this.inset = defaultInset,
  });

  // Material symbols have padding inside: the arrow does not fill its box
  // to the edge. Without this inset the glow would start before the drawing
  // and stop short of the tip. The value is set by eye, not read from the
  // font file — so adjust it for a different icon if needed.
  static const defaultInset = 2 / 24;

  // Soft edge ahead of the glow, so it moves instead of switching.
  static const feather = 0.3;

  final IconData icon;
  // At rest the normal icon is simply drawn, without a ticker.
  final bool active;
  final Color baseColor;
  final Color glowColor;
  // From the start of the drawing to its end — for an arrow, its pointing
  // direction: arrow_downward runs down, arrow_upward runs up.
  final AxisDirection direction;
  final double size;
  final double inset;

  // The gradient math lives in a pure function so a test can recompute it
  // frame by frame — the stops can no longer be extracted from a finished
  // shader. [t] runs from 0 (nothing lit) to 1 (up to the tip).
  @visibleForTesting
  static LinearGradient gradientFor({
    required double t,
    required AxisDirection direction,
    required Color baseColor,
    required Color glowColor,
    double inset = defaultInset,
  }) {
    final (begin, end) = switch (direction) {
      AxisDirection.down => (Alignment.topCenter, Alignment.bottomCenter),
      AxisDirection.up => (Alignment.bottomCenter, Alignment.topCenter),
      AxisDirection.right => (Alignment.centerLeft, Alignment.centerRight),
      AxisDirection.left => (Alignment.centerRight, Alignment.centerLeft),
    };
    final span = 1 - 2 * inset;
    final lead = (inset + t.clamp(0.0, 1.0) * span).clamp(0.0, 1.0);
    final tail = (lead - feather).clamp(0.0, 1.0);
    return LinearGradient(
      begin: begin,
      end: end,
      colors: [glowColor, glowColor, baseColor, baseColor],
      // The stops must ascend, even in the first frame (lead == tail).
      stops: [0, tail, (tail + 0.001).clamp(lead, 1.0), 1],
    );
  }

  @override
  State<SweepingIcon> createState() => _SweepingIconState();
}

class _SweepingIconState extends State<SweepingIcon>
    with SingleTickerProviderStateMixin {
  // A sweep takes 1100 ms like a pulse beat, then the arrow stays fully lit
  // briefly before starting over — without this hold the jump back to dark
  // looks like a stutter.
  static const _cycle = Duration(milliseconds: 1300);
  static const _sweepFraction = 1100 / 1300;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  );
  late final Animation<double> _sweep = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, _sweepFraction, curve: Curves.easeInOut),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant SweepingIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(widget.icon, size: widget.size, color: widget.baseColor);
    if (!widget.active) return icon;
    return AnimatedBuilder(
      animation: _sweep,
      // The mask colors the drawing (srcIn only takes its coverage); the
      // icon's own color underneath no longer matters.
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => SweepingIcon.gradientFor(
          t: _sweep.value,
          direction: widget.direction,
          baseColor: widget.baseColor,
          glowColor: widget.glowColor,
          inset: widget.inset,
        ).createShader(rect),
        child: child,
      ),
      child: icon,
    );
  }
}
