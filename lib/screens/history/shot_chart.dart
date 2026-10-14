import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../database/database.dart';
import '../../models/shot_phases.dart';
import '../../theme/app_theme.dart';
import 'history_logic.dart';

// Yield axis (right) in "nice" steps so the three axis labels
// (0, half, end) show round numbers.
double niceYieldMax(double weight) {
  const steps = [10, 20, 30, 40, 50, 60, 80, 100, 120, 160, 200, 300, 400, 600];
  for (final s in steps) {
    if (weight <= s) return s.toDouble();
  }
  return (weight / 100).ceil() * 100.0;
}

// Left axis (pressure/flow): at least 10, in even steps.
double niceLeftMax(double value) =>
    math.max(10, (value / 2).ceil() * 2).toDouble();

// Temperature window of the red curve: the top chart edge is [tempAbove]
// above the target temperature, the bottom edge [tempBelow] below it. A
// fixed relation to the target instead of auto-zooming to the data: the
// curve sits at the same height in every shot (two shots in comparison are
// directly readable) and the drop at pump start stays visible as a dent
// instead of filling the whole height.
const double tempAbove = 5;
const double tempBelow = 20;

// Nearest data point to [ms] (data points are sorted by time).
ShotReading? readingNear(List<ShotReading> readings, int ms) {
  if (readings.isEmpty) return null;
  var lo = 0;
  var hi = readings.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (readings[mid].timeMs < ms) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo > 0 && (ms - readings[lo - 1].timeMs) < (readings[lo].timeMs - ms)) {
    return readings[lo - 1];
  }
  return readings[lo];
}

// End of the actual brew (before the retraction) — the cursor starts there.
int extractionEndMs(List<ShotReading> readings) {
  for (var i = readings.length - 1; i >= 0; i--) {
    if (readings[i].stage != retractionStage) return readings[i].timeMs;
  }
  return readings.isEmpty ? 0 : readings.last.timeMs;
}

// Extraction chart: yield (yellow, right axis), flow (blue), pressure
// (green). The cursor (swiping across the chart) is managed by the parent
// (ShotDetailScreen), which also reads the numbers for the stat grid above
// from it — hence "controlled" here: [cursorMs] comes in, changes go back
// out via [onCursorChanged]. Below the chart a subtle gray stage bar
// instead of the earlier phase pills, below that the active stage with
// time fraction. With [other] a second shot is overlaid;
// [primaryDashed]/[otherDashed] decide which one is dashed (always the
// older one). With [showTemperature] the boiler temperature is added as a
// red curve (GaggiMate: one sensor that visibly drops during the brew) —
// it has its own scale, see [tempAbove]/[tempBelow].
class ShotChart extends StatelessWidget {
  const ShotChart({
    super.key,
    required this.readings,
    required this.phases,
    required this.cursorMs,
    required this.onCursorChanged,
    this.onStageTap,
    this.stageExpanded = false,
    this.other,
    this.primaryDashed = false,
    this.otherDashed = true,
    this.height = 200,
    this.minWindowSeconds,
    this.showTemperature = false,
    this.otherShowsTemperature = false,
    this.temperatureTarget,
    this.showCursor = true,
    this.fineGrid = false,
    this.showMaxXLabel = true,
    this.showStageBar = true,
  });

  final List<ShotReading> readings;
  final List<ShotPhase> phases;
  final int cursorMs;
  final ValueChanged<int> onCursorChanged;
  final List<ShotReading>? other;
  final bool primaryDashed;
  final bool otherDashed;
  // A more compact card (e.g. shot live card in the carousel) needs a
  // smaller chart than the full shot detail screen.
  final double height;
  // Minimum width of the time axis in seconds. Live, the curve thus grows
  // from the y-axis to the right into a fixed window, instead of the axis
  // moving with every data point and the lines appearing to slide in from
  // the right. The detail screen omits it: a finished shot always fills the
  // full width.
  final double? minWindowSeconds;
  // Draws the temperature (ShotReading.barUp) as a red curve. Only set for
  // machines with a single boiler sensor; the Meticulous has its own
  // temperature card for its four sensors.
  final bool showTemperature;
  final bool otherShowsTemperature;
  // Target temperature of the profile: sets the window and is drawn as a
  // thin red dashed line. If missing (old recording), the highest reading
  // serves as anchor and the line is omitted.
  final double? temperatureTarget;

