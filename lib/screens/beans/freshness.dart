import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// The ring fills over 2 months since roasting.
const freshnessRingDays = 60;
// Color stages: freshly roasted (still resting), best window, after that.
const freshnessRestingMaxDays = 7;
const freshnessPeakMaxDays = 28;

// The stages come from the theme: resting like the heating hero ring, best
// window like "connected", after that muted.
Color freshnessColor(BuildContext context, int days) {
  final colors = context.colors;
  if (days <= freshnessRestingMaxDays) return colors.heroRingHeating;
  if (days <= freshnessPeakMaxDays) return colors.success;
  return colors.textSecondary;
}

double freshnessProgress(int days) =>
    (days / freshnessRingDays).clamp(0.0, 1.0);

class FreshnessRing extends StatelessWidget {
  const FreshnessRing({super.key, required this.days, this.size = 40});

  final int days;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$days days since roast',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: freshnessProgress(days),
            color: freshnessColor(context, days),
            track: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
          child: Center(
            child: Text(
              '$days',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: days >= 100 ? 10 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Ring of a frozen bean: closed, gradient light blue ↔ white, a snowflake in
// the middle. The freshness ring only starts on thawing.
class FrozenRing extends StatelessWidget {
  const FrozenRing({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Frozen',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _FrozenRingPainter(
            ice: context.colors.ice,
            iceLight: context.colors.iceLight,
          ),
          child: Center(
            child: Icon(
              Icons.ac_unit,
              color: context.colors.ice,
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _FrozenRingPainter extends CustomPainter {
  const _FrozenRingPainter({required this.ice, required this.iceLight});

  final Color ice;
  final Color iceLight;

  @override
  void paint(Canvas canvas, Size size) {
    final arcRect = (Offset.zero & size).deflate(_RingPainter._stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _RingPainter._stroke
      ..shader = SweepGradient(colors: [ice, iceLight, ice, iceLight, ice])
          .createShader(arcRect);
    canvas.drawArc(arcRect, 0, math.pi * 2, false, paint);
  }

  @override
  bool shouldRepaint(_FrozenRingPainter old) =>
      old.ice != ice || old.iceLight != iceLight;
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;

  /// The unfilled track behind the progress.
  final Color track;

  static const _stroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

// Small color legend for the ring (in the form below the roast date).
class FreshnessLegend extends StatelessWidget {
  const FreshnessLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _LegendItem(
          freshnessColor(context, 0),
          'Resting · up to $freshnessRestingMaxDays d',
        ),
        _LegendItem(
          freshnessColor(context, freshnessRestingMaxDays + 1),
          'Peak · ${freshnessRestingMaxDays + 1}–$freshnessPeakMaxDays d',
        ),
        _LegendItem(
          freshnessColor(context, freshnessPeakMaxDays + 1),
          'Past peak · ${freshnessPeakMaxDays + 1}+ d',
        ),
        _LegendItem(context.colors.ice, 'Frozen · ring starts at thaw'),
        Text(
          'Full ring = 2 months',
          style: TextStyle(color: context.colors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
