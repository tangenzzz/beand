import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/gear.dart';
import '../../models/grind_scale.dart';
import '../../models/grinder.dart';
import '../../models/water.dart';
import '../../services/gear_store.dart';
import '../../services/grinder_store.dart';
import '../../services/water_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/underline_select.dart';
import '../live/tile_title.dart';
import 'my_coffee_desk_screen.dart' show GearIcon;
import 'settings_widgets.dart';

// Add/edit dialogs of Settings → My Setup. Everything is free text; the
// chips offer what the user entered elsewhere before (no bundled lists).

/// Add ([grinder] null) or edit a grinder. Returns the saved grinder, null
/// on cancel or delete.
/// [onPhoto]: the desk's photo choice for an existing piece — shown as
/// the thumbnail in the sheet's head (the shelf has no Edit/Photo buttons).
Future<Grinder?> showGrinderDialog(
  BuildContext context, {
  Grinder? grinder,
  VoidCallback? onPhoto,
}) {
  return showSetupSheet<Grinder>(
    context,
    (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider<GrinderStore>.value(
          value: context.read<GrinderStore>(),
        ),
        ChangeNotifierProvider<GearStore>.value(
          value: context.read<GearStore>(),
        ),
      ],
      child: _GrinderDialog(grinder: grinder, onPhoto: onPhoto),
    ),
  );
}

Future<void> showWaterDialog(
  BuildContext context, {
  Water? water,
  VoidCallback? onPhoto,
}) {
  return showSetupSheet<void>(
    context,
    (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider<WaterStore>.value(
          value: context.read<WaterStore>(),
        ),
        ChangeNotifierProvider<GearStore>.value(
          value: context.read<GearStore>(),
        ),
      ],
      child: _WaterDialog(water: water, onPhoto: onPhoto),
    ),
  );
}

class _GrinderDialog extends StatefulWidget {
  const _GrinderDialog({this.grinder, this.onPhoto});

  final Grinder? grinder;
  final VoidCallback? onPhoto;

  @override
  State<_GrinderDialog> createState() => _GrinderDialogState();
}

class _GrinderDialogState extends State<_GrinderDialog> {
  late final TextEditingController _brand;
  late final TextEditingController _name;
  final List<TextEditingController> _burrs = [];

  // Form, scale and zero point (see Grinder).
  late bool _hand = widget.grinder?.hand ?? false;
  late GrindUnit? _unit = widget.grinder?.scale?.unit;
  late double _step = widget.grinder?.scale?.step ?? 0.5;
  late final _min = TextEditingController(
    text: _num(widget.grinder?.scale?.min),
  );
  late final _max = TextEditingController(
    text: _num(widget.grinder?.scale?.max),
  );
  late final _perRotation = TextEditingController(
    text: widget.grinder?.scale?.clicksPerRotation.toString() ?? '30',
  );
  late final _zero = TextEditingController(
    text: _num(widget.grinder?.zeroPoint?.value),
  );

  // Index marks (optional): colour, name, offset from the first one.
  late final List<_MarkerDraft> _markers = [
    for (final m in widget.grinder?.scale?.markers ?? const <GrindMarker>[])
      _MarkerDraft(markerDisplayColor(m.color), m.name, m.offset),
  ];

  void _addMarker() => setState(() {
    final used = {for (final m in _markers) m.color};
    _markers.add(
      _MarkerDraft(
        _markerColors.firstWhere(
          (c) => !used.contains(c),
          orElse: () => _markerColors.first,
        ),
        '',
        0,
      ),
    );
  });

  void _cycleColor(_MarkerDraft m) => setState(() {
    final i = _markerColors.indexOf(m.color);
    m.color = _markerColors[(i + 1) % _markerColors.length];
  });