  /// Draw the vertical cursor line. Off for the share image — there is
  /// nothing to swipe there.
  final bool showCursor;

  /// Finer vertical grid (2 bar instead of half the axis) — for the share
  /// image, which has to be readable without swiping.
  final bool fineGrid;

  /// The time label at the right edge that fl_chart puts at the end itself
  /// (e.g. "42s"). Off for the share image: it often sticks to the last
  /// regular label.
  final bool showMaxXLabel;

  /// Stage bar + stage name below the chart. Off for the share image: there
  /// only the bands in the chart show the stages, the names are listed
  /// below.
  final bool showStageBar;

  /// Turns the stage name below the bar into a toggle for the stage details
  /// below (arrow shows the state). Null = no toggle.
  final VoidCallback? onStageTap;
  final bool stageExpanded;

  double _max(List<ShotReading> r, double? Function(ShotReading) f) =>
      r.fold(0.0, (m, e) => math.max(m, f(e) ?? 0));

  // Without data points the axes still stay visible (the live card thus
  // visibly waits for the first data, instead of first showing an empty
  // hole and then suddenly a chart).
  static const _emptyWindowSeconds = 20.0;

  // Reserved widths of the two axis label areas (see titlesData): the
  // curve drawing area lies between them. Swiping uses this to map the
  // finger position back to time.
  static const _leftAxisWidth = 24.0;
  static const _rightAxisWidth = 28.0;

  // Time under the finger, rounded to the nearest real data point — so the
  // cursor snaps like tapping on data points and does not stop in the empty
  // part of the time window right of the curve (the live card shows a fixed
  // window that is wider than the data).
  int _msAtX(double dx, double width, double maxX) {
    final plot = width - _leftAxisWidth - _rightAxisWidth;
    if (plot <= 0) return cursorMs;
    final fraction = ((dx - _leftAxisWidth) / plot).clamp(0.0, 1.0);
    final raw = (fraction * maxX * 1000).round();
    return readingNear(readings, raw)?.timeMs ?? raw;
  }

