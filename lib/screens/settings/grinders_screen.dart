import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/grinder.dart';
import '../../services/grinder_store.dart';
import '../../theme/app_theme.dart';
import 'settings_widgets.dart';

// Settings → My Setup → Grinders: all grinders in ONE card. Each grinder
// shows all its burr sets; the check mark marks the fitted one (tap to
// switch). "+" adds a grinder, tapping its name edits it.
class GrindersScreen extends StatelessWidget {
  const GrindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GrinderStore>();
    final grinders = store.grinders;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grinders'),
        actions: [
          IconButton(
            tooltip: 'Add grinder',
            icon: const Icon(Icons.add),
            onPressed: () => showGrinderDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              if (grinders.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.dividerInset),
                  child: Text(
                    'No grinders yet. Tap + to add yours.',
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                ),
              for (final g in grinders) _GrinderSection(grinder: g),
            ],
          ),
        ],
      ),
    );
  }
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
              14,
              AppSpacing.dividerInset,
              grinder.burrs.isEmpty ? 14 : 4,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.blender_outlined,
                  size: 20,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    grinder.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.edit_outlined, size: 18, color: colors.textTertiary),
              ],
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
        if (grinder.burrs.isNotEmpty) const SizedBox(height: 6),
      ],
    );
  }
}

/// Add ([grinder] null) or edit a grinder. Returns the saved grinder, null
/// on cancel or delete.
Future<Grinder?> showGrinderDialog(BuildContext context, {Grinder? grinder}) {
  return showDialog<Grinder>(
    context: context,
    builder: (_) => ChangeNotifierProvider<GrinderStore>.value(
      value: context.read<GrinderStore>(),
      child: _GrinderDialog(grinder: grinder),
    ),
  );
}

class _GrinderDialog extends StatefulWidget {
  const _GrinderDialog({this.grinder});

  final Grinder? grinder;

  @override
  State<_GrinderDialog> createState() => _GrinderDialogState();
}

class _GrinderDialogState extends State<_GrinderDialog> {
  late final TextEditingController _name;
  final List<TextEditingController> _burrs = [];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.grinder?.name)
      ..addListener(() => setState(() {}));
    for (final b in widget.grinder?.burrs ?? const <String>[]) {
      _addBurrField(b);
    }
    if (_burrs.isEmpty) _addBurrField();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _burrs) {
      c.dispose();
    }
    super.dispose();
  }

  void _addBurrField([String text = '']) {
    _burrs.add(TextEditingController(text: text)..addListener(_refresh));
  }

  void _refresh() => setState(() {});

  List<String> get _entered => [
    for (final c in _burrs)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  // Burr sets from the user's other grinders, not yet entered here.
  List<String> _suggestions(GrinderStore store) {
    final taken = {for (final b in _entered) b.toLowerCase()};
    return [
      for (final s in store.burrSuggestions)
        if (!taken.contains(s.toLowerCase())) s,
    ];
  }

  void _takeSuggestion(String burr) {
    final empty = _burrs.where((c) => c.text.trim().isEmpty);
    if (empty.isNotEmpty) {
      empty.first.text = burr;
    } else {
      setState(() => _addBurrField(burr));
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final store = context.read<GrinderStore>();
    final existing = widget.grinder;
    final saved = existing == null
        ? store.add(name, _entered)
        : existing.copyWith(name: name, burrs: _entered);
    if (existing != null) store.update(saved);
    Navigator.of(context).pop(saved);
  }

  Future<void> _delete() async {
    final grinder = widget.grinder!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Delete ${grinder.name}?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          'Shots brewed with it keep its name.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.colors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    context.read<GrinderStore>().remove(grinder.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<GrinderStore>();
    final suggestions = _suggestions(store);
    final editing = widget.grinder != null;
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text(
        editing ? 'Edit grinder' : 'Add grinder',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('grinder-name'),
              controller: _name,
              autofocus: !editing,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _burrs.length; i++)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('grinder-burrs-$i'),
                      controller: _burrs[i],
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Burrs'),
                    ),
                  ),
                  if (_burrs.length > 1)
                    IconButton(
                      tooltip: 'Remove burrs',
                      icon: Icon(Icons.close, color: colors.textTertiary),
                      onPressed: () => setState(() {
                        _burrs.removeAt(i).dispose();
                      }),
                    ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(_addBurrField),
                icon: Icon(Icons.add, color: colors.accent, size: 18),
                label: Text(
                  'Add burrs',
                  style: TextStyle(color: colors.accent),
                ),
              ),
            ),
            if (suggestions.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s),
                      onPressed: () => _takeSuggestion(s),
                    ),
                ],
              ),
            if (editing) ...[
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: colors.danger),
                  label: Text(
                    'Delete grinder',
                    style: TextStyle(color: colors.danger),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: _name.text.trim().isEmpty ? null : _save,
          child: Text(
            'Save',
            style: TextStyle(
              color: _name.text.trim().isEmpty
                  ? colors.textTertiary
                  : colors.accent,
            ),
          ),
        ),
      ],
    );
  }
}
