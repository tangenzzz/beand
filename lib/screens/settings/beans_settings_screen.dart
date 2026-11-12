import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/ai_settings.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/value_select_row.dart';
import '../beans/freshness.dart';
import '../live/ruler_picker.dart';
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
                    info: 'Days since roast, without time in the freezer.',
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
                  const _EmptyBelowRow(),
                ],
              ),
              // The form and its AI fill belong together: one block, no
              // line between them (user 2026-10-22).
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsRow(
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

// Empty below: a shot or brew that leaves less in the bag marks it as
// empty (BagEmptyWatcher). The same ruler as for the dose, in whole grams;
// 0 = off. Grayed out without the bag level, which it counts on.
class _EmptyBelowRow extends StatelessWidget {
  const _EmptyBelowRow();

  static const max = 30.0;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final grams = settings.emptyBelowGrams;
    final enabled = settings.showBeanStock;
    return ValueSelectRow<void>.custom(
      key: const ValueKey('empty-below'),
      label: 'Empty below',
      labelWidth: 120,
      labelSize: settingsValueLabelSize,
      labelColor: enabled ? context.colors.textPrimary : null,
      labelSuffix: const Padding(
        padding: EdgeInsets.only(left: 4),
        child: SettingsInfo(
          'After a shot or brew leaves less than this in the bag, it is '
          'marked as empty. 0 = off.',
        ),
      ),
      horizontalPadding: AppSpacing.dividerInset,
      enabled: enabled,
      dimValue: grams <= 0,
      valueText: grams <= 0 ? 'Off' : '${grams.round()} g',
      panel: RulerPicker(
        value: grams.clamp(0, max),
        min: 0,
        max: max,
        step: 1,
        unit: 'g',
        onChanged: (v) => settings.setEmptyBelowGrams(v.roundToDouble()),
      ),
    );
  }
}
