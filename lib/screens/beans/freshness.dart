import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// When a roast is usually at its best, in days off roast (or since
// thawing). A guide, not an expiry date. Ultra light rests like light; a
// bean without a roast level is read as medium.
typedef FreshnessWindow = ({String label, int from, int to, String range});

const freshnessWindows = <FreshnessWindow>[
  (label: 'Dark', from: 7, to: 21, range: '1–3 wk'),
  (label: 'Medium', from: 10, to: 28, range: '10d–4 wk'),
  (label: 'Light', from: 28, to: 70, range: '4–10 wk'),
];

FreshnessWindow freshnessWindowOf(String? roastLevel) => switch (roastLevel) {
  'dark' => freshnessWindows[0],
  'light' || 'ultra-light' => freshnessWindows[2],
  _ => freshnessWindows[1],
};

// The ring fills over 12 weeks, the span of the longest (light) window
// plus a little.
const freshnessRingDays = 84;

// The stages come from the theme: still resting like the heating hero ring,
// in its window like "connected", past it muted.
Color freshnessColor(BuildContext context, int days, [String? roastLevel]) {
  final colors = context.colors;
  final window = freshnessWindowOf(roastLevel);
  if (days < window.from) return colors.heroRingHeating;
  if (days <= window.to) return colors.success;
  return colors.textSecondary;
}

double freshnessProgress(int days) =>
    (days / freshnessRingDays).clamp(0.0, 1.0);

class FreshnessRing extends StatelessWidget {
  const FreshnessRing({
    super.key,
    required this.days,
    this.roastLevel,
    this.size = 40,
  });

  final int days;
  final String? roastLevel;
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
            color: freshnessColor(context, days, roastLevel),
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

// The ⓘ explanation of the ring: when each roast is usually good, as bars
// on a 0–12 week axis, plus what the colors and the ice ring mean.
class FreshnessLegend extends StatelessWidget {
  const FreshnessLegend({super.key});

  static const _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final small = TextStyle(color: colors.textSecondary, fontSize: 11);
    final medium = freshnessWindowOf('medium');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Usually good by roast', style: small),
        const SizedBox(height: 8),
        for (final w in freshnessWindows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: 52, child: Text(w.label, style: small)),
                Expanded(
                  child: _WindowBar(window: w, weeks: _weeks),
                ),
                SizedBox(
                  width: 58,
                  child: Text(w.range, textAlign: TextAlign.end, style: small),
                ),
              ],
            ),
          ),
        Row(
          children: [
            const SizedBox(width: 52),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final week in [0, 4, 8, 12])
                    Text(
                      week == _weeks ? '$week wk' : '$week',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 58),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _LegendItem(freshnessColor(context, 0), 'Still resting'),
            _LegendItem(freshnessColor(context, medium.from), 'In its window'),
            _LegendItem(
              freshnessColor(context, medium.to + 1),
              'Past its window',
            ),
            _LegendItem(colors.ice, 'Frozen · ring starts at thaw'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Ultra light counts as light, no roast level as medium. '
          'Full ring = 12 weeks. A guide, not an expiry date; let taste '
          'decide.',
          style: TextStyle(color: colors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}

class _WindowBar extends StatelessWidget {
  const _WindowBar({required this.window, required this.weeks});

  final FreshnessWindow window;
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final span = weeks * 7;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return SizedBox(
          height: 8,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colors.textPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Positioned(
                left: w * window.from / span,
                width: w * (window.to - window.from) / span,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.success,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
