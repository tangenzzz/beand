import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/gear.dart';
import '../../services/gear_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/underline_select.dart';
import 'coffee_desk_data.dart';
import 'my_setup_dialogs.dart';

// Add/edit dialogs of My Coffee Desk for everything that is not a grinder
// or a water (those keep their own dialogs), and for brew chains. Same look
// as the My Setup dialogs: neutral fields, earlier entries as suggestions.

/// Add ([gear] null) or edit a piece of [type].
Future<void> showGearDialog(
  BuildContext context, {
  required GearType type,
  Gear? gear,
  VoidCallback? onPhoto,
}) => showDialog<void>(
  context: context,
  builder: (_) => ChangeNotifierProvider<GearStore>.value(
    value: context.read<GearStore>(),
    child: _GearDialog(type: type, gear: gear, onPhoto: onPhoto),
  ),
);

/// Add ([chain] null) or edit a brew chain. Returns the saved chain, null on
/// cancel or delete.
Future<BrewChain?> showChainDialog(BuildContext context, {BrewChain? chain}) =>
    showDialog<BrewChain>(
      context: context,
      builder: (_) => ChangeNotifierProvider<GearStore>.value(
        value: context.read<GearStore>(),
        child: _ChainDialog(chain: chain),
      ),
    );

class _GearDialog extends StatefulWidget {
  const _GearDialog({required this.type, this.gear, this.onPhoto});

  final GearType type;
  final Gear? gear;
  final VoidCallback? onPhoto;

  @override
  State<_GearDialog> createState() => _GearDialogState();
}

class _GearDialogState extends State<_GearDialog> {
  late final _brand = TextEditingController(text: widget.gear?.brand);
  late final _model = TextEditingController(text: widget.gear?.model)
    ..addListener(() => setState(() {}));
  late final _stock = TextEditingController(
    text: widget.gear?.stock?.toString(),
  );
  late final Map<String, TextEditingController> _specs = {
    for (final f in specFields[widget.type] ?? const <SpecField>[])
      f.key: TextEditingController(
        text: switch (widget.gear?.specs[f.key]) {
          null => '',
          num v => v % 1 == 0 ? v.toStringAsFixed(0) : '$v',
          final v => '$v',
        },
      ),
  };
  late String? _shape = widget.gear?.specs['shape'] as String?;

