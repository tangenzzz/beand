import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/machine_sensors.dart';
import '../../services/heating_estimator.dart';
import '../../services/meticulous_socket_service.dart';
import '../../theme/app_theme.dart';
import 'sensor_stack.dart';
import 'temperature_ring.dart';

const chartVisiblePrefKey = 'temperature_chart_visible';

// Preheat/temperature hero: ring, four sensors, temperature curve. The
// heating model behind it (hero value, ring fill, ETA, stabilized) lives in
// HeatingEstimator since 2026-10-21 so it also runs in the background; the
// app provides one, otherwise the tile keeps its own (tests).
class TemperatureTile extends StatefulWidget {
  const TemperatureTile({super.key});

  @override
  State<TemperatureTile> createState() => _TemperatureTileState();
}

class _TemperatureTileState extends State<TemperatureTile> {
  bool _chartVisible = true;

  // The app's estimator (provider), or our own when there is none.
  HeatingEstimator? _ownEstimator;

  HeatingEstimator _estimator(BuildContext context) {
    try {
      return context.watch<HeatingEstimator>();
    } on ProviderNotFoundException {
      return _ownEstimator ??= HeatingEstimator(
        context.read<MeticulousSocketService>(),
      )..start();
    }
  }

  @override
  void dispose() {
    _ownEstimator?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Persisted across app restarts so the curve is in the same
    // expanded/collapsed state after reopening as when leaving.
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(chartVisiblePrefKey);
      if (saved != null && mounted) {
        setState(() => _chartVisible = saved);
      }
    });
  }

  void _setChartVisible(bool visible) {
    setState(() => _chartVisible = visible);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(chartVisiblePrefKey, visible);
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MeticulousSocketService>();
    final estimator = _estimator(context);
    final sensors = service.latestSensors;
    final history = service.recentSensors;
    final heroValue = estimator.heroValue;
    final sessionTarget = estimator.sessionTarget;
    final isHeatingSession = estimator.isHeatingSession;
    final ringProgress = estimator.ringProgress;
    final stabilityProgress = estimator.stabilityProgress;
    final stabilized = estimator.stabilized;
    final stabilityShown = estimator.stabilityShown;
    final eta = estimator.eta;
    final ringColor = (estimator.isHeatingState && !estimator.atTarget)
        ? context.colors.heroRingHeating
        : context.colors.heroRingReady;

    // Status line in the ring: ETA while heating, then Ready → Stabilizing
    // → Stable (instead of the earlier "at target").
    var statusText = eta;
    var statusColor = ringColor;
    if (stabilityShown) {
      if (stabilized) {
        statusText = 'Stable';
        statusColor = context.colors.accent;
      } else if (stabilityProgress > 0.02) {
        statusText = 'Stabilizing';
        statusColor = context.colors.accent;
      } else {
        statusText = 'Ready';
        statusColor = context.colors.heroRingReady;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ring on the left, the four sensors stacked on the right — in
          // the order in which they physically sit in the brew unit.
          // Previously they flanked the ring in two columns, which squeezed
          // it and pushed "Group Head" out of the column.
          Row(
            // Centered instead of at the left edge: the same arrangement as
            // on the GaggiMate page.
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TemperatureRing(
                heroValue: heroValue,
                // Only show the target temp in the ring when actually heating
                // (profile session or preheat) — not already when a profile
                // is merely loaded/selected. This also makes it disappear
                // immediately on cancel, like ETA and ring progress.
                targetTemp: isHeatingSession ? sessionTarget : null,
                progress: ringProgress,
                outerProgress: stabilityProgress,
                color: ringColor,
                statusText: statusText,
                statusColor: statusColor,
                showCheck: stabilized,
                // The machine stops before heating when its detector finds
                // no water — say so instead of showing a stalled ring.
                warning: service.isWaterMissing ? 'No water' : null,
                warningHint: 'Fill, then press the dial',
              ),
              const SizedBox(width: SensorStack.ringToValues),
              SensorStack(
                sensors: [
                  SensorValue(
                    'UP',
                    sensors?.barUp,
                    context.colors.sensorUp,
                    unit: '°',
                  ),
                  SensorValue(
                    'MID',
                    sensors?.barMidUp,
                    context.colors.sensorMid,
                    unit: '°',
                  ),
                  SensorValue(
                    'DOWN',
                    sensors?.barMidDown,
                    context.colors.sensorDown,
                    unit: '°',
                  ),
                  SensorValue(
                    'GROUP HEAD',
                    sensors?.barDown,
                    context.colors.sensorGroup,
                    unit: '°',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: IconButton(
              icon: Icon(
                _chartVisible ? Icons.expand_less : Icons.show_chart,
                color: context.colors.textSecondary,
                size: 20,
              ),
              tooltip: _chartVisible ? 'Hide chart' : 'Show chart',
              onPressed: () => _setChartVisible(!_chartVisible),
              visualDensity: VisualDensity.compact,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.ease,
            child: _chartVisible
                ? SizedBox(
                    height: 190,
                    child: history.isEmpty
                        ? Center(
                            child: Text(
                              'Waiting for sensor data…',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                              ),
                            ),
                          )
                        : _TemperatureChart(
                            history: history,
                            // Target line in profile session or preheat,
                            // not already with a merely loaded profile —
                            // so it also disappears immediately on cancel,
                            // like in the ring.
                            targetTemp: isHeatingSession ? sessionTarget : null,
                          ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _TemperatureChart extends StatelessWidget {
  const _TemperatureChart({required this.history, required this.targetTemp});

  final List<MachineSensors> history;
  final double? targetTemp;

  // Only for the x-axis labels (seconds); no real sample timestamps
  // available — measured from a real heating capture (median
  // 0.1057s/sample), accurate enough for the axis.
  static const _chartSampleIntervalSeconds = 0.1057;
  static const _windowSeconds = 400.0;

  @override
  Widget build(BuildContext context) {
    final spotsTop = <FlSpot>[];
    final spotsMidUp = <FlSpot>[];
    final spotsMidDown = <FlSpot>[];
    final spotsBottom = <FlSpot>[];

    // x = seconds relative to "now" (0 = newest sample, negative = past),
    // x = seconds since the oldest sample in the current buffer (0 = oldest,
    // growing to the right) — so the curve builds from left to right instead
    // of sticking to "now" on the right and growing backwards to the left.
    // Once the buffer is full (~400s), this naturally turns into a classic
    // scrolling window (new on the right, old drops off the left).
    for (var i = 0; i < history.length; i++) {
      final s = history[i];
      final x = i * _chartSampleIntervalSeconds;
      spotsTop.add(FlSpot(x, s.barUp));
      spotsMidUp.add(FlSpot(x, s.barMidUp));
      spotsMidDown.add(FlSpot(x, s.barMidDown));
      spotsBottom.add(FlSpot(x, s.barDown));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: _windowSeconds,
        minY: 0,
        maxY: 99,
        gridData: FlGridData(
          show: true,
          horizontalInterval: 20,
          verticalInterval: 100,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: context.colors.divider, strokeWidth: 0.5),
          getDrawingVerticalLine: (_) =>
              FlLine(color: context.colors.divider, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: Text(
              'sec.',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 10,
              ),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: 100,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 9,
                ),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text(
              '°C',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 10,
              ),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 20,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 9,
                ),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((spot) {
              return LineTooltipItem(
                '${spot.y.toStringAsFixed(1)}°C',
                TextStyle(color: context.colors.textPrimary, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (targetTemp != null)
              HorizontalLine(
                y: targetTemp!,
                color: context.colors.danger,
                strokeWidth: 1.5,
                dashArray: [6, 4],
              ),
          ],
        ),
        lineBarsData: [
          _line(spotsTop, context.colors.sensorUp),
          _line(spotsMidUp, context.colors.sensorMid),
          _line(spotsMidDown, context.colors.sensorDown),
          _line(spotsBottom, context.colors.sensorGroup),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
  }
}
