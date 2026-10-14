import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/meticulous_socket_service.dart';
import '../../theme/app_theme.dart';
import 'sweeping_icon.dart';

// Command buttons below the temperature widget: a neutral row without its
// own card, set off from the rest of the list by thin dividers.
// Preheat/Purge/Raise trigger real machine actions via REST (see
// MeticulousSocketService.triggerAction); the weight button only shows
// the live value so far.
//
// Purge and Raise show that they are running: the arrow lights up from its
// start to its tip (SweepingIcon) and the button ignores taps meanwhile.
// The actual problem was not missing feedback but repeated triggering —
// tapping Purge four times meant four piston runs. A spinner during the
// request would be useless for that: the machine answers in 30–105 ms
// (measured live), whereas the movement takes ~13 s.
//
// What "running" depends on: the machine names the running action itself
// in the status stream (`name`/`phase` is `purge` or `home`, then `idle`
// again). So no duration is estimated or derived from the motor — and so
// the button also lights up when the movement was triggered at the
// machine's dial.
//
// Preheat does not need this: it can be cancelled and already shows its
// state by turning into "Stop" (isPreheatActive). Tare moves nothing and
// never shows up in `phase`.
class CommandButtonsRow extends StatefulWidget {
  const CommandButtonsRow({super.key});

  @override
  State<CommandButtonsRow> createState() => _CommandButtonsRowState();
}

class _CommandButtonsRowState extends State<CommandButtonsRow> {
  // Which `phase` the machine reports while the action runs. Only these
  // two are trackable; everything else works as before.
  static const _phaseOfAction = {'purge': 'purge', 'home': 'home'};

  // Time between the accepted request and the expected phase. Measured, it
  // switches after ~0.2 s; if it has not switched by then, the command was
  // accepted but had no effect. The button then unlocks again, without a
  // message.
  static const _phaseGrace = Duration(seconds: 2);

  // Action whose request went through but whose phase has not been
  // reported yet. Only for this short window — after that `phase` carries
  // the state.
  String? _pending;
  Timer? _pendingTimer;

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  String? _runningAction(MeticulousSocketService service) {
    final phase = service.latestStatus?.phase;
    if (phase == null) return null;
    for (final entry in _phaseOfAction.entries) {
      if (entry.value == phase) return entry.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MeticulousSocketService>();
    final weight = service.latestStatus?.weight;
    final isPreheating = service.isPreheatActive;
    final busy = _runningAction(service) ?? _pending;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: context.colors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _CommandButton(
                  icon: isPreheating
                      ? Icons.stop_circle_outlined
                      : Icons.local_fire_department_outlined,
                  label: isPreheating ? 'Stop' : 'Preheat',
                  // Preheating takes ~10 minutes and has no movement that
                  // could sweep: the icon stays in the accent color the
                  // whole time.
                  active: isPreheating,
                  onTap: () => isPreheating
                      ? _runAction(action: 'reset', label: 'Stop')
                      : _runAction(action: 'preheat', label: 'Preheat'),
                ),
                _CommandButton(
                  icon: Icons.balance,
                  label: weight == null
                      ? '—'
                      : '${weight.toStringAsFixed(1)} g',
                  onTap: () => _runAction(action: 'tare', label: 'Tare'),
                ),
                _CommandButton(
                  icon: Icons.arrow_downward,
                  label: 'Purge',
                  sweepDirection: AxisDirection.down,
                  // Only the affected button locks: the user still has the
                  // other actions at hand meanwhile.
                  busy: busy == 'purge',
                  onTap: busy == 'purge'
                      ? null
                      : () => _runAction(action: 'purge', label: 'Purge'),
                ),
                _CommandButton(
                  icon: Icons.arrow_upward,
                  label: 'Raise',
                  sweepDirection: AxisDirection.up,
                  busy: busy == 'home',
                  onTap: busy == 'home'
                      ? null
                      : () => _runAction(action: 'home', label: 'Raise'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
        ],
      ),
    );
  }

  Future<void> _runAction({
    required String action,
    required String label,
  }) async {
    final service = context.read<MeticulousSocketService>();
    final ok = await service.triggerAction(action);
    if (!mounted) return;
    if (ok && _phaseOfAction.containsKey(action)) {
      // The glow IS the feedback — a snackbar would only claim what you
      // can already see. And it would have lied: previously the app
      // reported "triggered" even when nothing happened.
      setState(() => _pending = action);
      _pendingTimer?.cancel();
      _pendingTimer = Timer(_phaseGrace, () {
        if (mounted) setState(() => _pending = null);
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '$label triggered' : '$label failed'),
        // Flutter's default duration (4s) halved.
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.busy = false,
    this.sweepDirection,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  // Persistent state: the icon glows until it is over. Only the icon —
  // the word below stays neutral; in the active state it already switches
  // to "Stop" anyway.
  final bool active;
  // While the action is running, the arrow lights up in its direction.
  final bool busy;
  final AxisDirection? sweepDirection;

  // Fixed width so a longer/shorter live weight (e.g. "-90.4 g" vs.
  // "0.0 g") does not shift the neighboring buttons in the row.
  static const _width = 76.0;

  @override
  Widget build(BuildContext context) {
    // The running button is NOT dimmed: the glow shows the state, a dimmed
    // button next to it would just look broken.
    final color = context.colors.textSecondary;
    final iconColor = active ? context.colors.accent : color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sweepDirection == null)
                Icon(icon, color: iconColor, size: 24)
              else
                SweepingIcon(
                  icon: icon,
                  active: busy,
                  baseColor: iconColor,
                  glowColor: context.colors.accent,
                  direction: sweepDirection!,
                ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
