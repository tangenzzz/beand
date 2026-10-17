import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/grinder.dart';
import '../../models/water.dart';
import '../../services/grinder_store.dart';
import '../../services/water_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dot_choice_group.dart';

// Add/edit dialogs of Settings → My Setup. Everything is free text; the
// chips offer what the user entered elsewhere before (no bundled lists).

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

Future<void> showWaterDialog(BuildContext context, {Water? water}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ChangeNotifierProvider<WaterStore>.value(
      value: context.read<WaterStore>(),
      child: _WaterDialog(water: water),
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
  late final TextEditingController _brand;
  late final TextEditingController _name;
  final List<TextEditingController> _burrs = [];

  @override
  void initState() {
    super.initState();
    _brand = TextEditingController(text: widget.grinder?.brand)
      ..addListener(_refresh);
    _name = TextEditingController(text: widget.grinder?.name)
      ..addListener(_refresh);
    for (final b in widget.grinder?.burrs ?? const <String>[]) {
      _addBurrField(b);
    }
    if (_burrs.isEmpty) _addBurrField();
  }

  @override
  void dispose() {
    _brand.dispose();
    _name.dispose();
    for (final c in _burrs) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _addBurrField([String text = '']) {
    _burrs.add(TextEditingController(text: text)..addListener(_refresh));
  }

  List<String> get _entered => [
    for (final c in _burrs)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  void _takeBurrSuggestion(String burr) {
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
    final Grinder saved;
    if (existing == null) {
      saved = store.add(name, _entered, brand: _brand.text);
    } else {
      saved = Grinder(
        id: existing.id,
        name: name,
        brand: _brand.text,
        burrs: _entered,
        activeBurr: existing.activeBurr,
      );
      store.update(saved);
    }
    Navigator.of(context).pop(saved);
  }

  Future<void> _delete() async {
    final grinder = widget.grinder!;
    if (!await _confirmDelete(
          context,
          grinder.name,
          'Shots brewed with it keep its name.',
        ) ||
        !mounted) {
      return;
    }
    context.read<GrinderStore>().remove(grinder.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GrinderStore>();
    final burrTaken = {for (final b in _entered) b.toLowerCase()};
    final editing = widget.grinder != null;
    return _SetupDialog(
      title: editing ? 'Edit grinder' : 'Add grinder',
      canSave: _name.text.trim().isNotEmpty,
      onSave: _save,
      onDelete: editing ? _delete : null,
      deleteLabel: 'Delete grinder',
      children: [
        _Field(
          key: const ValueKey('grinder-brand'),
          controller: _brand,
          label: 'Brand',
        ),
        if (_brand.text.trim().isEmpty)
          _Suggestions(
            values: store.brandSuggestions,
            onPick: (v) => _brand.text = v,
          ),
        _Field(
          key: const ValueKey('grinder-name'),
          controller: _name,
          label: 'Name',
          autofocus: !editing,
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < _burrs.length; i++)
          Row(
            children: [
              Expanded(
                child: _Field(
                  key: ValueKey('grinder-burrs-$i'),
                  controller: _burrs[i],
                  label: 'Burrs',
                ),
              ),
              if (_burrs.length > 1)
                IconButton(
                  tooltip: 'Remove burrs',
                  icon: Icon(Icons.close, color: context.colors.textTertiary),
                  onPressed: () => setState(() => _burrs.removeAt(i).dispose()),
                ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(_addBurrField),
            icon: Icon(Icons.add, color: context.colors.accent, size: 18),
            label: Text(
              'Add burrs',
              style: TextStyle(color: context.colors.accent),
            ),
          ),
        ),
        _Suggestions(
          values: [
            for (final s in store.burrSuggestions)
              if (!burrTaken.contains(s.toLowerCase())) s,
          ],
          onPick: _takeBurrSuggestion,
        ),
      ],
    );
  }
}

class _WaterDialog extends StatefulWidget {
  const _WaterDialog({this.water});

  final Water? water;

  @override
  State<_WaterDialog> createState() => _WaterDialogState();
}

class _WaterDialogState extends State<_WaterDialog> {
  late final _recipe = TextEditingController(text: widget.water?.recipe);
  late final _gh = TextEditingController(text: _num(widget.water?.gh));
  late final _ghSource = TextEditingController(text: widget.water?.ghSource);
  late final _kh = TextEditingController(text: _num(widget.water?.kh));
  late final _khSource = TextEditingController(text: widget.water?.khSource);
  late final _ppm = TextEditingController(text: _num(widget.water?.ppm));
  late WaterUse? _use = widget.water?.use;

  static String _num(double? v) =>
      v == null ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toString());

  static double? _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  static String? _text(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_recipe, _ghSource, _khSource]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_recipe, _gh, _ghSource, _kh, _khSource, _ppm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final recipe = _recipe.text.trim();
    if (recipe.isEmpty) return;
    context.read<WaterStore>().save(
      Water(
        id: widget.water?.id ?? '',
        recipe: recipe,
        gh: _parse(_gh),
        ghSource: _text(_ghSource),
        kh: _parse(_kh),
        khSource: _text(_khSource),
        ppm: _parse(_ppm),
        use: _use,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final water = widget.water!;
    if (!await _confirmDelete(context, water.recipe, null) || !mounted) return;
    context.read<WaterStore>().remove(water.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WaterStore>();
    final editing = widget.water != null;
    return _SetupDialog(
      title: editing ? 'Edit water' : 'Add water',
      canSave: _recipe.text.trim().isNotEmpty,
      onSave: _save,
      onDelete: editing ? _delete : null,
      deleteLabel: 'Delete water',
      children: [
        _Field(
          key: const ValueKey('water-recipe'),
          controller: _recipe,
          label: 'Recipe',
          autofocus: !editing,
        ),
        Row(
          children: [
            SizedBox(
              width: 86,
              child: _Field(
                key: const ValueKey('water-gh'),
                controller: _gh,
                label: 'GH',
                suffix: 'ppm',
                numeric: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Field(
                key: const ValueKey('water-gh-source'),
                controller: _ghSource,
                label: 'GH from',
              ),
            ),
          ],
        ),
        if (_ghSource.text.trim().isEmpty)
          _Suggestions(
            values: store.ghSources,
            onPick: (v) => _ghSource.text = v,
          ),
        Row(
          children: [
            SizedBox(
              width: 86,
              child: _Field(
                key: const ValueKey('water-kh'),
                controller: _kh,
                label: 'KH',
                suffix: 'ppm',
                numeric: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Field(
                key: const ValueKey('water-kh-source'),
                controller: _khSource,
                label: 'KH from',
              ),
            ),
          ],
        ),
        if (_khSource.text.trim().isEmpty)
          _Suggestions(
            values: store.khSources,
            onPick: (v) => _khSource.text = v,
          ),
        _Field(
          key: const ValueKey('water-ppm'),
          controller: _ppm,
          label: 'Total',
          suffix: 'ppm',
          numeric: true,
        ),
        const SizedBox(height: 14),
        DotChoiceGroup<WaterUse>(
          options: [for (final u in WaterUse.values) DotChoice(u, u.label)],
          value: _use,
          allowDeselect: true,
          onChanged: (v) => setState(() => _use = v),
        ),
      ],
    );
  }
}

// Shared frame: scrollable fields, delete at the bottom, Cancel/Save.
class _SetupDialog extends StatelessWidget {
  const _SetupDialog({
    required this.title,
    required this.children,
    required this.canSave,
    required this.onSave,
    required this.onDelete,
    required this.deleteLabel,
  });

  final String title;
  final List<Widget> children;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text(title, style: TextStyle(color: colors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...children,
            if (onDelete != null) ...[
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: colors.danger),
                  label: Text(
                    deleteLabel,
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
          onPressed: canSave ? onSave : null,
          child: Text(
            'Save',
            style: TextStyle(
              color: canSave ? colors.accent : colors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.numeric = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool numeric;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textCapitalization: numeric
          ? TextCapitalization.none
          : TextCapitalization.words,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
          : null,
      style: TextStyle(color: context.colors.textPrimary),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.values, required this.onPick});

  final List<String> values;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final v in values)
            ActionChip(label: Text(v), onPressed: () => onPick(v)),
        ],
      ),
    );
  }
}

Future<bool> _confirmDelete(
  BuildContext context,
  String name,
  String? note,
) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.colors.card,
      title: Text(
        'Delete $name?',
        style: TextStyle(color: context.colors.textPrimary),
      ),
      content: note == null
          ? null
          : Text(note, style: TextStyle(color: context.colors.textSecondary)),
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
          child: Text('Delete', style: TextStyle(color: context.colors.danger)),
        ),
      ],
    ),
  );
  return answer == true;
}
