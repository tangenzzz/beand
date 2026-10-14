import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../services/brew_recipe_store.dart';
import '../../theme/app_theme.dart';
import 'pourover_profiles_screen.dart';

// Settings → Home → Pour Over: the switch for the pill on Home and the way
// to the profiles available for selection. One card per page.
class PourOverSettingsScreen extends StatelessWidget {
  const PourOverSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final store = context.watch<BrewRecipeStore>();
    final colors = context.colors;
    final fresh = store.newCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Pour Over')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          // Material instead of a colored Container, otherwise the
          // background hides the ListTiles' tap animation.
          Material(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppRadii.tile),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.dividerInset,
                    vertical: 4,
                  ),
                  secondary: Icon(
                    Icons.water_drop_outlined,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                  title: Text(
                    'Show in Home',
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                  ),
                  value: settings.isHomeModeEnabled(HomeMode.pourOver),
                  onChanged: (v) =>
                      settings.setHomeModeEnabled(HomeMode.pourOver, v),
                ),
                Divider(
                  height: 1,
                  indent: AppSpacing.dividerInset,
                  endIndent: AppSpacing.dividerInset,
                  color: colors.divider,
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.dividerInset,
                    vertical: 4,
                  ),
                  leading: Icon(
                    Icons.tune,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                  title: Text(
                    'Profiles',
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                  ),
                  subtitle: Text(
                    '${store.enabledRecipes.length} of ${store.recipes.length} selected'
                    '${fresh > 0 ? ' · $fresh new' : ''}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: colors.textSecondary,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PourOverProfilesScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
