import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../services/brew_recipe_store.dart';
import '../../theme/app_theme.dart';
import 'pourover_profiles_screen.dart';
import 'settings_widgets.dart';

// Settings → Home → Pour Over: the switch for the pill on Home and the way
// to the profiles available for selection. One card per page.
class PourOverSettingsScreen extends StatelessWidget {
  const PourOverSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final store = context.watch<BrewRecipeStore>();
    final fresh = store.newCount;
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
                  SettingsRow(
                    icon: Icons.tune,
                    title: 'Profiles',
                    subtitle:
                        '${store.enabledRecipes.length} of '
                        '${store.recipes.length} selected'
                        '${fresh > 0 ? ' · $fresh new' : ''}',
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
