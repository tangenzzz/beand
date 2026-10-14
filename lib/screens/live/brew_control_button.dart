import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/live_shot_service.dart';
import '../../theme/app_theme.dart';
import 'pulsing_glow.dart';

// The Pre-Shot card's button from "Start Profile" on: tapping the center
// starts the shot manually once the machine is ready ("click to start"), the
// small square on the right aborts (action/stop).
//
// No swipe gestures: Auto Start hangs on the checkbox above the button,
// aborting only via the square. The color stays the same as at rest
// throughout — only when the machine is ready AND the temperature has
// stabilized does the button pulse (see PulsingGlow).
class BrewControlButton extends StatelessWidget {
  const BrewControlButton({
    super.key,
    required this.stage,
    required this.stabilized,
    required this.heatingDots,
    required this.onStartShot,
    this.pulsesWhenReady = true,
  });

  final ShotStage stage;
  final bool stabilized;
  // See LiveShotService.pulsesWhenReady — with a machine that is
  // permanently ready in standby, the pulsing would never stop.
  final bool pulsesWhenReady;
  // Number of breathing dots after "Heating" (0..3) — its timer lives in the
  // parent (PreShotCard) so it doesn't restart on every rebuild of this
  // button. Deliberately the count instead of the finished text: the dots
  // get a fixed slot below so the word doesn't shift back and forth while
  // counting.
  final int heatingDots;
  final VoidCallback onStartShot;

  bool get _abortable =>
      stage == ShotStage.heating ||
      stage == ShotStage.ready ||
      stage == ShotStage.running;

  Future<void> _abort(BuildContext context) async {
    final ok = await context.read<LiveShotService>().stopShot();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Brew stopped' : 'Stop failed'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static TextStyle _labelStyle(BuildContext context) => TextStyle(
    color: context.colors.accent,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  Widget _label(BuildContext context) {
    if (stage == ShotStage.heating) {
      // There are ALWAYS three dots in the layout, the ones not currently
      // "breathing" are just transparent — otherwise the word shifts with
      // every dot.
      return Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Heating'),
            for (var i = 0; i < 3; i++)
              TextSpan(
                text: '.',
                style: i < heatingDots
                    ? null
                    : const TextStyle(color: Colors.transparent),
              ),
          ],
        ),
        style: _labelStyle(context),
      );
    }
    final text = switch (stage) {
      ShotStage.ready => stabilized ? 'Start Shot · Stable' : 'Start Shot',
      ShotStage.running => 'Shot running',
      _ => 'Shot in progress',
    };
    return Text(text, textAlign: TextAlign.center, style: _labelStyle(context));
  }

  @override
  Widget build(BuildContext context) {
    // Same outline style as AppButton (primary): no fill, a thin border,
    // the color is carried by the text alone. Custom build because the
    // abort button sits in the same pill on the right.
    final pill = Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.divider),
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: stage == ShotStage.ready ? onStartShot : null,
              child: Center(child: _label(context)),
            ),
          ),
          if (_abortable) ...[
            Container(width: 1, height: 22, color: context.colors.divider),
            IconButton(
              tooltip: 'Abort brew',
              icon: Icon(Icons.close, color: context.colors.accent, size: 18),
              onPressed: () => _abort(context),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );

    return PulsingGlow(
      active: pulsesWhenReady && stage == ShotStage.ready && stabilized,
      color: context.colors.accent,
      child: pill,
    );
  }
}
