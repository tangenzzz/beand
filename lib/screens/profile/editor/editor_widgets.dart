import 'package:flutter/material.dart';

import '../../../models/profile_rules.dart';
import '../../../theme/app_theme.dart';

// Shared building blocks of the profile editor. The profile page and the
// stage page share sections, sliders, value rows and the display of rule
// findings.

// ------------------------------------------------------------- Sections

// As in the profile view: everything sits in ONE card, sections are only
// separated by a line.
class EditorSection extends StatelessWidget {
  const EditorSection({super.key, required this.child, this.first = false});

  final Widget child;
  final bool first;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!first) Divider(height: 1, color: context.colors.divider),
      Padding(padding: const EdgeInsets.all(14), child: child),
    ],
  );
}

class EditorSectionLabel extends StatelessWidget {
  const EditorSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.colors.textTertiary,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
      ),
    );
    if (trailing == null) return label;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [label, trailing!],
    );
  }
}

// The large card that holds the whole editor.
class EditorCard extends StatelessWidget {
  const EditorCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(AppRadii.tile),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

// ------------------------------------------------------------- Inputs

// Label on the left, value on the right, slider below — the layout both
// reference apps use for temperature and target weight.
class EditorSlider extends StatelessWidget {
  const EditorSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.format,
    this.divisions,
    this.color,
    this.hint,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double) format;
  final Color? color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = color ?? colors.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            Text(
              format(value),
              style: TextStyle(
                color: tint,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: tint,
            inactiveTrackColor: colors.divider,
            thumbColor: tint,
            overlayColor: tint.withValues(alpha: 0.12),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hint!,
              style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
            ),
          ),
      ],
    );
  }
}

// A number with −/+ for fine-tuning, optionally with a gear for binding to
// a variable. Corresponds to the "Selected point" card of the Meticulous app.
class EditorStepper extends StatelessWidget {
  const EditorStepper({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.onChanged,
    this.step = 0.1,
    this.min = 0,
    this.max = double.infinity,
    this.variableName,
    this.onVariable,
    this.color,
  });

  final String label;
  final double value;
  final String unit;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;

