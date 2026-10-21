import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../models/shot_phases.dart';
import '../../services/live_shot_service.dart';
import '../../services/shot_setup.dart';
import '../../theme/app_theme.dart';
import '../history/history_logic.dart';
import '../history/shot_chart.dart';
import '../../widgets/app_button.dart';
import 'pulsing_glow.dart';
import 'tile_title.dart';

// "Shot" card: live chart during the brew (Yield/Flow/Pressure, same design
// as ShotDetailScreen), afterwards the finished chart until the purge.
//
// Layout: Time/Yield/Flow/Pressure, the chart including stages and the
// button must ALWAYS be visible without scrolling — only the remaining
// figures (Temp/Dose/Ratio/Grind) sit above and need a scroll up. That's
// why the chart is deliberately kept short. The card also shows the empty
// axes and the value row as soon as you switch to it, instead of a
// placeholder text — so it visibly waits for the tare point from which
// recording starts.
class ShotLiveCard extends StatefulWidget {
  const ShotLiveCard({super.key});

  @override
  State<ShotLiveCard> createState() => _ShotLiveCardState();
}

class _ShotLiveCardState extends State<ShotLiveCard> {
  int? _cursorMs;
  ShotStage? _lastStage;
  Timer? _cursorRelease;

  // How long a cursor set by hand holds during the brew before the value
  // row follows the newest data point again.
  static const _cursorHold = Duration(seconds: 3);

  void _setCursor(int ms, {required bool running}) {
    setState(() => _cursorMs = ms);
    _cursorRelease?.cancel();
    if (!running) return;
    _cursorRelease = Timer(_cursorHold, () {
      if (!mounted) return;
      if (context.read<LiveShotService>().stage != ShotStage.running) return;
      setState(() => _cursorMs = null);
    });
  }

  @override
  void dispose() {
    _cursorRelease?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = context.select<LiveShotService, ShotStage>((s) => s.stage);
    final service = context.watch<LiveShotService>();
    final readings = service.liveReadings;
    final phases = service.livePhases;
    final target = context.select<LiveShotService, double?>(
      (s) => s.targetTemperature,
    );
    final tracksTemperature = context.select<LiveShotService, bool>(
      (s) => s.tracksTemperature,
    );
    final setup = context.watch<ShotSetup>();

    // A cursor set by hand (or by a carousel swipe that started on the
    // chart) used to stick — even into the next shot, since this state
    // outlives the cycle — and froze the value row at an old moment, e.g. a
    // negative flow from the lead-in for the whole brew. Now each shot
    // starts without a cursor, and during the brew a hand-set one lets go
    // again after [_cursorHold] (see _setCursor).
    final running = stage == ShotStage.running;
    if (running && _lastStage != ShotStage.running) {
      _cursorRelease?.cancel();
      _cursorMs = null;
    }
    _lastStage = stage;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: _Body(
        readings: readings,
        phases: phases,
        stage: stage,
        isActiveCard: service.activeCard == ActiveCard.live,
        target: target,
        tracksTemperature: tracksTemperature,
        dose: setup.doseGrams,
        grind: setup.grindSize,
        cursorMs: _cursorMs,
        onCursorChanged: (ms) => _setCursor(ms, running: running),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.readings,
    required this.phases,
    required this.stage,
    required this.isActiveCard,
    required this.target,
    required this.tracksTemperature,
    required this.dose,
    required this.grind,
    required this.cursorMs,
    required this.onCursorChanged,
  });

  final List<ShotReading> readings;
  final List<ShotPhase> phases;
  final ShotStage stage;
  final bool isActiveCard;
  final double? target;
  // Machine with a boiler sensor (GaggiMate): red curve in the chart and a
  // fifth TEMP column in the value row.
  final bool tracksTemperature;
  // Empty as long as nothing has been brewed with the profile.
  final double? dose;
  final double? grind;
  final int? cursorMs;
  final ValueChanged<int> onCursorChanged;

  // Fixed time window for the live chart: it starts at the y-axis and moves
  // to the right, instead of the axis growing with every data point. If the
  // shot runs longer, the window jumps ahead in a few large steps instead
  // of constantly compressing.
  static const _windowSteps = [30.0, 45.0, 60.0, 90.0, 120.0];

