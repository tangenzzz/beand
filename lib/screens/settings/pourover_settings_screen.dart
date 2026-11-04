import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../services/pourover_brew_service.dart';
import '../../widgets/underline_select.dart';
import '../../theme/app_theme.dart';
import 'settings_widgets.dart';

// Settings → Home → Pour Over: the switch for the pill on Home and who
// leads on the Meticulous. Profiles are gathered with "+" on the profile
// row (user 2026-11-04), no longer here. One card per page.
class PourOverSettingsScreen extends StatelessWidget {
  const PourOverSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    // Always there in the app; null in tests that only build this page.
    final brew = context.watch<PourOverBrewService?>();
    return Scaffold(
      appBar: AppBar(title: const Text('Pour Over')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              SettingsGroup(
                children: [
                  SettingsSwitchRow(
                    icon: Icons.water_drop_outlined,
                    title: 'Show on Home',
                    value: settings.isHomeModeEnabled(HomeMode.pourOver),
                    onChanged: (v) =>
                        settings.setHomeModeEnabled(HomeMode.pourOver, v),
                  ),
                ],
              ),
              // Who leads when the Meticulous' built-in scale is used.
              if (brew != null)
                SettingsGroup(
                  label: 'Meticulous',
                  info:
                      'Machine: you brew on the machine, the app shows weight, '
                      'flow and time and takes the finished brew with your '
                      'Pre Brew data. Scale only: the app leads with its own '
                      'steps and timer, the machine is just the scale.',
                  children: [
                    SettingsSection(
                      title: 'Mode',
                      child: UnderlineSelect<MeticulousPourMode>(
                        options: const [
                          UnderlineOption(
                            MeticulousPourMode.machine,
                            'Machine',
                          ),
                          UnderlineOption(
                            MeticulousPourMode.scaleOnly,
                            'Scale only',
                          ),
                        ],
                        value: brew.meticulousMode,
                        onChanged: (v) {
                          if (v != null) brew.setMeticulousMode(v);
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
