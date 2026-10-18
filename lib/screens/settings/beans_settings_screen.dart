import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../beans/freshness.dart';
import 'beans_form_settings_screen.dart';
import 'settings_widgets.dart';

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
          // One card per settings page: what the bean list shows, then the
          // way to the form.
          SettingsCard(
            children: [
              SettingsGroup(
                label: 'Bean list',
                children: [
                  SettingsSwitchRow(
                    title: 'Freshness ring',
                    // The color legend is part of the ⓘ bubble.
                    info: 'Days since roast, or since thawing.',
                    infoExtra: const FreshnessLegend(),
                    value: settings.showFreshnessRing,
                    onChanged: settings.setShowFreshnessRing,
                  ),
                  SettingsSwitchRow(
                    title: 'Bag level',
                    info:
                        'Bag weight minus the dose of every shot. '
                        'Needs a bag weight.',
                    value: settings.showBeanStock,
                    onChanged: settings.setShowBeanStock,
                  ),
                ],
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
