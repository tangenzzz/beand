import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/profile_detail.dart';
import '../../models/setpoint_curve.dart';
import '../../models/shot_phases.dart';
import '../../theme/app_theme.dart';
import '../history/shot_chart.dart';

// A profile's targets over time, drawn like the chart in the shot detail:
// same axes (pressure and flow left, weight right), colors, bands, stage bar
// and cursor. So a target curve and a pulled shot read the same.
class SetpointCurveChart extends StatefulWidget {
  const SetpointCurveChart({super.key, required this.curve, this.height = 200});

  final SetpointCurve curve;
  final double height;

  @override
  State<SetpointCurveChart> createState() => _SetpointCurveChartState();
}

class _SetpointCurveChartState extends State<SetpointCurveChart> {
  static const _leftAxisWidth = 24.0;
  static const _rightAxisWidth = 28.0;

  int _cursorMs = 0;

  void _moveCursor(double dx, double width, double maxX) {
    final plot = width - _leftAxisWidth - _rightAxisWidth;
    if (plot <= 0) return;
    final fraction = ((dx - _leftAxisWidth) / plot).clamp(0.0, 1.0);
    setState(() => _cursorMs = (fraction * maxX * 1000).round());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final curve = widget.curve;
    final maxX = math.max(curve.durationS, 1.0);

    double peak(bool Function(String) wanted) {
      var m = 0.0;
      for (final s in curve.segments) {
        if (!wanted(s.type)) continue;
        for (final p in s.points) {
          m = math.max(m, p.value);
        }
      }
      return m;
    }

    final leftMax = niceLeftMax(peak((t) => t != 'weight' && t != 'power'));
    final hasWeight =
        curve.finalWeight != null ||
        curve.segments.any((s) => s.type == 'weight');
    final yieldMax = niceYieldMax(
      math.max(peak((t) => t == 'weight'), curve.finalWeight ?? 0),
    );
    final k = leftMax / yieldMax;

    double scaled(String type, double v) => switch (type) {
      'weight' => v * k,
      // Percent has no axis of its own: full height is 100 %.
      'power' => v * leftMax / 100,
      _ => v,
    };

    final temperature = curve.temperature;
    final tempY = temperature == null
        ? null
        : leftMax * tempBelow / (tempAbove + tempBelow);

    final types = <String>[
      for (final t in const ['pressure', 'flow', 'power', 'weight'])
        if (curve.segments.any((s) => s.type == t)) t,
    ];
    Color colorOf(String type) => colorForType(context, type);

    final phases = [
      for (final s in curve.stages)
        ShotPhase(
          name: s.name,
          startMs: (s.startS * 1000).round(),
          endMs: (s.endS * 1000).round(),
          color: colors.textSecondary,
          isRetraction: false,
        ),
    ];
    final totalMs = (curve.durationS * 1000).round();
    final xInterval = maxX <= 25
        ? 5.0
        : (maxX <= 50
              ? 10.0
              : (maxX <= 100 ? 20.0 : (maxX <= 300 ? 30.0 : 60.0)));
    final yInterval = leftMax / 2;
    final labelStyle = TextStyle(color: colors.textSecondary, fontSize: 10);
    final weightColor = colorOf('weight');

    String timeLabel(double v) {
      if (!curve.clockLabels) return '${v.round()}s';
      final s = v.round();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            key: const ValueKey('setpoint-chart'),
            onTapDown: (d) =>
                _moveCursor(d.localPosition.dx, constraints.maxWidth, maxX),
            onHorizontalDragStart: (d) =>
                _moveCursor(d.localPosition.dx, constraints.maxWidth, maxX),
            onHorizontalDragUpdate: (d) =>
                _moveCursor(d.localPosition.dx, constraints.maxWidth, maxX),
            child: SizedBox(
              height: widget.height,
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
                      color: colors.divider,
                      strokeWidth: 1,
                      dashArray: v == 0 ? null : const [2, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: _leftAxisWidth,
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
                        reservedSize: _rightAxisWidth,
                        interval: yInterval,
                        getTitlesWidget: (v, meta) => !hasWeight
                            ? const SizedBox.shrink()
                            : SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(
                                  (v / k).round().toString(),
                                  style: TextStyle(
                                    color: weightColor.withValues(alpha: 0.8),
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
                        // The label fl_chart adds at the very end often sticks
                        // to the last regular one.
                        getTitlesWidget: (v, meta) =>
                            v == meta.max &&
                                (v / xInterval - (v / xInterval).round())
                                        .abs() >
                                    0.01
                            ? const SizedBox.shrink()
                            : SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(timeLabel(v), style: labelStyle),
                              ),
                      ),
                    ),
                  ),
                  rangeAnnotations: RangeAnnotations(
                    verticalRangeAnnotations: [
                      for (var i = 0; i < phases.length; i++)
                        if (i.isEven && phases[i].endMs > phases[i].startMs)
                          VerticalRangeAnnotation(
                            x1: phases[i].startMs / 1000,
                            x2: phases[i].endMs / 1000,
                            color: colors.textPrimary.withValues(alpha: 0.028),
                          ),
                    ],
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      if (tempY != null)
                        _targetLine(
                          tempY,
                          colors.danger,
                          '${temperature!.toStringAsFixed(0)}°',
                        ),
                      if (curve.finalWeight case final w?)
                        _targetLine(
                          w * k,
                          weightColor,
                          '${w.toStringAsFixed(0)} g',
                        ),
                    ],
                    verticalLines: [
                      VerticalLine(
                        x: _cursorMs / 1000,
                        color: colors.textPrimary.withValues(alpha: 0.5),
                        strokeWidth: 1,
                      ),
                    ],
                  ),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    for (final s in curve.segments)
                      LineChartBarData(
                        spots: [
                          for (final p in s.points)
                            FlSpot(p.seconds, scaled(s.type, p.value)),
                        ],
                        color: s.estimated
                            ? colorOf(s.type).withValues(alpha: 0.85)
                            : colorOf(s.type),
                        barWidth: s.estimated ? 1.8 : 2.2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        dashArray: s.estimated ? const [5, 4] : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (phases.isNotEmpty) ...[
          const SizedBox(height: 10),
          StageBar(phases: phases, cursorMs: _cursorMs),
          const SizedBox(height: 9),
          StageReadout(
            phase: phaseAt(phases, _cursorMs),
            allNames: [for (final p in phases) p.name],
            cursorMs: _cursorMs,
            extractionEndMs: totalMs,
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final t in types)
              _Key(
                color: colorOf(t),
                text: t == 'flow'
                    ? 'Flow ${curve.flowUnit}'
                    : t == 'weight'
                    ? 'Water g'
                    : '${typeLabel(t)} ${unitFor(t)}',
              ),
            if (curve.hasEstimate)
              _Key(
                color: colors.textSecondary,
                dashed: true,
                text: 'Length depends on the shot',
              ),
          ],
        ),
      ],
    );
  }

  HorizontalLine _targetLine(double y, Color color, String label) =>
      HorizontalLine(
        y: y,
        color: color.withValues(alpha: 0.45),
        strokeWidth: 1,
        dashArray: const [3, 5],
        label: HorizontalLineLabel(
          show: true,
          alignment: Alignment.topRight,
          padding: const EdgeInsets.only(right: 2, bottom: 1),
          style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 9.5),
          labelResolver: (_) => label,
        ),
      );
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.text, this.dashed = false});

  final Color color;
  final String text;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < (dashed ? 2 : 1); i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(width: dashed ? 6 : 14, height: 2, color: color),
        ],
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(color: context.colors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}
