import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../scale/brew_scale.dart';
import '../../../services/pourover_brew_service.dart';
import '../../../theme/app_theme.dart';
import '../../root_scaffold.dart';
import '../../settings/scale_settings_screen.dart';

// Command row below the pour-over hero — the same shape as for the machines
// (CommandButtonsRow/GaggiMateCommandRow): neutral row without a card, thin
// dividers above and below, fixed-width buttons.
//
// Contents, in order: Profile ↔ Manual toggle, Tare, the connected scale
// (Bluetooth icon neutral like the other buttons — the colored status is in
// the pill at the top; a tap connects or opens Settings → Bluetooth Scale)
// and the scale's battery level.
class PourOverCommandRow extends StatelessWidget {
  const PourOverCommandRow({super.key});

  @override
  Widget build(BuildContext context) {
    final scale = context.watch<BrewScale>();
    final brew = context.watch<PourOverBrewService>();
    final connected = scale.isConnected;
    final battery = scale.batteryPercent;

    final (IconData scaleIcon, String scaleLabel) = switch (scale.connection) {
      ScaleConnection.connected => (
        Icons.bluetooth_connected,
        scaleShortName(scale.deviceName),
      ),
      ScaleConnection.scanning ||
      ScaleConnection.connecting => (Icons.bluetooth_searching, 'Searching'),
      ScaleConnection.disconnected =>
        scale.error != null
            ? (Icons.bluetooth_disabled, 'No scale')
            : (Icons.bluetooth, 'Connect'),
    };

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
                // One button that toggles: icon and label show the current
                // mode. Disabled during the brew.
                _CommandButton(
                  icon: brew.manual ? Icons.back_hand_outlined : Icons.tune,
                  label: brew.manual ? 'Manual' : 'Profile',
                  onTap: brew.profileLocked
                      ? null
                      : () => brew.setManual(!brew.manual),
                ),
                _CommandButton(
                  // Same icon as Tare on the Meticulous, but with "Tare"
                  // instead of the weight below — that is in the hero.
                  icon: Icons.balance,
                  label: 'Tare',
                  onTap: connected ? scale.tare : null,
                ),
                _CommandButton(
                  icon: scaleIcon,
                  label: scaleLabel,
                  onTap: scale.connection == ScaleConnection.disconnected
                      ? scale.connect
                      : () => _openScaleSettings(context),
                  onLongPress: () => _openScaleSettings(context),
                ),
                _CommandButton(
                  icon: _batteryIcon(battery),
                  iconColor: battery != null && battery <= 15
                      ? context.colors.danger
                      : null,
                  label: battery == null ? '—' : '$battery %',
                  onTap: null,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
        ],
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

  static IconData _batteryIcon(int? percent) {
    if (percent == null) return Icons.battery_unknown_outlined;
    if (percent >= 95) return Icons.battery_full;
    const bars = [
      Icons.battery_0_bar,
      Icons.battery_1_bar,
      Icons.battery_2_bar,
      Icons.battery_3_bar,
      Icons.battery_4_bar,
      Icons.battery_5_bar,
      Icons.battery_6_bar,
    ];
    return bars[(percent / 100 * 7).floor().clamp(0, 6)];
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
