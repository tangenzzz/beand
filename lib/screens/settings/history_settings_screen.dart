import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/ai_settings.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/bean_icon.dart';
import 'settings_widgets.dart';
import '../../widgets/value_select_row.dart';

// History settings: which photo is shown in the circle on the shot
// (thumbnail), and which evaluations appear in the shot detail.
class HistorySettingsScreen extends StatelessWidget {
  const HistorySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final ai = context.watch<AiSettings>();
    final aiReady = ai.enabled && ai.isConfigured;
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          // One card per settings page: the list, the shot detail, then
          // comparing shots — one line between the blocks.
          SettingsCard(
            children: [
              const SettingsGroup(
                label: 'List',
                children: [_ThumbnailPicker()],
              ),
              SettingsGroup(
                label: 'Shot detail',
                children: [
                  SettingsSwitchRow(
                    title: 'Local analysis',
                    info:
                        'Findings under the chart, worked out on the phone. '
                        'Espresso only.',
                    value: settings.showShotFacts,
                    onChanged: settings.setShowShotFacts,
                  ),
                  // The same switch as in Settings → AI, repeated here because
                  // it determines what the shot detail shows. Grayed out and off
                  // when no AI is set up.
                  SettingsSwitchRow(
                    title: 'AI analysis',
                    info:
                        'Comments on a shot and suggests what to change. '
                        'Espresso only. Needs an AI API key in Settings → AI.',
                    value: aiReady && ai.isFeatureOn(AiFeature.shotAnalysis),
                    onChanged: aiReady
                        ? (value) =>
                              ai.setFeatureOn(AiFeature.shotAnalysis, value)
                        : null,
                  ),
                ],
              ),
              SettingsGroup(
                label: 'Compare',
                children: [
                  SettingsSwitchRow(
                    title: 'Grind from zero',
                    info:
                        'Next to the grind: how far it was from the zero '
                        'point that day. Compares shots fairly after you '
                        'reset the zero point.',
                    value: settings.showGrindFromZero,
                    onChanged: settings.setShowGrindFromZero,
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

// Thumbnail: which photo is shown in the circle on the shot — the app's
// value row with its inline choice list.
class _ThumbnailPicker extends StatelessWidget {
  const _ThumbnailPicker();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return ValueSelectRow<HistoryAvatar>(
      key: const ValueKey('thumbnail-picker'),
      label: 'Thumbnail',
      labelWidth: 96,
      labelSize: settingsValueLabelSize,
      labelColor: context.colors.textPrimary,
      horizontalPadding: AppSpacing.dividerInset,
      isLast: true,
      value: settings.historyAvatar,
      options: [
        for (final choice in HistoryAvatar.values)
          ValueOption(
            value: choice,
            title: choice.label,
            // The same bean as in the tab bar.
            leading: choice == HistoryAvatar.bean
                ? const BeanIcon(size: 16)
                : Icon(
                    Icons.tune,
                    size: 16,
                    color: context.colors.textSecondary,
                  ),
          ),
      ],
      onChanged: settings.setHistoryAvatar,
    );
  }
}
