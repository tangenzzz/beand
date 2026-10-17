import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../beans/freshness.dart';
import 'beans_form_settings_screen.dart';
import 'settings_widgets.dart';
import '../../widgets/app_switch_tile.dart';

class BeansSettingsScreen extends StatelessWidget {
  const BeansSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('Beans')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          // One card per settings page: switches and subpages are stacked
          // in the same container.
          SettingsCard(
            children: [
              AppSwitchTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.dividerInset,
                  vertical: 6,
                ),
                // The color legend is part of the ⓘ bubble.
                title: const SettingsTitle(
                  'Freshness ring',
                  info: 'Days since roast, or since thawing.',
                  infoExtra: FreshnessLegend(),
                ),
                value: settings.showFreshnessRing,
                onChanged: settings.setShowFreshnessRing,
              ),
              AppSwitchTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.dividerInset,
                  vertical: 6,
                ),
                title: const SettingsTitle(
                  'Bag level',
                  info:
                      'Bag weight minus the dose of every shot. '
                      'Needs a bag weight.',
                ),
                value: settings.showBeanStock,
                onChanged: settings.setShowBeanStock,
              ),
              SettingsRow(
                icon: Icons.dynamic_form_outlined,
                title: 'Form',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BeansFormSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
