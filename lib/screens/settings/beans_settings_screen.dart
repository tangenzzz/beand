import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/ai_settings.dart';
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
    final ai = context.watch<AiSettings>();
    // The same switch as Settings → AI → Features; without a key it does
    // nothing, so it stays greyed out.
    final aiReady = ai.enabled && ai.isConfigured;
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
              // The form and its AI fill belong together: one block, no
              // line between them (user 2026-10-22).
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsRow(
                    icon: Icons.dynamic_form_outlined,
                    title: 'Form',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BeansFormSettingsScreen(),
                      ),
                    ),
                  ),
                  // Like "AI analysis" in Settings → History: the same switch
                  // as in Settings → AI, grayed out and off without a key.
                  SettingsSwitchRow(
                    title: 'Fill bean form with AI',
                    info:
                        'Reads a bean from a photo of the packaging or from a '
                        'shop link. Needs an AI API key in Settings → AI.',
                    value: aiReady && ai.isFeatureOn(AiFeature.beanForm),
                    onChanged: aiReady
                        ? (v) => ai.setFeatureOn(AiFeature.beanForm, v)
                        : null,
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
