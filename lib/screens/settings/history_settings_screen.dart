import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/ai_settings.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/bean_icon.dart';
import 'settings_widgets.dart';
import '../../widgets/app_switch_tile.dart';

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

// Thumbnail: which photo is shown in the circle on the shot. Expandable list
// in the card like the model picker under AI (dropdown, ⓘ only on the title,
// not on the options). With two entries, no search/plus row.
class _ThumbnailPicker extends StatefulWidget {
  const _ThumbnailPicker();

  @override
  State<_ThumbnailPicker> createState() => _ThumbnailPickerState();
}

class _ThumbnailPickerState extends State<_ThumbnailPicker> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('thumbnail-picker'),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.dividerInset,
              vertical: 14,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SettingsTitle(
                        'Thumbnail',
                        info:
                            'Which photo each shot shows in the History list.',
                      ),
                      const SizedBox(height: 3),
                      Text(
                        settings.historyAvatar.label,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final choice in HistoryAvatar.values)
            SettingsChoiceRow(
              icon: choice == HistoryAvatar.bean ? null : Icons.tune,
              // The same bean as in the tab bar.
              leading: choice == HistoryAvatar.bean
                  ? const BeanIcon(size: 16)
                  : null,
              title: choice.label,
              compact: true,
              selected: settings.historyAvatar == choice,
              onTap: () {
                settings.setHistoryAvatar(choice);
                setState(() => _open = false);
              },
            ),
      ],
    );
  }
}
