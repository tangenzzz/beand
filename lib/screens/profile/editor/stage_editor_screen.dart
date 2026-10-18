import 'package:flutter/material.dart';

import '../../../models/profile_draft.dart';
import '../../../models/profile_rules.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_button.dart';
import 'editor_widgets.dart';
import 'stage_curve_editor.dart';
import 'variable_sheet.dart';
import '../../../widgets/underline_select.dart';
import '../../../widgets/value_select_row.dart';

// Edit a stage. A separate page instead of a section, so the chart, point
// fine-tuning and exit conditions have room side by side — the Meticulous
// app does it the same way.
//
// Work happens on a COPY of the draft: "Keep changes" returns it,
// "Discard" throws it away. Saving only happens on the profile page.
// Variables belong to the whole profile, so the complete draft travels
// along, not just the one stage.
class StageEditorScreen extends StatefulWidget {
  const StageEditorScreen({
    super.key,
    required this.draft,
    required this.stageIndex,
    required this.profileName,
  });

  final ProfileDraft draft;
  final int stageIndex;
  final String profileName;

  @override
  State<StageEditorScreen> createState() => _StageEditorScreenState();
}

class _StageEditorScreenState extends State<StageEditorScreen> {
  late final ProfileDraft _draft = widget.draft.copy();
  late final TextEditingController _name;
  int? _selectedPoint;

  DraftStage get _stage => _draft.stages[widget.stageIndex];
  bool get _isLast => widget.stageIndex == _draft.stages.length - 1;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _stage.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _touch() => setState(() {});

  // When the type changes, the old target values no longer fit (6 bar is
  // not 6 ml/s and certainly not 6 %) — so convert to sensible values and
  // switch the limit to the now matching counterpart quantity.
  void _changeType(String type) {
    if (type == _stage.type) return;
    final oldMax = chartMaxForType(_stage.type);
    final newMax = chartMaxForType(type);

    for (final p in _stage.points) {
      if (p.y.isVariable) continue;
      final scaled = (p.y.number ?? 0) / oldMax * newMax;
      final step = type == 'power' ? 1.0 : 0.1;
      p.y = DraftValue.number((scaled / step).round() * step);
    }

    _stage.type = type;
    _stage.limits.removeWhere((l) => l.type == type);
    _touch();
  }

  void _addPointAtEnd() {
    final lastX = _stage.points.isEmpty
        ? 0.0
        : (_stage.points.last.x.resolve(_draft.variables) ?? 0);
    final lastY = _stage.points.isEmpty
        ? 0.0
        : (_stage.points.last.y.resolve(_draft.variables) ?? 0);
    _stage.points.add(
      DraftPoint(DraftValue.number(lastX + 10), DraftValue.number(lastY)),
    );
    _selectedPoint = _stage.points.length - 1;
    _touch();
  }

  void _deleteSelectedPoint() {
    final index = _selectedPoint;
    if (index == null || index == 0 || _stage.points.length <= 2) return;
    _stage.points.removeAt(index);
    _selectedPoint = null;
    _touch();
  }