  @override
  Widget build(BuildContext context) {
    // The three curve colors come from the theme: weight like the middle
    // sensor, flow like the bottom one, pressure like "good".
    final colors = context.colors;
    final yieldColor = colors.sensorMid;
    final flowColor = colors.sensorDown;
    final pressureColor = colors.success;
    final tempColor = colors.danger;
    final all = [...readings, ...?other];
    final leftMax = niceLeftMax(
      math.max(_max(all, (r) => r.pressure), _max(all, (r) => r.flow)),
    );
    final yieldMax = niceYieldMax(_max(all, (r) => r.weight));
    final k = leftMax / yieldMax;
    // Only the empty case gets a fallback window — otherwise a short shot
    // would be artificially stretched in the detail screen.
    final dataMax = all.isEmpty
        ? _emptyWindowSeconds
        : all.fold(0, (m, e) => math.max(m, e.timeMs)) / 1000;
    final maxX = math.max(dataMax, minWindowSeconds ?? 0);

    // The temperature (around 93 °C) does not fit the left axis (0-10 bar):
    // it is mapped from its own window onto the same height.
    final tempReadings = [
      if (showTemperature) ...readings,
      if (otherShowsTemperature) ...?other,
    ];
    // The target only applies if a temperature curve is drawn at all:
    // otherwise the red dashed line also showed in the Meticulous chart,
    // which passes its target temperature only for the value row.
    final tempTarget = showTemperature || otherShowsTemperature
        ? temperatureTarget
        : null;
    final tempPeak = _max(tempReadings, (r) => r.barUp);
    final tempAnchor = tempTarget != null && tempTarget > 0
        ? tempTarget
        : (tempPeak > 0 ? tempPeak.roundToDouble() : null);
    final tempLow = tempAnchor == null ? 0.0 : tempAnchor - tempBelow;
    final tempSpan = tempAbove + tempBelow;
    double toLeftAxis(double celsius) =>
        leftMax * (celsius - tempLow) / tempSpan;

    List<FlSpot> spots(
      List<ShotReading> r,
      double? Function(ShotReading) f, [
      double scale = 1,
    ]) => [
      for (final e in r)
        if (f(e) != null) FlSpot(e.timeMs / 1000, f(e)! * scale),
    ];

    LineChartBarData bar(List<FlSpot> s, Color c, bool dashed) =>
        LineChartBarData(
          spots: s,
          color: dashed ? c.withValues(alpha: 0.85) : c,
          barWidth: dashed ? 1.8 : 2.2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          dashArray: dashed ? const [5, 4] : null,
        );

    // Temperature lies behind the other three: it runs flat and should not
    // cover pressure and flow.
    List<FlSpot> tempSpots(List<ShotReading> r) => [
      for (final e in r)
        if (e.barUp != null) FlSpot(e.timeMs / 1000, toLeftAxis(e.barUp!)),
    ];

    final bars = <LineChartBarData>[
      if (tempAnchor != null) ...[
        if (otherShowsTemperature && other != null)
          bar(tempSpots(other!), tempColor, otherDashed),
        if (showTemperature) bar(tempSpots(readings), tempColor, primaryDashed),
      ],
      if (other != null) ...[
        bar(spots(other!, (r) => r.weight, k), yieldColor, otherDashed),
        bar(spots(other!, (r) => r.flow), flowColor, otherDashed),
        bar(spots(other!, (r) => r.pressure), pressureColor, otherDashed),
      ],
      bar(spots(readings, (r) => r.weight, k), yieldColor, primaryDashed),
      bar(spots(readings, (r) => r.flow), flowColor, primaryDashed),
      bar(spots(readings, (r) => r.pressure), pressureColor, primaryDashed),
    ];

    final xInterval = maxX <= 25
        ? 5.0
        : (maxX <= 50 ? 10.0 : (maxX <= 100 ? 20.0 : 30.0));
    final yInterval = fineGrid && leftMax <= 12 ? 2.0 : leftMax / 2;
    final labelStyle = TextStyle(color: colors.textSecondary, fontSize: 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (other != null) ...[
          const Align(alignment: Alignment.centerRight, child: _LineKey()),
          const SizedBox(height: 8),
        ],
        // Swiping over the curve needs its OWN recognizer: fl_chart listens
        // internally with a pan recognizer (threshold in every direction),
        // the card carousel above with a HorizontalDrag (threshold on one
        // axis). The PageView thus wins every swipe gesture, and in the
        // live card the cursor could only be tapped, not dragged. A
        // recognizer HERE sits deeper in the gesture arena than the
        // carousel's and wins at equal threshold. Accepted trade-off: a
        // swipe that starts on the chart no longer pages — there is room
        // for that everywhere else on the card.
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            onHorizontalDragStart: (d) => onCursorChanged(
              _msAtX(d.localPosition.dx, constraints.maxWidth, maxX),
            ),
            onHorizontalDragUpdate: (d) => onCursorChanged(
              _msAtX(d.localPosition.dx, constraints.maxWidth, maxX),
            ),
            child: SizedBox(
              height: height,
              child: LineChart(
                duration: Duration.zero,
                LineChartData(
                  minX: 0,
                  maxX: maxX,
                  minY: 0,
                  maxY: leftMax,
                  clipData: const FlClipData.all(),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: context.colors.divider,
                      strokeWidth: 1,
                      dashArray: v == 0 ? null : const [2, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: yInterval,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(v.toStringAsFixed(0), style: labelStyle),
                        ),
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: yInterval,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            (v / k).round().toString(),
                            style: TextStyle(
                              color: yieldColor.withValues(alpha: 0.8),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 20,
                        interval: xInterval,
                        getTitlesWidget: (v, meta) =>
                            !showMaxXLabel &&
                                v == meta.max &&
                                (v / xInterval - (v / xInterval).round())
                                        .abs() >
                                    0.01
                            ? const SizedBox.shrink()
                            : SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text('${v.round()}s', style: labelStyle),
                              ),
                      ),
                    ),
                  ),
                  // Subtle, neutral bands instead of phase colors: only every
                  // second phase slightly lightened, so boundaries stay
                  // faintly visible without looking colorful.
                  rangeAnnotations: RangeAnnotations(
                    verticalRangeAnnotations: [
                      for (var i = 0; i < phases.length; i++)
                        if (i.isEven)
                          VerticalRangeAnnotation(
                            x1: phases[i].startMs / 1000,
                            x2: phases[i].endMs / 1000,
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.028,
                            ),
                          ),
                    ],
                  ),
                  extraLinesData: ExtraLinesData(
                    // Thin red dashed line at the target temperature:
                    // without it the height of the red curve means nothing,
                    // because the window has no axis labels of its own.
                    horizontalLines: [
                      if (tempAnchor != null && tempTarget != null)
                        HorizontalLine(
                          y: toLeftAxis(tempTarget),
                          color: tempColor.withValues(alpha: 0.45),
                          strokeWidth: 1,
                          dashArray: const [3, 5],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            padding: const EdgeInsets.only(right: 2, bottom: 1),
                            style: TextStyle(
                              color: tempColor.withValues(alpha: 0.75),
                              fontSize: 9.5,
                            ),
                            labelResolver: (_) => tempTarget.toStringAsFixed(0),
                          ),
                        ),
                    ],
                    verticalLines: [
                      if (showCursor)
                        VerticalLine(
                          x: cursorMs / 1000,
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.5,
                          ),
                          strokeWidth: 1,
                        ),
                    ],
                  ),
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: false,
                    // Nearest point by x only — no matter how high the
                    // finger position is.
                    touchSpotThreshold: double.infinity,
                    distanceCalculator: (touch, spot) =>
                        (touch.dx - spot.dx).abs(),
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions) return;
                      final hit = response?.lineBarSpots;
                      if (hit == null || hit.isEmpty) return;
                      final ms = (hit.first.x * 1000).round();
                      if (ms != cursorMs) onCursorChanged(ms);
                    },
                  ),
                  lineBarsData: bars,
                ),
              ),
            ),
          ),
        ),
        if (showStageBar && phases.isNotEmpty) ...[
          const SizedBox(height: 10),
          _StageBar(phases: phases, cursorMs: cursorMs),
          const SizedBox(height: 9),
          _StageReadout(
            phase: phaseAt(phases, cursorMs),
            allNames: [for (final p in phases) p.name],
            cursorMs: cursorMs,
            extractionEndMs: extractionEndMs(readings),
            onTap: onStageTap,
            expanded: stageExpanded,
          ),
        ],
      ],
    );
  }
}