  static double _timeWindow(List<ShotReading> readings) {
    final elapsed = readings.isEmpty ? 0.0 : readings.last.timeMs / 1000;
    for (final step in _windowSteps) {
      if (elapsed <= step) return step;
    }
    return (elapsed / 30).ceil() * 30;
  }

  // Chart height chosen so that value row + chart + stage bar + button fit
  // in the card together without scrolling. Scales with the card height.
  static const _chartHeight = 137.0;

  @override
  Widget build(BuildContext context) {
    final effectiveCursor =
        cursorMs ?? (readings.isEmpty ? 0 : readings.last.timeMs);
    final atCursor = readings.isEmpty
        ? null
        : readingNear(readings, effectiveCursor);
    final ratio = (dose ?? 0) > 0 ? (atCursor?.weight ?? 0) / dose! : 0.0;

    // Everything in the card's height, without scrolling: since the Chain
    // row made the carousel taller (2026-10-20) the setup row fits above the
    // live values all the time — no scrolling up after the shot any more.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TileTitle(short: 'LIVE', active: isActiveCard),
          const SizedBox(height: 8),
          // The setup of this shot; Ratio follows the yield.
          Row(
            children: [
              // The machine's target, not a measured value.
              LiveStat('Target', target?.toStringAsFixed(0), '°C'),
              LiveStat('Dose', dose == null ? '—' : grams(dose!), 'g'),
              LiveStat('Ratio', '1:${ratio.toStringAsFixed(1)}', ''),
              LiveStat('Grind', grind?.toStringAsFixed(1) ?? '—', ''),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              LiveStat(
                'Time',
                readings.isEmpty ? null : seconds(effectiveCursor),
                's',
              ),
              LiveStat(
                'Yield',
                atCursor?.weight?.toStringAsFixed(1),
                'g',
                color: context.colors.sensorMid,
              ),
              LiveStat(
                'Flow',
                atCursor?.flow?.toStringAsFixed(1),
                'ml/s',
                color: context.colors.sensorDown,
              ),
              LiveStat(
                // Five columns need the short form, otherwise the
                // labels wrap.
                tracksTemperature ? 'Press' : 'Pressure',
                atCursor?.pressure?.toStringAsFixed(1),
                'bar',
                color: context.colors.success,
              ),
              if (tracksTemperature)
                LiveStat(
                  'Temp',
                  atCursor?.barUp?.toStringAsFixed(1),
                  '°C',
                  color: context.colors.danger,
                ),
            ],
          ),
          const SizedBox(height: 6),
          ShotChart(
            readings: readings,
            phases: phases,
            cursorMs: effectiveCursor,
            onCursorChanged: onCursorChanged,
            height: _chartHeight,
            minWindowSeconds: _timeWindow(readings),
            showTemperature: tracksTemperature,
            temperatureTarget: target,
          ),
          const Spacer(),
          _ActionButton(stage: stage),
          const SizedBox(height: AppSpacing.tileActionBottom),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.stage});

  final ShotStage stage;

  static Future<void> _run(
    BuildContext context, {
    required Future<bool> Function() action,
    required String label,
  }) async {
    final ok = await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '$label triggered' : '$label failed'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (label, onTap) = switch (stage) {
      ShotStage.running => (
        'Stop',
        () => _run(
          context,
          action: () => context.read<LiveShotService>().stopShot(),
          label: 'Stop',
        ),
      ),
      ShotStage.awaitingPurge => (
        'Purge',
        () => _run(
          context,
          action: () => context.read<LiveShotService>().purge(),
          label: 'Purge',
        ),
      ),
      ShotStage.purging => ('Purging…', null),
      _ => ('No shot running', null),
    };

    return PulsingGlow(
      active: stage == ShotStage.awaitingPurge,
      color: context.colors.accent,
      child: AppButton(label: label, onPressed: onTap),
    );
  }
}

// Value column above the live chart (abbreviation, value below in the curve
// color). Public because the Pour Over live brew card shows the same row.
class LiveStat extends StatelessWidget {
  const LiveStat(this.label, this.value, this.unit, {super.key, this.color});

  final String label;
  final String? value;
  final String unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: context.colors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value ?? '–',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color ?? context.colors.textPrimary,
                  ),
                ),
                if (value != null && unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
