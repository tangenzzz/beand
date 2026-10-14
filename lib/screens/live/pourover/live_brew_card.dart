import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/brew_plan.dart';
import '../../../models/brew_recipe.dart';
import '../../../services/live_shot_service.dart';
import '../../../services/pourover_brew_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_button.dart';
import '../shot_live_card.dart';
import '../tile_title.dart';
import 'recipe_format.dart';

// Live brew card: chart on top (weight in yellow over time, the plan dashed,
// flow in blue on its own axis on the right, pours as bands; above it
// Time/Weight/Flow like in the machines' live card), below it the pour list
// with check marks and the hint for the current pour. "Finish" at the bottom.
class LiveBrewCard extends StatelessWidget {
  const LiveBrewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final brew = context.watch<PourOverBrewService>();
    final plan = brew.plan;
    final running = brew.stage == ShotStage.running;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TileTitle(short: 'LIVE', active: brew.activeCard == ActiveCard.live),
          const SizedBox(height: 10),
          if (plan == null)
            Expanded(
              child: Text(
                'Pick a profile in the Pre Brew card.',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 13,
                ),
              ),
            )
          else ...[
            Row(
              children: [
                LiveStat(
                  'Time',
                  running && brew.liveReadings.isNotEmpty
                      ? formatClock(brew.elapsedMs / 1000)
                      : null,
                  '',
                ),
                LiveStat(
                  'Weight',
                  running && brew.liveReadings.isNotEmpty
                      ? brew.grams.toStringAsFixed(1)
                      : null,
                  'g',
                  color: context.colors.sensorMid,
                ),
                LiveStat(
                  'Flow',
                  running && brew.liveReadings.isNotEmpty
                      ? brew.flow.toStringAsFixed(1)
                      : null,
                  'g/s',
                  color: context.colors.sensorDown,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // In manual mode there are no pours to check off: the chart gets
            // the list's space.
            if (brew.manual)
              Expanded(
                child: _BrewChart(brew: brew, plan: plan),
              )
            else ...[
              SizedBox(
                height: 120,
                child: _BrewChart(brew: brew, plan: plan),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _StepList(plan: plan, brew: brew, running: running),
              ),
            ],
          ],
          const SizedBox(height: 8),
          AppButton(
            label: 'Finish',
            variant: AppButtonVariant.primary,
            onPressed: running ? brew.stopShot : null,
          ),
          const SizedBox(height: AppSpacing.tileActionBottom),
        ],
      ),
    );
  }
}

class _BrewChart extends StatelessWidget {
  const _BrewChart({required this.brew, required this.plan});

  final PourOverBrewService brew;
  final BrewPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final readings = brew.liveReadings;
    final lastS = readings.isEmpty ? 0.0 : readings.last.timeMs / 1000;
    final manual = brew.manual;
    // Manual mode has no planned duration: a three-minute window that grows.
    final maxX = math
        .max(manual ? 180.0 : plan.plannedSeconds * 1.1, lastS + 5)
        .ceilToDouble();
    final maxY = (plan.totalWaterG * 1.1).ceilToDouble();
    // Flow (g/s) on its own axis on the right: 0 … flowDialMax over the full
    // height, so it's as readable as the weight.
    final k = maxY / flowDialMax;

    final planSpots = <FlSpot>[
      if (!manual)
        for (var t = 0.0; t <= maxX; t += 1) FlSpot(t, plan.targetAt(t)),
    ];
    final weightSpots = [
      for (final r in readings) FlSpot(r.timeMs / 1000, r.weight ?? 0),
    ];
    final flowSpots = [
      for (final r in readings)
        FlSpot(r.timeMs / 1000, ((r.flow ?? 0) * k).clamp(0, maxY)),
    ];

    // Bands: per plan, shifted to the actual start of each pour once it has
    // started.
    final starts = plan.plannedStepStarts;
    final actual = <int, double>{};
    for (final r in readings) {
      for (var i = actual.length; i < plan.steps.length; i++) {
        if ((r.weight ?? 0) <= plan.steps[i].startTotalG + 1) break;
        actual[i] = r.timeMs / 1000;
      }
    }
    double startOf(int i) => actual[i] ?? starts[i];

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY / 2,
          getDrawingHorizontalLine: (v) => FlLine(
            color: colors.divider,
            strokeWidth: 1,
            dashArray: v == 0 ? null : const [2, 4],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: maxY / 2,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  (v / k).toStringAsFixed(0),
                  style: TextStyle(color: colors.sensorDown, fontSize: 10),
                ),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: maxY / 2,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  v.toStringAsFixed(0),
                  style: TextStyle(color: colors.textSecondary, fontSize: 10),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: maxX <= 120 ? 30 : 60,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  formatClock(v),
                  style: TextStyle(color: colors.textSecondary, fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: [
            for (var i = 0; i < (manual ? 0 : plan.steps.length); i++)
              VerticalRangeAnnotation(
                x1: startOf(i),
                x2: i + 1 < plan.steps.length ? startOf(i + 1) : maxX,
                color: i == brew.stepIndex && brew.stage == ShotStage.running
                    ? colors.accent.withValues(alpha: 0.10)
                    : (i.isEven
                          ? colors.textPrimary.withValues(alpha: 0.028)
                          : Colors.transparent),
              ),
          ],
        ),
        // In manual mode, only the target water as a line instead of the
        // plan line.
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (manual)
              HorizontalLine(
                y: plan.totalWaterG,
                color: colors.textTertiary,
                strokeWidth: 1.4,
                dashArray: const [3, 4],
              ),
          ],
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: flowSpots,
            color: colors.sensorDown,
            barWidth: 1.8,
            isCurved: true,
            preventCurveOverShooting: true,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: colors.sensorDown.withValues(alpha: 0.12),
            ),
          ),
          LineChartBarData(
            spots: planSpots,
            color: colors.textTertiary,
            barWidth: 1.4,
            dashArray: const [3, 4],
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: weightSpots,
            color: colors.sensorMid,
            barWidth: 2.4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, bar) => spot == bar.spots.last,
              getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                radius: 3.5,
                color: colors.sensorMid,
                strokeWidth: 2,
                strokeColor: colors.card,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({
    required this.plan,
    required this.brew,
    required this.running,
  });

  final BrewPlan plan;
  final PourOverBrewService brew;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final current = running ? brew.stepIndex : -1;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: plan.steps.length,
      itemBuilder: (context, i) => _StepRow(
        step: plan.steps[i],
        done: running && i < current,
        active: i == current,
        waitingFor: i == current && brew.phase == BrewState.waiting
            ? brew.waitLeftSeconds
            : null,
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.done,
    required this.active,
    required this.waitingFor,
  });

  final BrewStep step;
  final bool done;
  final bool active;
  final double? waitingFor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final note = step.note;
    final wait = step.waitSeconds;
    final meta = [
      '${formatGrams(step.waterG)} g',
      'to ${formatGrams(step.targetTotalG)} g',
      if (wait != null && wait > 0) 'wait ${formatClock(wait)}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: active ? colors.accent.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              done
                  ? Icons.check_circle
                  : (active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
              size: 16,
              color: done || active ? colors.accent : colors.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    color: done ? colors.textSecondary : colors.textPrimary,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                Text(
                  waitingFor != null
                      ? 'Starts in ${formatClock(waitingFor!)} · $meta'
                      : meta,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
                if (active && note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