  @override
  void dispose() {
    for (final c in [_brand, _model, _stock, ..._specs.values]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _parse(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  void _save() {
    // Brand and model are optional (user 2026-10-19): a piece without them
    // shows as its kind, e.g. "Machine".
    final model = _model.text.trim();
    final existing = widget.gear;
    final current = existing == null
        ? null
        : context.read<GearStore>().byId(existing.id);
    final brand = _brand.text.trim();
    final fields = specFields[widget.type] ?? const <SpecField>[];
    // Keys this form doesn't know (e.g. from a newer app version) stay.
    final specs = <String, Object?>{
      for (final e in (existing?.specs ?? const {}).entries)
        if (!fields.any((f) => f.key == e.key) && e.key != 'shape')
          e.key: e.value,
      for (final f in fields)
        if (_specs[f.key]!.text.trim() case final text when text.isNotEmpty)
          f.key: f.numeric ? (_parse(text) ?? text) : text,
      'shape': ?_shape,
    };
    final stock = int.tryParse(_stock.text.trim());
    context.read<GearStore>().save(
      Gear(
        id: existing?.id ?? '',
        type: widget.type,
        brand: brand.isEmpty ? null : brand,
        model: model,
        // What it serves follows the kind (the form no longer asks).
        brewModes: existing?.brewModes ?? defaultBrewModes(widget.type),
        // The photo may have changed while the dialog was open.
        photoPath: current?.photoPath,
        photoOriginalPath: current?.photoOriginalPath,
        photoBlob: current?.photoBlob,
        photoOriginalBlob: current?.photoOriginalBlob,
        specs: specs,
        stock: hasStock(widget.type) ? stock : null,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final gear = widget.gear!;
    if (!await confirmSetupDelete(context, gear.displayName, null) ||
        !mounted) {
      return;
    }
    context.read<GearStore>().remove(gear.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GearStore>();
    final type = widget.type;
    final editing = widget.gear != null;
    final single = type.single.toLowerCase();
    final shapes = gearShapes[type];
    return SetupDialog(
      title: editing ? 'Edit $single' : 'Add $single',
      onPhoto: widget.onPhoto,
      canSave: true,
      onSave: _save,
      onDelete: editing ? _delete : null,
      deleteLabel: 'Delete $single',
      children: [
        SetupField(
          key: const ValueKey('gear-brand'),
          controller: _brand,
          label: 'Brand',
          suggestions: store.brandSuggestions(type),
        ),
        SetupField(
          key: const ValueKey('gear-model'),
          controller: _model,
          label: 'Model',
          autofocus: !editing,
        ),
        for (final f in specFields[type] ?? const <SpecField>[])
          SetupField(
            key: ValueKey('gear-${f.key}'),
            controller: _specs[f.key]!,
            label: f.label,
            suffix: f.unit,
            numeric: f.numeric,
            suggestions: f.numeric
                ? const []
                : store.specSuggestions(type, f.key),
          ),
        if (hasStock(type))
          SetupField(
            key: const ValueKey('gear-stock'),
            controller: _stock,
            label: 'Stock',
            numeric: true,
          ),
        if (shapes != null) ...[
          const SizedBox(height: 14),
          UnderlineSelect<String?>(
            options: [for (final (v, l) in shapes) UnderlineOption(v, l)],
            value: _shape,
            onChanged: (v) => setState(() => _shape = v),
          ),
        ],
      ],
    );
  }
}

class _ChainDialog extends StatefulWidget {
  const _ChainDialog({this.chain});

  final BrewChain? chain;

  @override
  State<_ChainDialog> createState() => _ChainDialogState();
}

class _ChainDialogState extends State<_ChainDialog> {
  late final _name = TextEditingController(text: widget.chain?.name)
    ..addListener(() => setState(() {}));
  late final _gearIds = <String>{...?widget.chain?.gearIds};

  @override
  void initState() {
    super.initState();
    // A chain from before 2026-10-19 may hold two pieces of one kind: keep
    // the first of each, as the choice shows it.
    final store = context.read<GearStore>();
    for (final type in GearType.values) {
      final ids = [
        for (final g in store.ofType(type))
          if (_gearIds.contains(g.id)) g.id,
      ];
      _gearIds.removeAll(ids.skip(1));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final store = context.read<GearStore>();
    // Keep the desk's order: by type, then as listed.
    final ids = [
      for (final g in store.gear)
        if (_gearIds.contains(g.id)) g.id,
    ];
    final saved = store.saveChain(
      BrewChain(id: widget.chain?.id ?? '', name: name, gearIds: ids),
    );
    Navigator.of(context).pop(saved);
  }

  Future<void> _delete() async {
    final chain = widget.chain!;
    if (!await confirmSetupDelete(
          context,
          chain.name,
          'The gear stays on the desk.',
        ) ||
        !mounted) {
      return;
    }
    context.read<GearStore>().removeChain(chain.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<GearStore>();
    final editing = widget.chain != null;
    return SetupDialog(
      title: editing ? 'Edit brew chain' : 'Add brew chain',
      canSave: _name.text.trim().isNotEmpty,
      onSave: _save,
      onDelete: editing ? _delete : null,
      deleteLabel: 'Delete brew chain',
      children: [
        SetupField(
          key: const ValueKey('chain-name'),
          controller: _name,
          label: 'Name',
          autofocus: !editing,
        ),
        if (store.gear.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              'No gear on the desk yet.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
        for (final type in GearType.values)
          if (store.ofType(type).toList() case final items
              when items.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 2),
              child: Text(
                type.label.toUpperCase(),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            // One piece per category: picking another one replaces it,
            // tapping the chosen one again leaves the category out.
            UnderlineSelect<String>(
              key: ValueKey('chain-${type.name}'),
              options: [
                for (final g in items) UnderlineOption(g.id, g.displayName),
              ],
              value: items
                  .where((g) => _gearIds.contains(g.id))
                  .firstOrNull
                  ?.id,
              allowDeselect: true,
              onChanged: (id) => setState(() {
                _gearIds.removeAll([for (final g in items) g.id]);
                if (id != null) _gearIds.add(id);
              }),
            ),
          ],
      ],
    );
  }
}
