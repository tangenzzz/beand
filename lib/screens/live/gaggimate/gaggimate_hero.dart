import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../machines/espresso_machine.dart';
import '../../../machines/gaggimate/gaggimate_service.dart';
import '../../../theme/app_theme.dart';
import '../sensor_stack.dart';
import '../temperature_ring.dart';

// GaggiMate hero area: ring on the left, next to it on the right the three
// values of this machine — in the same column as the four sensors of the
// Meticulous (SensorStack: both sides should look the same).
//
// Unlike the Meticulous it does NOT sit in a card — the background belongs
// to the screen, the area is framed only by the dividers of the command
// row below.
//
// The ring has only ONE arc here: the Meticulous outer ring shows
// "Stabilized", and that band is calibrated to its four sensors — with a
// single sensor there is nothing to compare.
//
// Deliberately without ETA: the ETA model of the Meticulous card is
// calibrated on real recordings of that machine and would be pure
// invention for a Gaggia. The ring only shows preheat progress, the line
// below Ready/Heating.
class GaggiMateHero extends StatefulWidget {
  const GaggiMateHero({super.key, required this.service});

  final GaggiMateService service;

  @override
  State<GaggiMateHero> createState() => _GaggiMateHeroState();
}

class _GaggiMateHeroState extends State<GaggiMateHero> {
  // As with the Meticulous, "ready" applies shortly before the target —
  // the controller oscillates around the setpoint, it is never hit exactly.
  static const _readyMargin = 2.0;

  // Both machines show the same ring diameter (see TemperatureRing) —
  // hence the shared value instead of a separate number that can drift.
  // Gap to the ring, width and row spacing of the column live in
  // SensorStack, also shared by both machines.
  static const _ringSize = TemperatureRing.defaultSize;

  // Start temperature of the current preheat: without it the ring would
  // already be 20/93 = 21% full at room temperature, instead of 0.
  double? _startTemp;
  double? _startTarget;

  // "+2" expanded? Without this the collapsed warnings could not be read
  // in the app at all.
  bool _warningsExpanded = false;

  void _trackHeating(double? temp, double? target) {
    if (temp == null || target == null || target <= 0) {
      _startTemp = null;
      _startTarget = null;
      return;
    }
    // New target (profile change, steam mode) → restart progress.
    if (_startTarget != null && (_startTarget! - target).abs() > 0.5) {
      _startTemp = null;
    }
    _startTarget = target;
    if (temp >= target - _readyMargin) {
      _startTemp = null; // done heating
    } else {
      _startTemp ??= temp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.service.liveState;
    final caps = widget.service.capabilities;
    final temp = live.temperature;
    final target = live.targetTemperature;
    _trackHeating(temp, target);

    final ready =
        temp != null && target != null && temp >= target - _readyMargin;
    double progress = 0;
    if (ready) {
      progress = 1;
    } else if (temp != null && target != null && _startTemp != null) {
      final span = (target - _readyMargin) - _startTemp!;
      if (span > 0.5) progress = ((temp - _startTemp!) / span).clamp(0.0, 1.0);
    }

    final offline =
        widget.service.connectionState != MachineConnectionState.connected;
    final String status;
    final Color statusColor;
    if (offline) {
      status = 'Offline';
      statusColor = context.colors.textSecondary;
    } else if (live.systemStatus == MachineSystemStatus.error) {
      status = 'Error';
      statusColor = context.colors.danger;
    } else if (live.systemStatus != MachineSystemStatus.ready &&
        live.systemStatus != MachineSystemStatus.busy) {
      // starting / waiting / updating: the machine's own text says more
      // than a text of our own.
      status = live.systemMessage?.isNotEmpty == true
          ? live.systemMessage!
          : live.systemStatus.name;
      statusColor = context.colors.sensorMid;
    } else if (ready) {
      status = 'Ready';
      statusColor = context.colors.heroRingReady;
    } else {
      status = 'Heating';
      statusColor = context.colors.heroRingHeating;
    }

    final warnings = live.visibleWarnings;

    // The three fields are ALWAYS shown, even if the machine does not
    // provide the value (pressure/flow only on the Pro, weight only with a
    // paired scale) — dimmed with "—" then, instead of the area changing
    // shape as soon as a scale is added.
    final values = <SensorValue>[
      SensorValue(
        'BAR',
        caps.pressure ? live.pressure : null,
        context.colors.success,
      ),
      SensorValue(
        'ML/S',
        caps.flow ? live.flow : null,
        context.colors.sensorDown,
      ),
      SensorValue(
        'G',
        caps.weight ? live.weight : null,
        context.colors.sensorMid,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            // The group is centered instead of sticking to the left edge —
            // the ring needs room on the left, otherwise the area looks off.
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TemperatureRing(
                size: _ringSize,
                heroValue: temp,
                targetTemp: target,
                progress: offline ? 0 : progress,
                // One ring, no "Stabilized" outer ring.
                outerProgress: null,
                color: ready
                    ? context.colors.heroRingReady
                    : context.colors.heroRingHeating,
                statusText: status,
                statusColor: statusColor,
                showCheck: ready,
              ),
              const SizedBox(width: SensorStack.ringToValues),
              SensorStack(sensors: values, dimMissing: true),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _WarningLines(
              warnings: warnings,
              expanded: _warningsExpanded,
              onToggle: () =>
                  setState(() => _warningsExpanded = !_warningsExpanded),
            ),
          ],
        ],
      ),
    );
  }
}

// Machine warnings as narrow rows: a small dot in the severity color,
// followed by the plain text. The firmware knows six
// (src/display/core/WarningManager.h) that can be active at the same time —
// so at most two rows are shown, the rest collects behind a "+n". Blocking
// warnings (severity "error") are never collapsed, even if there are more
// than two: they hold up the brew.
class _WarningLines extends StatelessWidget {
  const _WarningLines({
    required this.warnings,
    required this.expanded,
    required this.onToggle,
  });

  final List<MachineWarning> warnings;
  final bool expanded;
  final VoidCallback onToggle;

  static const _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...warnings.where((w) => w.isBlocking),
      ...warnings.where((w) => !w.isBlocking),
    ];
    final blocking = ordered.where((w) => w.isBlocking).length;
    final budget = math.max(blocking, _maxLines);
    // Whether there is anything to collapse depends on the set, not the
    // state: if a warning disappears while expanded, no "less" without
    // content may remain.
    final collapsible = ordered.length > budget;
    final visible = (expanded && collapsible ? ordered : ordered.take(budget))
        .toList();
    final hidden = ordered.length - visible.length;

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _WarningLine(
              warning: visible[i],
              // The "+n" hangs on the last visible row, so it does not need
              // its own almost empty row.
              trailing: i == visible.length - 1 && collapsible
                  ? (expanded ? 'less' : '+$hidden')
                  : null,
              onTrailingTap: onToggle,
            ),
          ],
        ],
      ),
    );
  }
}

class _WarningLine extends StatelessWidget {
  const _WarningLine({
    required this.warning,
    required this.trailing,
    required this.onTrailingTap,
  });

  final MachineWarning warning;
  final String? trailing;
  final VoidCallback onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final color = warning.isBlocking
        ? context.colors.danger
        : context.colors.sensorMid;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          warning.label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTrailingTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              // Tap area slightly larger than the text.
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                trailing!,
                style: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
