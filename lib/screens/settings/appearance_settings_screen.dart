import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/underline_select.dart';
import 'settings_widgets.dart';

// Settings → Appearance: appearance and accent color. Both apply
// immediately — the preview at the top is no mock-up but the same building
// blocks as everywhere, so it shows every change right away too.
class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          // One block: theme and accent belong together, no line between.
          SettingsCard(
            children: [
              SettingsGroup(
                children: [
                  SettingsSection(
                    title: 'Theme',
                    child: UnderlineSelect<AppThemeMode>(
                      options: [
                        for (final mode in AppThemeMode.values)
                          UnderlineOption(mode, mode.label),
                      ],
                      value: settings.themeMode,
                      onChanged: (mode) => settings.setThemeMode(mode!),
                    ),
                  ),
                  SettingsSection(
                    title: 'Accent color',
                    child: _AccentSwatches(
                      value: settings.accent,
                      onChanged: settings.setAccent,
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

// The six accent colors as circles. Not selected: outline only — selected:
// the circle is filled, i.e. the same dot marker as on the pills.
class _AccentSwatches extends StatelessWidget {
  const _AccentSwatches({required this.value, required this.onChanged});

  final AppAccent value;
  final ValueChanged<AppAccent> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final variant = Theme.of(context).brightness == Brightness.light
        ? AppThemeVariant.light
        : AppThemeVariant.dark;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final accent in AppAccent.values)
          InkWell(
            onTap: () => onChanged(accent),
            borderRadius: BorderRadius.circular(AppRadii.button),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTapTarget,
                minWidth: AppSpacing.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent == value
                            ? accent.forVariant(variant)
                            : Colors.transparent,
                        border: Border.all(
                          color: accent.forVariant(variant),
                          width: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      accent.label,
                      style: TextStyle(
                        color: accent == value
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontSize: 11,
                        fontWeight: accent == value
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
