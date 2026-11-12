import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/value_select_row.dart';
import '../live/ruler_picker.dart';
import 'settings_widgets.dart';

// Settings → Beans → Bag level: one card — the switch for the remaining
// amount, below it Empty below, which counts on it.
class BagLevelSettingsScreen extends StatelessWidget {
  const BagLevelSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('Bag level')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              SettingsGroup(
                children: [
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
  static const _label = 'Empty below';

  // Label and ⓘ share the label column: measured, so the whole label stays
  // readable with any font size (the ⓘ takes about 32 px).
  static double _labelWidth(BuildContext context) {
    final painter = TextPainter(
      // The app's font, as the row draws it.
      text: TextSpan(
        text: _label,
        style: DefaultTextStyle.of(context).style
            .copyWith(fontSize: settingsValueLabelSize),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width.ceilToDouble() + 36;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final grams = settings.emptyBelowGrams;
    final enabled = settings.showBeanStock;
    return ValueSelectRow<void>.custom(
      key: const ValueKey('empty-below'),
      label: _label,
      labelWidth: _labelWidth(context),
      labelSize: settingsValueLabelSize,
      labelColor: enabled ? context.colors.textPrimary : null,
      labelSuffix: const Padding(
        padding: EdgeInsets.only(left: 4),
        child: SettingsInfo(
          'A bag below this is automatically marked as empty. 0 = off.',
        ),
      ),
      horizontalPadding: AppSpacing.dividerInset,
      isLast: true,
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