  // Set when the value is bound to a variable — then its name is shown
  // instead of the number.
  final String? variableName;
  final VoidCallback? onVariable;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = color ?? colors.accent;
    final bound = variableName != null;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ),
        if (bound)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              variableName!,
              style: TextStyle(
                color: tint,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Text(
          '${trimNumber(value)} $unit',
          style: TextStyle(
            color: bound ? colors.textTertiary : colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (onVariable != null)
          IconButton(
            tooltip: bound ? 'Variable' : 'Use variable',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.settings_outlined,
              size: 18,
              color: bound ? tint : colors.textTertiary,
            ),
            onPressed: onVariable,
          ),
        _StepButton(
          icon: Icons.remove,
          // A bound number can't be adjusted on its own — it belongs to the
          // variable.
          onTap: bound || value - step < min
              ? null
              : () => onChanged(_round(value - step)),
        ),
        _StepButton(
          icon: Icons.add,
          onTap: bound || value + step > max
              ? null
              : () => onChanged(_round(value + step)),
        ),
      ],
    );
  }

  double _round(double v) => (v * 100).round() / 100;
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.divider),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 34,
            child: Icon(
              icon,
              size: 18,
              color: onTap == null ? colors.textTertiary : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// Plain text field in the app's style.
class EditorField extends StatelessWidget {
  const EditorField({
    super.key,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
        counterStyle: TextStyle(color: colors.textTertiary, fontSize: 10),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- Findings

// The rule findings below each section. Errors red, safety notes in the
// warning color, the rest muted.
class FindingsList extends StatelessWidget {
  const FindingsList(this.findings, {super.key, this.dense = false});

  final List<RuleFinding> findings;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in findings)
          Padding(
            padding: EdgeInsets.only(bottom: dense ? 4 : 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1.5, right: 7),
                  child: Icon(
                    switch (f.severity) {
                      RuleSeverity.error => Icons.error_outline,
                      RuleSeverity.safety => Icons.warning_amber_rounded,
                      RuleSeverity.warning => Icons.info_outline,
                    },
                    size: 14,
                    color: _color(colors, f.severity),
                  ),
                ),
                Expanded(
                  child: Text(
                    f.message,
                    style: TextStyle(
                      color: _color(colors, f.severity),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Color _color(AppColors colors, RuleSeverity severity) =>
      switch (severity) {
        RuleSeverity.error => colors.danger,
        RuleSeverity.safety => colors.star,
        RuleSeverity.warning => colors.textTertiary,
      };
}

// ------------------------------------------------------------- Help

// The "?" from the reference apps: a short explanation as a bottom sheet.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: title,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    icon: Icon(
      Icons.help_outline,
      size: 16,
      color: context.colors.textTertiary,
    ),
    onPressed: () => showHelpSheet(context, title: title, body: body),
  );
}

Future<void> showHelpSheet(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final colors = context.colors;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.tile)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text('Got it', style: TextStyle(color: colors.accent)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------- Format

// Number without redundant zeros — same display as in the profile view.
String trimNumber(double v) {
  final rounded = (v * 100).round() / 100;
  if (rounded % 1 == 0) return rounded.toStringAsFixed(0);
  var s = rounded.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

// Unit per value type, matching unitFor() in models/profile_detail.dart.
String unitForType(String type) => switch (type) {
  'pressure' => 'bar',
  'flow' => 'ml/s',
  'power' => '%',
  'weight' => 'g',
  'time' => 's',
  'piston_position' => 'mm',
  _ => '',
};

// What a type is called in plain words.
String labelForType(String type) => switch (type) {
  'pressure' => 'Pressure',
  'flow' => 'Flow',
  'power' => 'Power',
  'weight' => 'Weight',
  'time' => 'Time',
  'piston_position' => 'Piston',
  'user_interaction' => 'Button press',
  _ => type,
};

// Upper bound per type for sliders and chart axis.
double maxForType(String type) => switch (type) {
  'pressure' => 12,
  'flow' => 12,
  'power' => 100,
  'weight' => 100,
  'time' => 180,
  'piston_position' => 100,
  _ => 100,
};

// Color of a stage type — same tokens as the curves in the profile view,
// so both views mean the same thing.
Color colorForStageType(BuildContext context, String type) {
  final colors = context.colors;
  return switch (type) {
    'flow' => colors.sensorDown,
    'pressure' => colors.success,
    'power' => colors.danger,
    'weight' => colors.sensorMid,
    'piston_position' => colors.sensorGroup,
    _ => colors.textSecondary,
  };
}

// Explanation texts, paraphrased from the official RFC of the profile format
// (MeticulousHome/espresso-profile-schema, rfc.md) and the hints of the two
// reference apps.
class EditorHelp {
  static const stages =
      'Stages are the steps of your shot. The machine runs them in order.\n\n'
      'Each stage steers one thing over time — pressure, flow or power — and '
      'hands over to the next one as soon as one of its exit conditions is met.';

  static const stageTypes =
      'Flow is how much water is pushed into the puck each second.\n\n'
      "Pressure is what you get when that water meets the puck's resistance. "
      'A pressure stage adjusts the flow by itself to follow your curve.\n\n'
      'Power drives the piston directly, as a percentage. A steady push can '
      'make the first seconds smoother and more repeatable, before the wet '
      'puck offers enough resistance for flow or pressure control.';

  static const exitTriggers =
      'Exit conditions decide when the machine moves on. If you set several, '
      'the first one reached wins.\n\n'
      'Time and weight can be counted from the start of the shot or from the '
      'start of this stage — "this stage" is usually what you want.\n\n'
      'With no exit condition at all, the stage runs until the profile\'s '
      'target weight is reached.';

  static const limits =
      'A limit caps one value for the whole stage without changing your curve.'
      '\n\n'
      'A flow stage should cap pressure, so a fine grind cannot spike it and '
      'stall the machine. A pressure stage should cap flow, so a coarse grind '
      'cannot gush.';

  static const variables =
      'A variable is a named value you set once and use in several places — '
      'points, limits or exit conditions.\n\n'
      'Change it, and everywhere it is used changes with it. Variables also '
      "show up on the machine's dial, so you can adjust them without opening "
      'the profile.';

  static const curve =
      'Press and hold an empty spot to add a point. Tap a point to select it, '
      'then use − and + below for exact values. Drag a point off the chart to '
      'remove it.\n\n'
      'Linear connects the points with straight lines, Curve rounds the '
      'corners.';

  static const targetWeight =
      'The target weight stops the whole shot, not just one stage — whichever '
      "comes first, this or the current stage's exit condition.";
}