// Segmented bar (width per phase proportional to duration) instead of the
// earlier chip cloud — subtle gray, only the active segment (cursor
// position) stands out lighter.
class _StageBar extends StatelessWidget {
  const _StageBar({required this.phases, required this.cursorMs});

  final List<ShotPhase> phases;
  final int cursorMs;

  @override
  Widget build(BuildContext context) {
    final total = phases.last.endMs - phases.first.startMs;
    if (total <= 0) return const SizedBox.shrink();
    final active = phaseAt(phases, cursorMs);
    return Row(
      children: [
        for (final p in phases) ...[
          if (p != phases.first) const SizedBox(width: 3),
          Expanded(
            flex: math.max(1, ((p.endMs - p.startMs) * 1000 / total).round()),
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(
                  alpha: p == active ? 0.55 : 0.16,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StageReadout extends StatelessWidget {
  const _StageReadout({
    required this.phase,
    required this.allNames,
    required this.cursorMs,
    required this.extractionEndMs,
    this.onTap,
    this.expanded = false,
  });

  final ShotPhase? phase;

  /// All phase names of the shot: the space for the name is sized to the
  /// longest one, so the arrow next to it stays put while swiping.
  final List<String> allNames;
  final int cursorMs;
  final int extractionEndMs;
  final VoidCallback? onTap;
  final bool expanded;

  static const _arrowSize = 18.0;
  static const _arrowGap = 10.0;
  static const _timeGap = 8.0;

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      color: context.colors.textPrimary,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );
    final timeText = Text(
      '${seconds(cursorMs)} s / ${seconds(extractionEndMs)} s',
      style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    // Measured in the font Text() actually draws with (theme font plus own
    // style), otherwise the width is off.
    final baseStyle = DefaultTextStyle.of(context).style;
    double widthOf(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: baseStyle.merge(style)),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    final row = LayoutBuilder(
      builder: (context, constraints) {
        // Arrow right of the name like LOCAL/AI ANALYSIS, but at a fixed
        // spot: after the longest name of the shot. Long names (the
        // GaggiMate has some) wrap, the time is always shown in full.
        final arrow = onTap == null ? 0.0 : _arrowGap + _arrowSize;
        // Room for the widest time of this shot (cursor at the end),
        // otherwise the moving time would shift the arrow.
        final widestTime =
            '${seconds(extractionEndMs)} s / ${seconds(extractionEndMs)} s';
        final timeWidth = widthOf(widestTime, timeText.style!).ceilToDouble();
        var longestName = '';
        var longest = 0.0;
        for (final name in allNames) {
          final w = widthOf(name, nameStyle);
          if (w > longest) {
            longest = w;
            longestName = name;
          }
        }
        final room = constraints.maxWidth - timeWidth - _timeGap - arrow;
        final slot = math.max(0.0, math.min(longest.ceilToDouble() + 1, room));
        return Row(
          children: [
            SizedBox(
              width: slot,
              // Never truncated: if a long name does not fit the line, it
              // wraps.
              // The longest name invisibly underneath fixes the height: if
              // it wraps, the row does not jump between one and two lines
              // while swiping.
              child: Stack(
                children: [
                  Visibility(
                    visible: false,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Text(longestName, style: nameStyle),
                  ),
                  Text(phase?.name ?? '', style: nameStyle),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: _arrowGap),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: _arrowSize,
                color: context.colors.textTertiary,
              ),
            ],
            const Spacer(),
            timeText,
          ],
        );
      },
    );
    if (onTap == null) return row;
    // The whole row is the toggle — the arrow alone would be too small a
    // target.
    return InkWell(
      key: const ValueKey('stage-details-toggle'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
      ),
    );
  }
}

// Legend in comparison mode: solid = newer, dashed = older.
class _LineKey extends StatelessWidget {
  const _LineKey();

  @override
  Widget build(BuildContext context) {
    Widget item(bool dashed, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 2,
          child: CustomPaint(
            painter: _DashPainter(dashed, context.colors.textSecondary),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: context.colors.textTertiary, fontSize: 11),
        ),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        item(false, 'newer'),
        const SizedBox(width: 12),
        item(true, 'older'),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.dashed, this.color);
  final bool dashed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    if (!dashed) {
      canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
      return;
    }
    for (double x = 0; x < size.width; x += 5) {
      canvas.drawLine(
        Offset(x, 0),
        Offset((x + 3).clamp(0, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.dashed != dashed || old.color != color;
}
