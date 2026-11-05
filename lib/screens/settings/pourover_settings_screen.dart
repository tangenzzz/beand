import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../services/brew_recipe_store.dart';
import '../../theme/app_theme.dart';
import 'pourover_profiles_screen.dart';
import 'settings_widgets.dart';

// Settings → Home → Pour Over: the switch for the pill on Home and the profile
// collection (also via "+" on the profile row). Who leads on the Meticulous is
// chosen on Home, in the scale button's list. One card per page.
class PourOverSettingsScreen extends StatelessWidget {
  const PourOverSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final store = context.watch<BrewRecipeStore>();
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
                  // The collection to pick from (also reachable with "+" on
                  // the profile row on Home).
                  SettingsRow(
                    icon: Icons.tune,
                    title: 'Profiles',
                    subtitle:
                        '${store.ownRecipes.length} in use'
                        '${store.newCount > 0 ? ' · ${store.newCount} new' : ''}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PourOverProfilesScreen(),
                      ),
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
