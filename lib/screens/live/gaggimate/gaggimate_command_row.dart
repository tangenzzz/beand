import 'package:flutter/material.dart';

import '../../../machines/espresso_machine.dart';
import '../../../machines/gaggimate/gaggimate_service.dart';
import '../../../machines/gaggimate/gaggimate_status.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/gaggimate_icons.dart';

// Command row below the hero card — same shape as on the Meticulous
// (CommandButtonsRow): neutral row without its own card, framed by thin
// dividers above and below, four buttons with fixed width.
//
// Content is machine-specific: the GaggiMate has no actions like
// Purge/Raise, but has modes (Brew/Steam/Water, `req:change-mode`) and
// rinsing. The active mode is shown in the accent color.
//
// While a steam, water or rinse process is running, its button becomes a
// stop button. These three are not part of the shot cycle and so have no
// stop in the live card — without this one they couldn't be ended from the
// app at all. Verified on the simulator: `req:process:deactivate` ends
// steam and water, a rinse is only ended by `req:process:deactivate`
// (see GaggiMateService).
//
// Water takes two steps: the first tap sets the mode, the second runs water
// (`req:process:activate` starts a PumpProcess in water mode,
// Controller.cpp). Previously the button only set the mode and no water
// ever came.
class GaggiMateCommandRow extends StatelessWidget {
  const GaggiMateCommandRow({super.key, required this.service});

  final GaggiMateService service;

  @override
  Widget build(BuildContext context) {
    final status = service.status;
    final mode = status.mode ?? GaggiMateMode.standby;
    final connected =
        service.connectionState == MachineConnectionState.connected;
    final process = status.process;
    // The firmware marks a rinse as a utility process — that's how we
    // recognize it even after an app restart.
    final flushing = process?.utility == true && process!.active;
    // Steam or water: same process block, but reported empty. Which of the
    // two it is comes from the machine mode.
    final drawing = process != null && process.active && process.isUtilityDraw;

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
                  glyph: GaggiMateGlyph.brew,
                  icon: null,
                  label: 'Brew',
                  active: mode == GaggiMateMode.brew,
                  onTap: connected
                      ? () => service.changeMode(GaggiMateMode.brew)
                      : null,
                ),
                _CommandButton(
                  glyph: drawing && mode == GaggiMateMode.steam
                      ? null
                      : GaggiMateGlyph.steam,
                  icon: drawing && mode == GaggiMateMode.steam
                      ? Icons.stop_circle_outlined
                      : null,
                  label: drawing && mode == GaggiMateMode.steam
                      ? 'Stop'
                      : 'Steam',
                  active: mode == GaggiMateMode.steam,
                  onTap: !connected
                      ? null
                      : drawing && mode == GaggiMateMode.steam
                      ? () => _stopDraw(context, service)
                      : () => service.changeMode(GaggiMateMode.steam),
                ),
                _CommandButton(
                  glyph: drawing && mode == GaggiMateMode.water
                      ? null
                      : GaggiMateGlyph.water,
                  icon: drawing && mode == GaggiMateMode.water
                      ? Icons.stop_circle_outlined
                      : null,
                  label: drawing && mode == GaggiMateMode.water
                      ? 'Stop'
                      : 'Water',
                  active: mode == GaggiMateMode.water,
                  onTap: !connected
                      ? null
                      : drawing && mode == GaggiMateMode.water
                      ? () => _stopDraw(context, service)
                      : mode == GaggiMateMode.water
                      ? () => _startDraw(context, service)
                      : () => service.changeMode(GaggiMateMode.water),
                ),
                _CommandButton(
                  glyph: null,
                  icon: flushing
                      ? Icons.stop_circle_outlined
                      : Icons.shower_outlined,
                  // The machine's icons fill their box completely, Material
                  // icons have padding inside: at 24 the shower head only
                  // reaches two thirds of their height (measured on the
                  // device). The stop circle, on the other hand, fills
                  // almost the whole box and therefore stays at 24.
                  iconSize: flushing ? null : 32,
                  // And it sits lower in its box than the others: measured on
                  // the device its drawing started 4 px below the machine
                  // icons, shrinking the gap to the label from 12 to 8 px.
                  iconNudgeY: flushing ? 0 : -4,
                  label: flushing ? 'Stop' : 'Flush',
                  active: flushing,
                  onTap: connected
                      ? () => _flush(context, service, running: flushing)
                      : null,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
        ],
      ),
    );
  }

  static Future<void> _startDraw(
    BuildContext context,
    GaggiMateService service,
  ) async {
    final ok = await service.sendCommand(MachineCommand.start);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Start failed'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  static Future<void> _stopDraw(
    BuildContext context,
    GaggiMateService service,
  ) async {
    final ok = await service.sendCommand(MachineCommand.stop);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stop failed'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  static Future<void> _flush(
    BuildContext context,
    GaggiMateService service, {
    required bool running,
  }) async {
    final ok = await service.sendCommand(
      running ? MachineCommand.flushStop : MachineCommand.flushStart,
    );
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Flush failed'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.glyph,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.iconSize,
    this.iconNudgeY = 0,
  });

  // Either the machine's icon (modes) or one from the Material set (stop,
  // rinse) — the GaggiMate only brings its own for its three modes.
  final GaggiMateGlyph? glyph;
  final IconData? icon;
  final double? iconSize;
  final double iconNudgeY;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  static const _width = 76.0;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? context.colors.textTertiary
        : active
        ? context.colors.accent
        : context.colors.textSecondary;
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
              if (glyph != null)
                GaggiMateIcon(glyph!, size: 24, color: color)
              else
                SizedBox(
                  // Fixed height so a larger-drawn icon doesn't push the row
                  // apart.
                  height: 24,
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(0, iconNudgeY),
                      child: Icon(icon, color: color, size: iconSize ?? 24),
                    ),
                  ),
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
