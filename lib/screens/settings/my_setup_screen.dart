import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/grinder.dart';
import '../../models/water.dart';
import '../../services/grinder_store.dart';
import '../../services/water_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/underline_select.dart';
import 'my_setup_dialogs.dart';
import 'settings_widgets.dart';

// Settings → My Setup: the user's own equipment in ONE card — "Grinders"
// and below it "Water", each section with its icon and "+" at the far
// right. A grinder shows brand + name and its burr sets as choices (the
// fitted one has the dot, tap to switch); a water shows GH and KH as bars
// so recipes compare at a glance. Tapping a name opens the form.
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
          // One divider only: between the two sections, not between their
          // entries.
          SettingsCard(
            children: [
              SettingsGroup(
                label: 'Grinders',
                icon: Icons.blender_outlined,
                trailing: _AddButton(
                  tooltip: 'Add grinder',
                  onPressed: () => showGrinderDialog(context),
                ),
                children: [
                  if (grinders.isEmpty)
                    const _Empty('Add your grinder to see it on every shot.'),
                  for (final g in grinders) _GrinderEntry(grinder: g),
                ],
              ),
              SettingsGroup(
                label: 'Water',
                icon: Icons.water_drop_outlined,
                trailing: _AddButton(
                  tooltip: 'Add water',
                  onPressed: () => showWaterDialog(context),
                ),
                children: [
                  if (waters.isEmpty)
                    const _Empty('Add a water recipe to keep its minerals.'),
                  for (final w in waters) _WaterEntry(water: w),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: Icon(Icons.add, color: context.colors.textSecondary),
    onPressed: onPressed,
  );
}

// An empty section is just one short line — no box, the "+" is right above.
class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.dividerInset,
      0,
      AppSpacing.dividerInset,
      16,
    ),
    child: Text(
      text,
      style: TextStyle(color: context.colors.textTertiary, fontSize: 13),
    ),
  );
}

class _GrinderEntry extends StatelessWidget {
  const _GrinderEntry({required this.grinder});

  final Grinder grinder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => showGrinderDialog(context, grinder: grinder),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.dividerInset,
          12,
          AppSpacing.dividerInset,
          12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  if (grinder.brand != null)
                    TextSpan(
                      text: '${grinder.brand}  ',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  TextSpan(
                    text: grinder.name,
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 15),
            ),
            if (grinder.burrs.isNotEmpty) ...[
              const SizedBox(height: 4),
              // The fitted burr set has the dot; tap another to switch.
              UnderlineSelect<String>(
                options: [for (final b in grinder.burrs) UnderlineOption(b, b)],
                value: grinder.activeBurrs,
                onChanged: (b) {
                  if (b != null) {
                    context.read<GrinderStore>().setActiveBurr(grinder.id, b);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WaterEntry extends StatelessWidget {
  const _WaterEntry({required this.water});

  final Water water;

  static String _n(double v, {int digits = 1}) =>
      v.toStringAsFixed(digits).replaceFirst(RegExp(r'\.?0+$'), '');

  // "Epsom salt 0.12 g · Calcium chloride 0.05 g" — grams per litre of each
  // ticked mineral, in the order of the list.
  String _composition(Set<Mineral> minerals) => [
    for (final m in Mineral.values)
      if (minerals.contains(m))
        water.amounts[m] == null
            ? m.label
            : '${m.label} ${_n(water.amounts[m]!, digits: 3)} g',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final use = switch (water.use) {
      WaterUse.both => 'Espresso · Pour Over',
      final u? => u.label,
      null => null,
    };
    return InkWell(
      onTap: () => showWaterDialog(context, water: water),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.dividerInset,
          12,
          AppSpacing.dividerInset,
          14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    water.recipe,
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                  ),
                ),
                if (use != null)
                  Text(
                    use,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
            if (water.gh != null || water.ghMinerals.isNotEmpty)
              _HardnessLine(
                label: 'GH',
                value: water.gh,
                composition: _composition(water.ghMinerals),
              ),
            if (water.kh != null || water.khMinerals.isNotEmpty)
              _HardnessLine(
                label: 'KH',
                value: water.kh,
                composition: _composition(water.khMinerals),
              ),
          ],
        ),
      ),
    );
  }
}

// "GH  68 ppm   Epsom salt 0.12 g · Calcium chloride 0.05 g".
class _HardnessLine extends StatelessWidget {
  const _HardnessLine({
    required this.label,
    required this.value,
    required this.composition,
  });

  final String label;
  final double? value;
  final String composition;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              value == null ? '—' : '${_WaterEntry._n(value!)} ppm',
              style: TextStyle(color: colors.textPrimary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              composition,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
