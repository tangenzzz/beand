import 'package:flutter/material.dart';

import '../../../models/profile_draft.dart';
import '../../../theme/app_theme.dart';
import 'editor_widgets.dart';

// Bind a value to a variable, change the binding or remove it.
//
// Layout follows our dropdown rule: list first, the create row at the very
// bottom. Only variables of the matching quantity are offered — a pressure
// value can't be attached to a time variable.
//
// Returns null if cancelled. The new variable is added directly to
// [draft]; the caller works on a copy anyway.
class VariableChoice {
  const VariableChoice(this.value);

  final DraftValue value;
}

Future<VariableChoice?> showVariableSheet(
  BuildContext context, {
  required ProfileDraft draft,
  required DraftValue current,
  required String type,
}) => showModalBottomSheet<VariableChoice>(
  context: context,
  isScrollControlled: true,
  backgroundColor: context.colors.card,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.tile)),
  ),
  builder: (_) => _VariableSheet(draft: draft, current: current, type: type),
);

class _VariableSheet extends StatefulWidget {
  const _VariableSheet({
    required this.draft,
    required this.current,
    required this.type,
  });

  final ProfileDraft draft;
  final DraftValue current;
  final String type;

  @override
  State<_VariableSheet> createState() => _VariableSheetState();
}

class _VariableSheetState extends State<_VariableSheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<DraftVariable> get _matching =>
      widget.draft.variables.where((v) => v.type == widget.type).toList();

  void _create() {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    // The current numeric value becomes the start value — so nothing jumps
    // when a point is attached to a variable later.
    final value = widget.current.resolve(widget.draft.variables) ?? 0;
    final variable = DraftVariable(
      name: name,
      key: widget.draft.freeVariableKey(widget.type),
      type: widget.type,
      value: value,
    );
    widget.draft.variables.add(variable);
    Navigator.of(context)
        .pop(VariableChoice(DraftValue.variable(variable.key)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bound = widget.current.isVariable;
    final matching = _matching;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${labelForType(widget.type)} variable',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const HelpButton(
                      title: 'Variables',
                      body: EditorHelp.variables,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'A named value you can reuse in several places and adjust '
                  "from the machine's dial.",
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),

              if (matching.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'No ${labelForType(widget.type).toLowerCase()} variables yet.',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12.5,
                    ),
                  ),
                )
              else
                for (final variable in matching)
                  _VariableRow(
                    variable: variable,
                    selected: widget.current.variableKey == variable.key,
                    onTap: () => Navigator.of(context)
                        .pop(VariableChoice(DraftValue.variable(variable.key))),
                  ),

              // Create new — at the bottom, like all lists in the app.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: EditorField(
                        controller: _name,
                        hint: 'New variable name',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Create variable',
                      icon: Icon(
                        Icons.add,
                        color: _name.text.trim().isEmpty
                            ? colors.textTertiary
                            : colors.accent,
                      ),
                      onPressed: _name.text.trim().isEmpty ? null : _create,
                    ),
                  ],
                ),
              ),

              if (bound)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: TextButton(
                    onPressed: () {
                      // On unbinding the last valid numeric value stays so
                      // the curve stays in place.
                      final value =
                          widget.current.resolve(widget.draft.variables) ?? 0;
                      Navigator.of(context)
                          .pop(VariableChoice(DraftValue.number(value)));
                    },
                    child: Text(
                      'Detach variable',
                      style: TextStyle(color: colors.danger),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariableRow extends StatelessWidget {
  const _VariableRow({
    required this.variable,
    required this.selected,
    required this.onTap,
  });

  final DraftVariable variable;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                variable.name,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
              ),
            ),
            Text(
              '${trimNumber(variable.value)} ${unitForType(variable.type)}',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.check, size: 17, color: colors.accent),
              ),
          ],
        ),
      ),
    );
  }
}