  // Bind a value to a variable or release the binding.
  Future<void> _bind(
    DraftValue current,
    String type,
    ValueChanged<DraftValue> apply,
  ) async {
    final result = await showVariableSheet(
      context,
      draft: _draft,
      current: current,
      type: type,
    );
    if (result == null) return;
    apply(result.value);
    _touch();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = colorForStageType(context, _stage.type);
    final findings = checkStage(_draft, widget.stageIndex);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // The back arrow discards, like "Discard changes".
        if (!didPop) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Text(
            _stage.name.trim().isEmpty ? 'Stage' : _stage.name.trim(),
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.tileOuterMargin,
                  0,
                  AppSpacing.tileOuterMargin,
                  AppSpacing.tileOuterMargin,
                ),
                children: [
                  EditorCard(
                    children: [
                      _nameAndType(tint),
                      _chart(tint),
                      if (_selectedPoint != null) _selectedPointCard(tint),
                      _limits(),
                      _exitTriggers(),
                      if (findings.isNotEmpty)
                        EditorSection(child: FindingsList(findings)),
                    ],
                  ),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- Name + type

  Widget _nameAndType(Color tint) => EditorSection(
    first: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EditorSectionLabel('Stage name'),
        const SizedBox(height: 8),
        EditorField(
          controller: _name,
          hint: 'Infusion',
          onChanged: (v) {
            _stage.name = v;
            _touch();
          },
        ),
        const SizedBox(height: 14),
        EditorSectionLabel(
          'Controls',
          trailing: const HelpButton(
            title: 'Stage controls',
            body: EditorHelp.stageTypes,
          ),
        ),
        const SizedBox(height: 8),
        // Underline choice; the line in the stage type's color.
        Wrap(
          spacing: UnderlineSelect.spacing,
          children: [
            for (final type in stageTypes)
              UnderlineItem(
                label: labelForType(type),
                underlineColor: colorForStageType(context, type),
                selected: _stage.type == type,
                onTap: () => _changeType(type),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          switch (_stage.type) {
            'pressure' =>
              'The machine adjusts flow by itself to follow this pressure '
                  'curve, up to the flow limit below.',
            'flow' =>
              'The machine pushes this much water per second, whatever '
                  'pressure the puck builds — up to the pressure limit below.',
            _ => 'The machine drives the piston with this much force.',
          },
          style: TextStyle(
            color: context.colors.textTertiary,
            fontSize: 11.5,
            height: 1.35,
          ),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------- Curve

  Widget _chart(Color tint) => EditorSection(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorSectionLabel(
          'Curve',
          trailing: Row(
            children: [
              _Segmented(
                options: const ['linear', 'curve'],
                labels: const ['Linear', 'Curve'],
                value: _stage.interpolation,
                onChanged: (v) {
                  _stage.interpolation = v;
                  _touch();
                },
              ),
              const HelpButton(
                title: 'Editing the curve',
                body: EditorHelp.curve,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        StageCurveEditor(
          stage: _stage,
          variables: _draft.variables,
          selected: _selectedPoint,
          onSelect: (i) => setState(() => _selectedPoint = i),
          onChanged: _touch,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                'Hold to add a point · tap to select · drag to move · drag off '
                'the chart to delete',
                style: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _addPointAtEnd,
              icon: Icon(Icons.add, size: 16, color: tint),
              label: Text('Point', style: TextStyle(color: tint, fontSize: 12)),
            ),
          ],
        ),
      ],
    ),
  );

  // -------------------------------------------------------- Selected point

  Widget _selectedPointCard(Color tint) {
    final index = _selectedPoint!;
    if (index >= _stage.points.length) return const SizedBox.shrink();
    final point = _stage.points[index];
    final unit = unitForType(_stage.type);

    String? nameOf(DraftValue v) {
      if (!v.isVariable) return null;
      for (final variable in _draft.variables) {
        if (variable.key == v.variableKey) return variable.name;
      }
      return v.variableKey;
    }

    return EditorSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorSectionLabel('Point ${index + 1} of ${_stage.points.length}'),
          const SizedBox(height: 10),
          EditorStepper(
            label: 'Time',
            value: point.x.resolve(_draft.variables) ?? 0,
            unit: 's',
            step: 0.5,
            // The start point stays at 0 — otherwise the stage starts from
            // nothing.
            max: index == 0 ? 0 : 600,
            variableName: nameOf(point.x),
            color: tint,
            onChanged: (v) {
              point.x = DraftValue.number(v);
              _touch();
            },
            onVariable: index == 0
                ? null
                : () => _bind(point.x, 'time', (v) => point.x = v),
          ),
          const SizedBox(height: 6),
          EditorStepper(
            label: labelForType(_stage.type),
            value: point.y.resolve(_draft.variables) ?? 0,
            unit: unit,
            step: _stage.type == 'power' ? 1 : 0.1,
            max: chartMaxForType(_stage.type),
            variableName: nameOf(point.y),
            color: tint,
            onChanged: (v) {
              point.y = DraftValue.number(v);
              _touch();
            },
            onVariable: () => _bind(point.y, _stage.type, (v) => point.y = v),
          ),
          const SizedBox(height: 10),
          if (index == 0)
            Text(
              'The 0 s start point stays where it is.',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 11.5,
              ),
            )
          else if (_stage.points.length > 2)
            AppButton(
              label: 'Remove point',
              icon: Icons.delete_outline,
              variant: AppButtonVariant.destructive,
              onPressed: _deleteSelectedPoint,
            )
          else
            Text(
              'A stage needs at least two points.',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 11.5,
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- Limits

  Widget _limits() {
    // The limit is always on the other quantity: a pressure stage limits
    // flow, a flow stage limits pressure. Power stages allow both.
    final options = _stage.type == 'power'
        ? limitTypes
        : limitTypes.where((t) => t != _stage.type).toList();

    return EditorSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorSectionLabel(
            'Limits',
            trailing: const HelpButton(
              title: 'Limits',
              body: EditorHelp.limits,
            ),
          ),
          const SizedBox(height: 4),
          for (final type in options) _limitRow(type),
        ],
      ),
    );
  }

  Widget _limitRow(String type) {
    final existing = _stage.limits.where((l) => l.type == type).firstOrNull;
    final tint = colorForStageType(context, type);

    if (existing == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            _stage.limits.add(
              DraftLimit(
                type: type,
                value: DraftValue.number(type == 'pressure' ? 10 : 5),
              ),
            );
            _touch();
          },
          icon: Icon(Icons.add, size: 16, color: tint),
          label: Text(
            'Limit ${labelForType(type).toLowerCase()}',
            style: TextStyle(color: tint, fontSize: 13),
          ),
        ),
      );
    }

    String? name;
    if (existing.value.isVariable) {
      name = existing.value.variableKey;
      for (final v in _draft.variables) {
        if (v.key == existing.value.variableKey) name = v.name;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: EditorStepper(
              label: 'Limit ${labelForType(type).toLowerCase()} to',
              value: existing.value.resolve(_draft.variables) ?? 0,
              unit: unitForType(type),
              step: type == 'pressure' ? 0.5 : 0.1,
              max: chartMaxForType(type),
              variableName: name,
              color: tint,
              onChanged: (v) {
                existing.value = DraftValue.number(v);
                _touch();
              },
              onVariable: () =>
                  _bind(existing.value, type, (v) => existing.value = v),
            ),
          ),
          IconButton(
            tooltip: 'Remove limit',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close,
              size: 16,
              color: context.colors.textTertiary,
            ),
            onPressed: () {
              _stage.limits.remove(existing);
              _touch();
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- Exit trigger

  Widget _exitTriggers() => EditorSection(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorSectionLabel(
          'Move on when',
          trailing: const HelpButton(
            title: 'Exit conditions',
            body: EditorHelp.exitTriggers,
          ),
        ),
        const SizedBox(height: 4),
        if (_stage.exitTriggers.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Whichever is reached first wins.',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 11.5,
              ),
            ),
          ),
        for (var i = 0; i < _stage.exitTriggers.length; i++)
          _triggerRow(_stage.exitTriggers[i]),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addTrigger,
            icon: Icon(Icons.add, size: 16, color: context.colors.accent),
            label: Text(
              'Condition',
              style: TextStyle(color: context.colors.accent, fontSize: 13),
            ),
          ),
        ),
        if (_isLast)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'This is the last stage — the shot ends as soon as one of these '
              'is met, even if ${trimNumber(_draft.finalWeight)} g has not been '
              'reached.',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
      ],
    ),
  );

  void _addTrigger() {
    // Time first, that's the most common case — and the safest fallback.
    final used = _stage.exitTriggers.map((t) => t.type).toSet();
    final type = exitTriggerTypes.firstWhere(
      (t) => !used.contains(t),
      orElse: () => 'time',
    );
    _stage.exitTriggers.add(
      DraftTrigger(
        type: type,
        value: DraftValue.number(switch (type) {
          'time' => 30,
          'weight' => 36,
          'pressure' => 9,
          'flow' => 2,
          _ => 0,
        }),
        relative: type == 'time',
      ),
    );
    _touch();
  }

  Widget _triggerRow(DraftTrigger trigger) {
    final colors = context.colors;
    final tint = colorForStageType(context, trigger.type);

    String? name;
    if (trigger.value.isVariable) {
      name = trigger.value.variableKey;
      for (final v in _draft.variables) {
        if (v.key == trigger.value.variableKey) name = v.name;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The app's value row; the type list folds out inline.
              Expanded(
                child: ValueSelectRow<String>(
                  label: 'Ends on',
                  labelWidth: 56,
                  isLast: true,
                  value: trigger.type,
                  options: [
                    for (final option in exitTriggerTypes)
                      ValueOption(value: option, title: labelForType(option)),
                  ],
                  onChanged: (v) {
                    trigger.type = v;
                    if (!trigger.needsValue) {
                      trigger.value = const DraftValue.number(0);
                    }
                    _touch();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Remove condition',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 16, color: colors.textTertiary),
                onPressed: () {
                  _stage.exitTriggers.remove(trigger);
                  _touch();
                },
              ),
            ],
          ),
          if (trigger.needsValue) ...[
            Row(
              children: [
                _ComparisonToggle(
                  value: trigger.comparison,
                  onChanged: (v) {
                    trigger.comparison = v;
                    _touch();
                  },
                ),
                Expanded(
                  child: EditorStepper(
                    label: '',
                    value: trigger.value.resolve(_draft.variables) ?? 0,
                    unit: unitForType(trigger.type),
                    step: trigger.type == 'time' ? 0.5 : 0.1,
                    max: trigger.type == 'time'
                        ? 600
                        : chartMaxForType(trigger.type),
                    variableName: name,
                    color: tint,
                    onChanged: (v) {
                      trigger.value = DraftValue.number(v);
                      _touch();
                    },
                    onVariable: () => _bind(
                      trigger.value,
                      trigger.type,
                      (v) => trigger.value = v,
                    ),
                  ),
                ),
              ],
            ),
            // The machine can count time and weight from shot start or from
            // the start of this stage. For everything else the question is
            // meaningless.
            if (trigger.type == 'time' || trigger.type == 'weight')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    _Segmented(
                      options: const [true, false],
                      labels: const ['This stage', 'Whole shot'],
                      value: trigger.relative,
                      onChanged: (v) {
                        trigger.relative = v;
                        _touch();
                      },
                    ),
                  ],
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Waits for a press of the machine dial.',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Footer

  Widget _footer() {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: colors.nav,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Keep changes applies this page to the profile. Nothing reaches '
            'the machine until you save the profile.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Discard',
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: 'Keep changes',
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(_draft),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Building blocks

// Two or three buttons, one of which is on.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.labels,
    required this.value,
    required this.onChanged,
  });

  final List<T> options;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            Material(
              color: options[i] == value
                  ? colors.accent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(i == 0 ? 9 : 0),
                right: Radius.circular(i == options.length - 1 ? 9 : 0),
              ),
              child: InkWell(
                onTap: () => onChanged(options[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: options[i] == value
                          ? colors.accent
                          : colors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: options[i] == value
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComparisonToggle extends StatelessWidget {
  const _ComparisonToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => onChanged(value == '>=' ? '<=' : '>='),
    style: TextButton.styleFrom(
      minimumSize: const Size(34, 34),
      padding: EdgeInsets.zero,
    ),
    child: Text(
      value == '>=' ? '≥' : '≤',
      style: TextStyle(color: context.colors.textPrimary, fontSize: 17),
    ),
  );
}
