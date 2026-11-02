import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../database/database.dart';
import '../../theme/app_theme.dart';

// The temperatures of a Decent shot file in their own chart below the main
// one: basket (barUp), mix and the profile's goal (dashed), on a scale of
// their own — a degree or two of drift would be invisible on the
// pressure/flow axis. Same time axis and the same cursor as the main
// chart, so both read together.
class TemperatureChart extends StatelessWidget {
  const TemperatureChart({
    super.key,
    required this.readings,
    required this.cursorMs,
    required this.onCursorChanged,
    this.height = 120,
  });

  final List<ShotReading> readings;
  final int cursorMs;
  final ValueChanged<int> onCursorChanged;
  final double height;

  /// Any reading with a mix or goal temperature: the shots this chart is
  /// for (Decent files).
  static bool hasData(List<ShotReading> readings) =>
      readings.any((r) => r.tempMix != null || r.tempGoal != null);

  static Color basketColor(BuildContext context) => context.colors.danger;
  static Color mixColor(BuildContext context) => context.colors.heroRingHeating;
  static Color goalColor(BuildContext context) =>
      context.colors.danger.withValues(alpha: 0.6);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final values = [
      for (final r in readings) ...[
        if (r.barUp != null && r.barUp! > 0) r.barUp!,
        if (r.tempMix != null && r.tempMix! > 0) r.tempMix!,
        if (r.tempGoal != null && r.tempGoal! > 0) r.tempGoal!,
      ],
    ];
    // Whole degrees, the window on multiples of the grid step so the
    // labels never crowd.
    final lowest = values.isEmpty ? 88.0 : values.reduce(math.min) - 0.5;
    final highest = values.isEmpty ? 95.0 : values.reduce(math.max) + 0.5;
    final yInterval = math.max(1, ((highest - lowest) / 3).ceil()).toDouble();
    final low = (lowest / yInterval).floor() * yInterval;
    final high = (highest / yInterval).ceil() * yInterval;
    final maxX = readings.isEmpty
        ? 30.0
        : readings.fold(0, (m, e) => math.max(m, e.timeMs)) / 1000;
    final xInterval = maxX <= 25
        ? 5.0
        : (maxX <= 50 ? 10.0 : (maxX <= 100 ? 20.0 : 30.0));
    final labelStyle = TextStyle(color: colors.textSecondary, fontSize: 10);

    LineChartBarData line(
      double? Function(ShotReading) f,
      Color color, {
      bool dashed = false,
    }) => LineChartBarData(
      spots: [
        for (final r in readings)
          if (f(r) != null && f(r)! > 0) FlSpot(r.timeMs / 1000, f(r)!),
      ],
      color: color,
      barWidth: dashed ? 1.4 : 2.2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      dashArray: dashed ? const [5, 4] : null,
    );

    int msAt(double dx, double width) {
      // The chart area starts after the left labels (24) and ends before
      // the right reserve (28), as in the main chart.
      final plot = width - 24 - 28;
      return ((dx - 24) / plot * maxX * 1000).round().clamp(
        0,
        (maxX * 1000).round(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onHorizontalDragStart: (d) =>
            onCursorChanged(msAt(d.localPosition.dx, constraints.maxWidth)),
        onHorizontalDragUpdate: (d) =>
            onCursorChanged(msAt(d.localPosition.dx, constraints.maxWidth)),
        onTapDown: (d) =>
            onCursorChanged(msAt(d.localPosition.dx, constraints.maxWidth)),
        child: SizedBox(
          height: height,
          child: LineChart(
            duration: Duration.zero,
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: low,
              maxY: high,
              clipData: const FlClipData.all(),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: yInterval,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: colors.divider,
                  strokeWidth: 1,
                  dashArray: const [2, 4],
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                // Only the room, so the time axis lines up with the main
                // chart's (which has its yield labels there).
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (_, _) => const SizedBox.shrink(),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: yInterval,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text('${v.round()}°', style: labelStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    interval: xInterval,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text('${v.round()}s', style: labelStyle),
                    ),
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  VerticalLine(
                    x: cursorMs / 1000,
                    color: colors.textPrimary.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ],
              ),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                line((r) => r.tempGoal, goalColor(context), dashed: true),
                line((r) => r.tempMix, mixColor(context)),
                line((r) => r.barUp, basketColor(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
