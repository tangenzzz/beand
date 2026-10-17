import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/grinder.dart';
import '../../models/water.dart';
import '../../services/grinder_store.dart';
import '../../services/water_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dot_choice_group.dart';
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
              _Section(
                children: [
                  _SectionHeader(
                    icon: Icons.blender_outlined,
                    title: 'Grinders',
                    addTooltip: 'Add grinder',
                    onAdd: () => showGrinderDialog(context),
                  ),
                  if (grinders.isEmpty)
                    const _Empty('Add your grinder to see it on every shot.'),
                  for (final g in grinders) _GrinderEntry(grinder: g),
                ],
              ),
              _Section(
                children: [
                  _SectionHeader(
                    icon: Icons.water_drop_outlined,
                    title: 'Water',
                    addTooltip: 'Add water',
                    onAdd: () => showWaterDialog(context),
                  ),
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

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

// Small uppercase title with the section's icon; "+" at the far right.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.addTooltip,
    required this.onAdd,
  });

  final IconData icon;
  final String title;
  final String addTooltip;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.dividerInset, 4, 4, 0),
      child: Row(
        children: [
          Icon(icon, size: 17, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
          ),
          IconButton(
            tooltip: addTooltip,
            icon: Icon(Icons.add, color: colors.textSecondary),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
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
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 15),
            ),
            if (grinder.burrs.isNotEmpty) ...[
              const SizedBox(height: 4),
              // The fitted burr set has the dot; tap another to switch.
              DotChoiceGroup<String>(
                options: [for (final b in grinder.burrs) DotChoice(b, b)],
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

  // Bars run up to this value — enough for common brew waters (most stay
  // well below 150 ppm GH).
  static const _barMax = 150.0;

  static String _n(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final minerals = [
      for (final m in [...water.ghMinerals, ...water.khMinerals]) m.label,
    ].join(' · ');
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
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (water.ppm != null)
                  Text(
                    '${_n(water.ppm!)} ppm',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                if (water.use != null) ...[
                  if (water.ppm != null) const SizedBox(width: 10),
                  Text(
                    water.use!.label,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            ),
            if (water.gh != null)
              _HardnessBar(
                label: 'GH',
                value: water.gh!,
                max: _barMax,
                color: colors.sensorDown,
              ),
            if (water.kh != null)
              _HardnessBar(
                label: 'KH',
                value: water.kh!,
                max: _barMax,
                color: colors.success,
              ),
            if (minerals.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                minerals,
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HardnessBar extends StatelessWidget {
  const _HardnessBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  final String label;
  final double value;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (value / max).clamp(0.0, 1.0),
                minHeight: 6,
                color: color,
                backgroundColor: colors.divider,
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              '${_WaterEntry._n(value)} ppm',
              textAlign: TextAlign.right,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
