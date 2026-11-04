import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../scale/brew_scale.dart';
import '../../../scale/meticulous_scale.dart';
import '../../../scale/scale_selector.dart';
import '../../../services/pourover_brew_service.dart';
import '../../../theme/app_theme.dart';
import '../../root_scaffold.dart';
import '../../settings/scale_settings_screen.dart';

// Command row below the pour-over hero — the same shape as for the machines
// (CommandButtonsRow/GaggiMateCommandRow): neutral row without a card, thin
// dividers above and below, fixed-width buttons.
//
// Contents, in order: Profile ↔ Free Pour toggle, Tare, the scale (icon
// neutral like the other buttons — the colored status is in the pill at the
// top; a Bluetooth scale shows its name and battery, the Meticulous its
// mode "Machine" / "Scale only"; a tap chooses Meticulous Machine / Scale
// only or a Bluetooth scale, a long press opens Settings → Scale) and Auto.
// The same for every scale the app leads with. In Machine mode only two:
// the scale button and Last brew.
class PourOverCommandRow extends StatelessWidget {
  const PourOverCommandRow({super.key});

  @override
  Widget build(BuildContext context) {
    final scale = context.watch<BrewScale>();
    final brew = context.watch<PourOverBrewService>();
    final connected = scale.isConnected;
    final battery = scale.batteryPercent;
    final machine = scale.isMachineScale;

    // The Meticulous button says which way it runs (user 2026-11-04):
    // "Machine" (the dial leads) or "Scale only" (the app leads) — the
    // same icons as in the scale picker.
    final (IconData scaleIcon, String scaleLabel) = machine
        ? (brew.dialLeads
              ? (Icons.touch_app_outlined, 'Machine')
              : (Icons.coffee_maker_outlined, 'Scale only'))
        : switch (scale.connection) {
            // The battery level next to the name (the fourth button is
            // Auto now); red icon when low.
            ScaleConnection.connected => (
              Icons.bluetooth_connected,
              battery == null
                  ? scaleShortName(scale.deviceName)
                  : '${scaleShortName(scale.deviceName)} $battery%',
            ),
            ScaleConnection.scanning || ScaleConnection.connecting => (
              Icons.bluetooth_searching,
              'Searching',
            ),
            ScaleConnection.disconnected =>
              scale.error != null
                  ? (Icons.bluetooth_disabled, 'No scale')
                  : (Icons.bluetooth, 'Connect'),
          };

    final dial = machine && brew.dialLeads;
    final scaleButton = _CommandButton(
      icon: scaleIcon,
      iconColor: battery != null && battery <= 15
          ? context.colors.danger
          : null,
      label: scaleLabel,
      // Tap: choose the scale (Meticulous Machine / Scale only /
      // Bluetooth); long press: the scale settings.
      onTap: brew.profileLocked
          ? null
          : scale is ScaleSelector
          ? () => _chooseScale(context, scale, brew)
          : scale.connection == ScaleConnection.disconnected
          ? scale.connect
          : () => _openScaleSettings(context),
      onLongPress: () => _openScaleSettings(context),
    );

    // Machine mode (the dial leads) needs only two: the scale button (it
    // switches to Scale only too) and fetching the last brew. No Profile
    // (the dial picks it) and no Tare (a tare from the app would confuse
    // the dial's steps).
    final List<Widget> buttons = dial
        ? [
            scaleButton,
            _CommandButton(
              icon: Icons.download_outlined,
              label: 'Last brew',
              onTap: connected && !brew.profileLocked
                  ? () => _importLast(context, brew)
                  : null,
            ),
          ]
        : [
            // One button that toggles: icon and label show the current
            // mode. Disabled during the brew.
            _CommandButton(
              icon: brew.manual ? Icons.back_hand_outlined : Icons.tune,
              label: brew.manual ? 'Free Pour' : 'Profile',
              onTap: brew.profileLocked
                  ? null
                  : () => brew.setManual(!brew.manual),
            ),
            _CommandButton(
              // Same icon as Tare on the Meticulous, but with "Tare"
              // instead of the weight below — that is in the hero. During
              // the setup steps it records the current step.
              icon: Icons.balance,
              label: 'Tare',
              onTap: connected ? brew.tare : null,
            ),
            scaleButton,
            // Auto: weigh server, brewer and coffee by themselves, start
            // with the water, end when the brewer comes off. Tap switches,
            // long press starts the steps again. Any scale.
            _CommandButton(
              icon: Icons.auto_mode,
              iconColor: brew.auto ? context.colors.accent : null,
              label: brew.auto ? 'Auto on' : 'Auto off',
              onTap: brew.profileLocked ? null : () => brew.setAuto(!brew.auto),
              onLongPress: brew.auto && connected && !brew.profileLocked
                  ? brew.restartPrep
                  : null,
            ),
          ];

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
              children: buttons,
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
        ],
      ),
    );
  }

  static Future<void> _chooseScale(
    BuildContext context,
    ScaleSelector scale,
    PourOverBrewService brew,
  ) async {
    final colors = context.colors;
    final btName = scale.bluetooth.deviceName;
    final onMeticulous = scale.source == ScaleSource.meticulous;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.tile),
        ),
      ),
      builder: (context) {
        Widget option(
          Object value,
          IconData icon,
          String title,
          String subtitle, {
          required bool chosen,
        }) => ListTile(
          leading: Icon(icon, color: colors.textSecondary),
          title: Text(title, style: TextStyle(color: colors.textPrimary)),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
          trailing: chosen ? Icon(Icons.check, color: colors.success) : null,
          onTap: () => Navigator.pop(context, value),
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'SCALE',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              option(
                MeticulousPourMode.machine,
                Icons.touch_app_outlined,
                '${MeticulousScale.name} · Machine',
                'Brew on the machine, the brew comes to the app',
                chosen:
                    onMeticulous &&
                    brew.meticulousMode == MeticulousPourMode.machine,
              ),
              option(
                MeticulousPourMode.scaleOnly,
                Icons.coffee_maker_outlined,
                '${MeticulousScale.name} · Scale only',
                'The app leads, the machine weighs',
                chosen:
                    onMeticulous &&
                    brew.meticulousMode == MeticulousPourMode.scaleOnly,
              ),
              option(
                ScaleSource.bluetooth,
                Icons.bluetooth,
                'Bluetooth scale',
                btName == null
                    ? 'Acaia, Decent, Bookoo'
                    : scaleShortName(btName),
                chosen: !onMeticulous,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, 'settings'),
                  child: Text(
                    'Scale settings ›',
                    style: TextStyle(color: colors.accent, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted) return;
    if (choice == 'settings') {
      _openScaleSettings(context);
    } else if (choice is MeticulousPourMode) {
      brew.setMeticulousMode(choice);
      scale.setSource(ScaleSource.meticulous);
    } else if (choice == ScaleSource.bluetooth) {
      scale.setSource(ScaleSource.bluetooth);
      // A Bluetooth scale that is not connected yet connects right away.
      if (scale.connection == ScaleConnection.disconnected &&
          scale.bluetooth.rememberedId != null) {
        unawaited(scale.connect());
      }
    }
  }

  static Future<void> _importLast(
    BuildContext context,
    PourOverBrewService brew,
  ) async {
    final added = await brew.importLastDialBrew();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Brew taken from the machine' : 'No new brew on the machine',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static void _openScaleSettings(BuildContext context) {
    final nav = RootNavigation.maybeOf(context);
    if (nav?.openSettingsPage != null) {
      nav!.openSettingsPage!((_) => const ScaleSettingsScreen());
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ScaleSettingsScreen()),
      );
    }
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? iconColor;

  // As for the machines: fixed width so changing labels
  // ("Searching" ↔ "Pearl") do not shift the neighbors.
  static const _width = 76.0;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.textSecondary;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: iconColor ?? color),
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
