import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../machines/gaggimate/gaggimate_service.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import 'pourover_settings_screen.dart';

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
          // Material instead of a colored Container, otherwise the
          // background hides the ListTile's tap animation.
          Material(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(AppRadii.tile),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final mode in HomeMode.values) ...[
                  // Pour Over has its own page (switch + profiles) — here
                  // only the way there.
                  if (mode == HomeMode.pourOver)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.dividerInset,
                        vertical: 4,
                      ),
                      leading: Icon(
                        _icons[mode],
                        color: context.colors.textSecondary,
                        size: 20,
                      ),
                      title: Text(
                        mode.label,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: context.colors.textSecondary,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PourOverSettingsScreen(),
                        ),
                      ),
                    )
                  else
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.dividerInset,
                        vertical: 4,
                      ),
                      secondary: Icon(
                        _icons[mode],
                        color: context.colors.textSecondary,
                        size: 20,
                      ),
                      title: Text(
                        mode.label,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      value: settings.isHomeModeEnabled(mode),
                      onChanged: (value) => _setEnabled(context, mode, value),
                    ),
                  if (mode != HomeMode.values.last)
                    Divider(
                      height: 1,
                      indent: AppSpacing.dividerInset,
                      endIndent: AppSpacing.dividerInset,
                      color: context.colors.divider,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
