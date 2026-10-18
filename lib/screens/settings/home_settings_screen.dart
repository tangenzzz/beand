import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../machines/gaggimate/gaggimate_service.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import 'pourover_settings_screen.dart';
import 'settings_widgets.dart';

// Settings → Home: one switch per view that shows or hides the matching
// pill at the top left of the Home tab. Pour Over instead leads to its own
// page with a switch and profiles.
class HomeSettingsScreen extends StatelessWidget {
  const HomeSettingsScreen({super.key});

  static const _icons = {
    HomeMode.meticulous: Icons.coffee_maker_outlined,
    HomeMode.pourOver: Icons.water_drop_outlined,
    HomeMode.gaggimate: Icons.coffee_outlined,
  };

  // The GaggiMate only keeps its connection while its pill is shown —
  // otherwise everyone without a GaggiMate would run a reconnect loop into
  // nothing (see main.dart).
  static void _setEnabled(BuildContext context, HomeMode mode, bool value) {
    context.read<AppSettings>().setHomeModeEnabled(mode, value);
    if (mode != HomeMode.gaggimate) return;
    final service = context.read<GaggiMateService>();
    value ? service.connect() : service.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          // One block: the views are siblings, no lines between them.
          SettingsCard(
            children: [
              SettingsGroup(
                label: 'Show on Home',
                children: [
                  for (final mode in HomeMode.values)
                    // Pour Over has its own page (switch + profiles) — here
                    // only the way there.
                    if (mode == HomeMode.pourOver)
                      SettingsRow(
                        icon: _icons[mode],
                        title: mode.label,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PourOverSettingsScreen(),
                          ),
                        ),
                      )
                    else
                      SettingsSwitchRow(
                        icon: _icons[mode],
                        title: mode.label,
                        value: settings.isHomeModeEnabled(mode),
                        onChanged: (value) => _setEnabled(context, mode, value),
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
