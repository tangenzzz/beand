import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

// When a roast is usually at its best, in days off roast (or since
// thawing), roughly — taste has the final say. Ultra light rests like light; a
// bean without a roast level is read as medium. Labels match
// roastLevelOptions (lowercased = Beans.roastLevel).
typedef FreshnessWindow = ({String label, int from, int to});

const freshnessWindows = <FreshnessWindow>[
  (label: 'Dark', from: 7, to: 21),
  (label: 'Medium', from: 10, to: 28),
  (label: 'Light', from: 28, to: 70),
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

// The ⓘ explanation of the ring: per roast one band in the ring's own
// colors — still resting, best time, past its best — on the ring's
// 12 weeks, the days written where the color changes.
class FreshnessLegend extends StatelessWidget {
  const FreshnessLegend({super.key});

  static const _nameWidth = 54.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final medium = freshnessWindowOf('medium');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final w in freshnessWindows) ...[
          Row(
            children: [
              SizedBox(
                width: _nameWidth,
                child: Text(
                  w.label,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ),
              Expanded(child: _Band(window: w)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: _nameWidth, bottom: 6),
            child: _BandMarks(window: w),
          ),
        ],
        const SizedBox(height: 4),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _LegendItem(freshnessColor(context, 0), 'Still resting'),
            _LegendItem(freshnessColor(context, medium.from), 'Best time'),
            _LegendItem(
              freshnessColor(context, medium.to + 1),
              'Past its best',
            ),
            _LegendItem(colors.ice, 'Frozen · ring starts at thaw'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'No roast level counts as medium. Rough timings – your taste has '
          'the final say.',
          style: TextStyle(color: colors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.window});

  final FreshnessWindow window;

  @override
  Widget build(BuildContext context) {
    final level = window.label.toLowerCase();
    Widget part(int days, Color color) => Expanded(
      flex: days,
      child: ColoredBox(color: color),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        // Stretched: an empty ColoredBox is otherwise 0 px high.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            part(window.from, freshnessColor(context, 0, level)),
            part(
              window.to - window.from,
              freshnessColor(context, window.from, level),
            ),
            part(
              freshnessRingDays - window.to,
              freshnessColor(context, window.to + 1, level),
            ),
          ],
        ),
      ),
    );
  }
}

// "7 d" and "21 d" under the band, centered on where the color changes
// (kept inside the band's width).
class _BandMarks extends StatelessWidget {
  const _BandMarks({required this.window});

  final FreshnessWindow window;

  static const _labelWidth = 36.0;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: context.colors.textSecondary, fontSize: 10);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        Widget mark(int days) {
          final double left = (w * days / freshnessRingDays - _labelWidth / 2)
              .clamp(0.0, math.max(0.0, w - _labelWidth));
          return Positioned(
            left: left,
            width: _labelWidth,
            child: Text('$days d', textAlign: TextAlign.center, style: style),
          );
        }

        return SizedBox(
          height: 14,
          child: Stack(children: [mark(window.from), mark(window.to)]),
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
