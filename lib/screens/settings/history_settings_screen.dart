import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/ai_settings.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/bean_icon.dart';
import 'settings_widgets.dart';
import '../../widgets/app_switch_tile.dart';
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
          // One card per settings page.
          SettingsCard(
            children: [
              const _ThumbnailPicker(),
              _Switch(
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
              _Switch(
                title: 'AI analysis',
                info:
                    'Comments on a shot and suggests what to change. '
                    'Espresso only. Needs an AI API key in Settings → AI.',
                value: aiReady && ai.isFeatureOn(AiFeature.shotAnalysis),
                onChanged: aiReady
                    ? (value) => ai.setFeatureOn(AiFeature.shotAnalysis, value)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Explanations only behind ⓘ, no subtitle.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.title,
    required this.info,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String info;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSwitchTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.dividerInset,
        vertical: 6,
      ),
      title: SettingsTitle(title, info: info),
      value: value,
      onChanged: onChanged,
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