  static String _num(double? v) =>
      v == null ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toString());

  static double? _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  // A unit picked without a range yet gets a usual one.
  void _setUnit(GrindUnit? unit) => setState(() {
    _unit = unit;
    if (unit == null) return;
    if (!unit.steps.contains(_step)) _step = unit.steps.first;
    if (_min.text.trim().isEmpty) _min.text = '0';
    if (_max.text.trim().isEmpty) {
      _max.text = switch (unit) {
        GrindUnit.dial => '50',
        GrindUnit.clicks => '40',
        GrindUnit.rotations => '120',
        GrindUnit.microns => '1500',
      };
    }
  });

  GrindScale? get _scale {
    final unit = _unit;
    final min = _parse(_min), max = _parse(_max);
    if (unit == null || min == null || max == null || max <= min) return null;
    return GrindScale(
      unit: unit,
      step: unit.steps.contains(_step) ? _step : unit.steps.first,
      min: min,
      max: max,
      clicksPerRotation: int.tryParse(_perRotation.text.trim()) ?? 30,
      markers: [
        for (final (i, m) in _markers.indexed)
          if (m.name.text.trim().isNotEmpty)
            GrindMarker(
              name: m.name.text.trim(),
              color: m.color,
              // The first one is the reference.
              offset: i == 0 ? 0 : (_parse(m.offset) ?? 0),
            ),
      ],
    );
  }

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
    for (final c in [_min, _max, _perRotation, _zero]) {
      c.dispose();
    }
    for (final m in _markers) {
      m.dispose();
    }
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

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final store = context.read<GrinderStore>();
    final existing = widget.grinder;
    final id = existing?.id ?? store.add(name, _entered, brand: _brand.text).id;
    store.update(
      Grinder(
        id: id,
        name: name,
        brand: _brand.text,
        burrs: _entered,
        activeBurr: existing?.activeBurr,
        hand: _hand,
        scale: _scale,
        zeros: existing?.zeros ?? const {},
      ),
    );
    // A zero point entered or changed: a new entry with today's date, for
    // the fitted burrs (or the grinder, while none are named).
    final zero = _parse(_zero);
    if (zero != null) store.setZero(id, zero);
    Navigator.of(context).pop(store.byId(id));
  }

  // Small heading of a part of the dialog, the explanation behind ⓘ.
  Widget _label(String text, {String? info}) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 4),
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 11,
            letterSpacing: 0.8,
          ),
        ),
        if (info != null) ...[const SizedBox(width: 4), SettingsInfo(info)],
      ],
    ),
  );

  // Shown next to the folded "Advanced": what is set in there.
  String? _advancedSummary() {
    final parts = [
      if (_unit case final unit?) unit.label,
      if (_markers.length > 1) '${_markers.length} markers',
      if (_zero.text.trim() case final z when z.isNotEmpty && z != '0')
        'zero $z',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _delete() async {
    final grinder = widget.grinder!;
    if (!await confirmSetupDelete(
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
    final id = widget.grinder?.id;
    return SetupDialog(
      title: 'Grinder',
      heading: _name.text,
      subheading: _brand.text,
      photo: id == null || widget.onPhoto == null
          ? null
          : GearThumb(
              gearId: id,
              icon: GearType.grinder.iconAsset({if (_hand) 'shape': 'hand'}),
            ),
      onPhoto: widget.onPhoto,
      canSave: _name.text.trim().isNotEmpty,
      onSave: _save,
      onDelete: editing ? _delete : null,
      deleteLabel: 'Delete grinder',
      advancedSummary: _advancedSummary(),
      // The basics first, then what folds away under "Advanced".
      // ignore: sort_child_properties_last
      children: [
        SetupField(
          key: const ValueKey('grinder-brand'),
          controller: _brand,
          label: 'Brand',
          suggestions: store.brandSuggestions,
        ),
        SetupField(
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
                child: SetupField(
                  key: ValueKey('grinder-burrs-$i'),
                  controller: _burrs[i],
                  label: 'Burrs',
                  suggestions: [
                    for (final s in store.burrSuggestions)
                      if (!burrTaken.contains(s.toLowerCase())) s,
                  ],
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
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => setState(_addBurrField),
            icon: Icon(
              Icons.add,
              color: context.colors.textSecondary,
              size: 18,
            ),
            label: Text(
              'Add burrs',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
        ),
        SetupRow(
          label: 'Type',
          child: UnderlineSelect<bool>(
            key: const ValueKey('grinder-form'),
            options: const [
              UnderlineOption(false, 'Electric'),
              UnderlineOption(true, 'Hand'),
            ],
            value: _hand,
            onChanged: (v) => setState(() => _hand = v!),
          ),
        ),
      ],
      advanced: [
        _label(
          'Scale',
          info:
              'How the dial is read. The grind ruler in Pre-Shot, Pre-Brew '
              'and the shot detail follows it.',
        ),
        UnderlineSelect<GrindUnit>(
          key: const ValueKey('grinder-unit'),
          options: [
            for (final u in GrindUnit.values) UnderlineOption(u, u.label),
          ],
          value: _unit,
          allowDeselect: true,
          onChanged: _setUnit,
        ),
        if (_unit case final unit?) ...[
          if (unit.steps.length > 1) ...[
            const SizedBox(height: 8),
            UnderlineSelect<double>(
              key: const ValueKey('grinder-step'),
              options: [
                for (final st in unit.steps)
                  UnderlineOption(st, _stepLabel(st, unit)),
              ],
              value: _step,
              onChanged: (v) => setState(() => _step = v!),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: SetupField(
                  key: const ValueKey('grinder-min'),
                  controller: _min,
                  label: 'From',
                  numeric: true,
                  signed: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SetupField(
                  key: const ValueKey('grinder-max'),
                  controller: _max,
                  label: 'To',
                  numeric: true,
                  signed: true,
                ),
              ),
            ],
          ),
          if (unit == GrindUnit.rotations)
            SetupField(
              key: const ValueKey('grinder-per-rotation'),
              controller: _perRotation,
              label: 'Clicks per rotation',
              numeric: true,
            ),
          _label(
            'Markers (optional)',
            info:
                'E.g. older Kafatek grinders whose scale is not continuous '
                'and has several marks. Offset: where 0 of a mark sits on '
                'the first one — red 2.2 at green 9.0 makes red +6.8. The '
                'grind ruler then runs across all marks.',
          ),
          for (final (i, m) in _markers.indexed)
            Row(
              key: ValueKey('marker-row-$i'),
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Marker colour',
                  onPressed: () => _cycleColor(m),
                  icon: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Color(m.color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.colors.textTertiary,
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SetupField(
                    key: ValueKey('marker-name-$i'),
                    controller: m.name,
                    label: 'Name',
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 92,
                  child: i == 0
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            'reference',
                            style: TextStyle(
                              color: context.colors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : SetupField(
                          key: ValueKey('marker-offset-$i'),
                          controller: m.offset,
                          label: 'Offset',
                          numeric: true,
                          signed: true,
                        ),
                ),
                IconButton(
                  tooltip: 'Remove marker',
                  icon: Icon(Icons.close, color: context.colors.textTertiary),
                  onPressed: () =>
                      setState(() => _markers.removeAt(i).dispose()),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: _addMarker,
              icon: Icon(
                Icons.add,
                color: context.colors.textSecondary,
                size: 18,
              ),
              label: Text(
                'Add marker',
                style: TextStyle(color: context.colors.textSecondary),
              ),
            ),
          ),
        ],
        _label(
          'Zero point (optional)',
          info:
              'The dial reading where the burrs just touch. If you re-index '
              'the dial after a burr change, leave it at 0. Negative values '
              'such as -0.3 are fine; shots keep the zero point of their day.',
        ),
        SetupField(
          key: const ValueKey('grinder-zero'),
          controller: _zero,
          label: _entered.isEmpty
              ? 'Zero point'
              : 'Zero point · ${widget.grinder?.activeBurrs ?? _entered.first}',
          numeric: true,
          signed: true,
          suffix: _unit?.suffix,
        ),
        if (widget.grinder?.zeroPoint case final z?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Set ${_date(z.at)}',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

// Colours of index marks to pick from (tap cycles).
const _markerColors = markerPalette;

class _MarkerDraft {
  _MarkerDraft(this.color, String name, double offset)
    : name = TextEditingController(text: name),
      offset = TextEditingController(
        text: offset == 0 ? '' : offset.toString(),
      );

  int color;
  final TextEditingController name;
  final TextEditingController offset;

  void dispose() {
    name.dispose();
    offset.dispose();
  }
}

String _stepLabel(double step, GrindUnit unit) {
  final text = step % 1 == 0 ? step.toStringAsFixed(0) : step.toString();
  return unit.suffix.isEmpty ? 'Steps of $text' : '$text ${unit.suffix}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

class _WaterDialog extends StatefulWidget {
  const _WaterDialog({this.water, this.onPhoto});

  final Water? water;
  final VoidCallback? onPhoto;

  @override
  State<_WaterDialog> createState() => _WaterDialogState();
}

class _WaterDialogState extends State<_WaterDialog> {
  late final _recipe = TextEditingController(text: widget.water?.recipe);
  late final _gh = TextEditingController(text: _num(widget.water?.gh));
  late final _kh = TextEditingController(text: _num(widget.water?.kh));
  late final _ghMinerals = {...?widget.water?.ghMinerals};
  late final _khMinerals = {...?widget.water?.khMinerals};
  late final _ppm = TextEditingController(text: _num(widget.water?.ppm));
  // No longer asked (user 2026-10-19); an earlier choice stays.
  late final WaterUse? _use = widget.water?.use;
  late MineralUnit _unit = widget.water?.unit ?? MineralUnit.gramsPerLitre;
  // Amount field per mineral, created on first tick; text in [_unit].
  final _amounts = <Mineral, TextEditingController>{};

  static String _num(double? v) =>
      v == null ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toString());

  static double? _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  @override
  void initState() {
    super.initState();
    _recipe.addListener(() => setState(() {}));
    widget.water?.amounts.forEach((m, grams) {
      _amountField(m).text = _format(m, grams, _unit);
    });
  }

  @override
  void dispose() {
    for (final c in [_recipe, _gh, _kh, _ppm, ..._amounts.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _amountField(Mineral m) =>
      _amounts.putIfAbsent(m, TextEditingController.new);

  // Grams per litre with up to three decimals, ppm with one; no trailing
  // zeros.
  static String _format(Mineral m, double grams, MineralUnit unit) {
    final v = unit == MineralUnit.ppm ? m.ppmFromGramsPerLitre(grams) : grams;
    final digits = unit == MineralUnit.ppm ? 1 : 3;
    return v.toStringAsFixed(digits).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  double? _gramsOf(Mineral m) {
    final c = _amounts[m];
    if (c == null) return null;
    final v = _parse(c);
    if (v == null) return null;
    return _unit == MineralUnit.ppm ? m.gramsPerLitreFromPpm(v) : v;
  }

  // Switching the unit converts what is already entered.
  void _setUnit(MineralUnit? unit) {
    if (unit == null || unit == _unit) return;
    final grams = {for (final m in _amounts.keys) m: _gramsOf(m)};
    setState(() {
      _unit = unit;
      grams.forEach((m, g) {
        if (g != null) _amounts[m]!.text = _format(m, g, unit);
      });
    });
  }

  void _toggle(Set<Mineral> set, Mineral m) =>
      setState(() => set.remove(m) || set.add(m));

  void _save() {
    final recipe = _recipe.text.trim();
    if (recipe.isEmpty) return;
    context.read<WaterStore>().save(
      Water(
        id: widget.water?.id ?? '',
        recipe: recipe,
        gh: _parse(_gh),
        ghMinerals: _ghMinerals,
        kh: _parse(_kh),
        khMinerals: _khMinerals,
        amounts: {
          for (final m in {..._ghMinerals, ..._khMinerals})
            if (_gramsOf(m) != null) m: _gramsOf(m)!,
        },
        unit: _unit,
        ppm: _parse(_ppm),
        use: _use,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final water = widget.water!;
    if (!await confirmSetupDelete(context, water.recipe, null) || !mounted) {
      return;
    }
    context.read<WaterStore>().remove(water.id);
    Navigator.of(context).pop();
  }

  Widget _amountRow(Mineral m) => Padding(
    padding: const EdgeInsets.only(left: 12, bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            m.label,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          ),
        ),
        SizedBox(
          width: 110,
          child: SetupField(
            key: ValueKey('water-amount-${m.name}'),
            controller: _amountField(m),
            label: 'Amount',
            suffix: _unit.label,
            numeric: true,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final editing = widget.water != null;
    final id = widget.water?.id;
    return SetupDialog(
      title: 'Water',
      heading: _recipe.text,
      photo: id == null || widget.onPhoto == null
          ? null
          : GearThumb(gearId: id, icon: GearType.water.iconAsset(const {})),
      onPhoto: widget.onPhoto,
      canSave: _recipe.text.trim().isNotEmpty,
      onSave: _save,
      onDelete: editing ? _delete : null,
      deleteLabel: 'Delete water',
      children: [
        SetupField(
          key: const ValueKey('water-recipe'),
          controller: _recipe,
          label: 'Recipe',
          autofocus: !editing,
        ),
        // Unit of the mineral amounts; switching converts what is entered.
        SetupRow(
          label: 'Amounts in',
          child: UnderlineSelect<MineralUnit>(
            options: [
              for (final u in MineralUnit.values) UnderlineOption(u, u.label),
            ],
            value: _unit,
            onChanged: _setUnit,
          ),
        ),
        SetupField(
          key: const ValueKey('water-gh'),
          controller: _gh,
          label: 'GH',
          suffix: 'ppm',
          numeric: true,
        ),
        _MineralChoice(
          minerals: Mineral.forGh,
          selected: _ghMinerals,
          onToggle: (m) => _toggle(_ghMinerals, m),
        ),
        for (final m in Mineral.forGh)
          if (_ghMinerals.contains(m)) _amountRow(m),
        SetupField(
          key: const ValueKey('water-kh'),
          controller: _kh,
          label: 'KH',
          suffix: 'ppm',
          numeric: true,
        ),
        _MineralChoice(
          minerals: Mineral.forKh,
          selected: _khMinerals,
          onToggle: (m) => _toggle(_khMinerals, m),
        ),
        for (final m in Mineral.forKh)
          if (_khMinerals.contains(m)) _amountRow(m),
        SetupField(
          key: const ValueKey('water-ppm'),
          controller: _ppm,
          label: 'Total',
          suffix: 'ppm',
          numeric: true,
        ),
      ],
    );
  }
}

// Which salts the hardness comes from — several may be ticked (many recipes
// mix two). Fixed list, see [Mineral].
class _MineralChoice extends StatelessWidget {
  const _MineralChoice({
    required this.minerals,
    required this.selected,
    required this.onToggle,
  });

  final List<Mineral> minerals;
  final Set<Mineral> selected;
  final ValueChanged<Mineral> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: [
          for (final m in minerals)
            UnderlineItem(
              label: m.label,
              selected: selected.contains(m),
              onTap: () => onToggle(m),
            ),
        ],
      ),
    );
  }
}

/// Opens a My Coffee Desk editor as a bottom sheet (see [SetupDialog]).
Future<T?> showSetupSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: builder,
    );

// Shared frame of every My Coffee Desk editor, as a bottom sheet: handle,
// head with the piece's photo and its name, the fields as rows, optional
// "Advanced" to fold out, Save fixed at the bottom and delete below it.
// Swiping down or tapping outside cancels.
class SetupDialog extends StatefulWidget {
  const SetupDialog({
    super.key,
    required this.title,
    required this.children,
    required this.canSave,
    required this.onSave,
    required this.onDelete,
    required this.deleteLabel,
    this.heading,
    this.subheading,
    this.photo,
    this.onPhoto,
    this.advanced = const [],
    this.advancedSummary,
  });

  /// The kind of piece, e.g. "Grinder" — the head only shows it while
  /// neither [heading] nor [subheading] has text.
  final String title;

  /// The piece's name as typed (live) and its brand: shown like the card
  /// titles ("PREShot") — brand small in the accent color, name big.
  final String? heading;
  final String? subheading;

  /// Thumbnail in the head (see [GearThumb]); tapping it calls [onPhoto].
  final Widget? photo;
  final VoidCallback? onPhoto;

  final List<Widget> children;

  /// Rarely needed fields, folded away under "Advanced".
  final List<Widget> advanced;

  /// What is set in there, shown next to "Advanced" while folded.
  final String? advancedSummary;

  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final String deleteLabel;

  @override
  State<SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends State<SetupDialog> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = widget.heading?.trim() ?? '';
    final brand = widget.subheading?.trim() ?? '';
    // Name with brand as prefix; only one of them: that one alone; neither:
    // the kind of piece.
    final (prefix, big) = name.isNotEmpty
        ? (brand, name)
        : brand.isNotEmpty
        ? ('', brand)
        : ('', widget.title);
    final photo = widget.photo;
    return Padding(
      // Above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 34,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                if (photo != null) ...[
                  GestureDetector(
                    key: const ValueKey('dialog-photo'),
                    onTap: widget.onPhoto,
                    child: photo,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PrefixedTitle(
                      key: const ValueKey('dialog-heading'),
                      prefix: prefix,
                      title: big,
                      active: true,
                      maxLines: 2,
                      fontSize: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...widget.children,
                  if (widget.advanced.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      key: const ValueKey('dialog-advanced'),
                      onTap: () =>
                          setState(() => _advancedOpen = !_advancedOpen),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Text(
                              'Advanced',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            if (!_advancedOpen &&
                                widget.advancedSummary != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.advancedSummary!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textTertiary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                            Icon(
                              _advancedOpen
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: colors.textTertiary,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: _advancedOpen
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: widget.advanced,
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: AppButton(
              label: 'Save',
              onPressed: widget.canSave ? widget.onSave : null,
            ),
          ),
          if (widget.onDelete != null)
            Center(
              child: TextButton.icon(
                onPressed: widget.onDelete,
                icon: Icon(Icons.delete_outline, color: colors.danger),
                label: Text(
                  widget.deleteLabel,
                  style: TextStyle(color: colors.danger),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A row in the editors for a choice instead of text: label on the left
/// (lined up with [SetupField]'s), the choice on the right.
class SetupRow extends StatelessWidget {
  const SetupRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      // The underline choice brings its own room below the text.
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: child),
          ),
        ],
      ),
    );
  }
}

/// The head's thumbnail: the piece's photo (live, so a new one shows right
/// away), else its type's line icon. Tapping it is the photo choice.
class GearThumb extends StatelessWidget {
  const GearThumb({super.key, required this.gearId, required this.icon});

  final String gearId;

  /// Line icon asset for when there is no photo.
  final String icon;

  static const size = 56.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<GearStore>();
    final gear = store.byId(gearId);
    final file = gear == null ? null : store.photoFile(gear);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: file != null
          ? Image.file(
              file,
              width: size,
              height: size,
              fit: (gear?.isCutout ?? false) ? BoxFit.contain : BoxFit.cover,
              cacheWidth: 200,
            )
          : GearIcon(asset: icon, size: 28, color: colors.textSecondary),
    );
  }
}

// A text field in the My Setup dialogs: label and underline in neutral
// tones (not the accent), and — like the bean form — matching earlier
// entries as tappable chips below while typing.
class SetupField extends StatefulWidget {
  const SetupField({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.numeric = false,
    this.signed = false,
    this.suffix,
    this.suggestions = const [],
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool numeric;

  /// A number that may be negative (grind range, zero point): allows a
  /// minus and shows a ± button — the number pad often has no minus key.
  final bool signed;
  final String? suffix;
  final List<String> suggestions;

  @override
  State<SetupField> createState() => _SetupFieldState();
}

class _SetupFieldState extends State<SetupField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(SetupField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // Only entries starting with what is typed; nothing without input.
  List<String> _matches() {
    if (!_focus.hasFocus) return const [];
    final q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final s in widget.suggestions)
        if (s.toLowerCase() != q && s.toLowerCase().startsWith(q)) s,
    ];
  }

  void _flipSign() {
    final t = widget.controller.text.trim();
    _apply(t.startsWith('-') ? t.substring(1) : '-$t');
  }

  void _apply(String value) {
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  // Below this width the label goes into the field as a hint (the narrow
  // offset/amount fields sit next to their own label anyway).
  static const _inlineLabelMinWidth = 150.0;

  // Label column on full-width rows, so the values line up.
  static const _labelWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final neutral = TextStyle(color: colors.textSecondary, fontSize: 14);
    final matches = _matches();
    final focused = _focus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showLabel = width >= _inlineLabelMinWidth;
            final field = TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              textAlign: showLabel ? TextAlign.end : TextAlign.start,
              textCapitalization: widget.numeric
                  ? TextCapitalization.none
                  : TextCapitalization.words,
              keyboardType: widget.numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : null,
              inputFormatters: widget.numeric
                  ? [
                      FilteringTextInputFormatter.allow(
                        widget.signed
                            ? RegExp(r'^-?[0-9.,]*')
                            : RegExp(r'[0-9.,]'),
                      ),
                    ]
                  : null,
              // The blinking cursor keeps the accent; label and line don't.
              cursorColor: colors.accent,
              style: TextStyle(color: colors.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                hintText: showLabel ? '—' : widget.label,
                hintStyle: TextStyle(color: colors.textTertiary, fontSize: 15),
                suffixText: widget.suffix,
                suffixStyle: neutral,
                suffixIcon: widget.signed
                    ? IconButton(
                        tooltip: 'Plus/minus',
                        visualDensity: VisualDensity.compact,
                        onPressed: _flipSign,
                        icon: Text(
                          '±',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 18,
                          ),
                        ),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: InputBorder.none,
              ),
            );
            return DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: focused ? colors.textSecondary : colors.divider,
                    width: focused ? 1 : 0.5,
                  ),
                ),
              ),
              child: showLabel
                  ? Row(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: width >= 260 ? _labelWidth : width * 0.45,
                            minWidth: width >= 260 ? _labelWidth : 0,
                          ),
                          child: GestureDetector(
                            onTap: _focus.requestFocus,
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: neutral,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: field),
                      ],
                    )
                  : field,
            );
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: matches.isEmpty
              ? const SizedBox(width: double.infinity)
              // Without TextFieldTapRegion, a tap on a chip counts as
              // "outside" and takes focus from the field.
              // Underline options in a wrap, like the bean form: typed
              // letters in textPrimary, a thin line marks them tappable. (A
              // horizontal list here once hung the dialog — it measures its
              // content's intrinsic width.) Without TextFieldTapRegion, a tap
              // counts as "outside" and takes focus from the field.
              : TextFieldTapRegion(
                  child: Wrap(
                    spacing: UnderlineSelect.spacing,
                    children: [
                      for (final m in matches.take(6))
                        UnderlineItem(
                          label: m,
                          selected: false,
                          idleUnderline: true,
                          highlight: widget.controller.text.trim(),
                          onTap: () => _apply(m),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

Future<bool> confirmSetupDelete(
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
