import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/grinder.dart';
import '../../models/water.dart';
import '../../services/grinder_store.dart';
import '../../services/water_store.dart';
import '../../theme/app_theme.dart';
import 'my_setup_dialogs.dart';
import 'settings_widgets.dart';

// Settings → My Setup: the user's own equipment in ONE card — "Grinders"
// and below it "Water", each with "+" at the far right. A grinder shows all
// its burr sets with the fitted one ticked (tap to switch); tapping a name
// edits the entry.
class MySetupScreen extends StatelessWidget {
  const MySetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final grinders = context.watch<GrinderStore>().grinders;
    final waters = context.watch<WaterStore>().waters;
    return Scaffold(
      appBar: AppBar(title: const Text('My Setup')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              _SectionHeader(
                title: 'Grinders',
                addTooltip: 'Add grinder',
                onAdd: () => showGrinderDialog(context),
              ),
              if (grinders.isEmpty) const _Empty('No grinders yet.'),
              for (final g in grinders) _GrinderSection(grinder: g),
              _SectionHeader(
                title: 'Water',
                addTooltip: 'Add water',
                onAdd: () => showWaterDialog(context),
              ),
              if (waters.isEmpty) const _Empty('No water recipes yet.'),
              for (final w in waters) _WaterRow(water: w),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.addTooltip,
    required this.onAdd,
  });

  final String title;
  final String addTooltip;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.dividerInset, 4, 4, 0),
      child: Row(
        children: [
          Expanded(child: SettingsTitle(title)),
          IconButton(
            tooltip: addTooltip,
            icon: Icon(Icons.add, color: context.colors.textSecondary),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.dividerInset,
      0,
      AppSpacing.dividerInset,
      14,
    ),
    child: Text(
      text,
      style: TextStyle(color: context.colors.textTertiary, fontSize: 13),
    ),
  );
}

class _GrinderSection extends StatelessWidget {
  const _GrinderSection({required this.grinder});

  final Grinder grinder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => showGrinderDialog(context, grinder: grinder),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.dividerInset,
              10,
              AppSpacing.dividerInset,
              grinder.burrs.isEmpty ? 12 : 2,
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  if (grinder.brand != null)
                    TextSpan(
                      text: '${grinder.brand}  ',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  TextSpan(
                    text: grinder.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ),
        for (final burr in grinder.burrs)
          SettingsChoiceRow(
            compact: true,
            leading: const SizedBox.shrink(),
            title: burr,
            selected: burr == grinder.activeBurrs,
            onTap: () =>
                context.read<GrinderStore>().setActiveBurr(grinder.id, burr),
          ),
        if (grinder.burrs.isNotEmpty) const SizedBox(height: 4),
      ],
    );
  }
}

class _WaterRow extends StatelessWidget {
  const _WaterRow({required this.water});

  final Water water;

  static String _n(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final details = [
      if (water.gh != null) 'GH ${_n(water.gh!)}',
      if (water.kh != null) 'KH ${_n(water.kh!)}',
      if (water.ppm != null) '${_n(water.ppm!)} ppm',
      ?water.use?.label,
    ].join(' · ');
    return InkWell(
      onTap: () => showWaterDialog(context, water: water),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.dividerInset,
          10,
          AppSpacing.dividerInset,
          12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              water.recipe,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                details,
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
