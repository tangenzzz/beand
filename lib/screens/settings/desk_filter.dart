import 'package:flutter/material.dart';

import '../../models/gear.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/underline_select.dart';

// Search and filter of My Coffee Desk, the same pattern as the bean list
// and the history: free text over brand, model and the type fields, and a
// filter sheet. Every section left empty means "all".

/// In use = some active brew chain uses it; stored = none does.
enum DeskStatus {
  inUse('In use'),
  stored('Stored');

  const DeskStatus(this.label);
  final String label;
}

@immutable
class DeskFilter {
  const DeskFilter({
    this.status = const {},
    this.modes = const {},
    this.types = const {},
    this.brands = const {},
  });

  static const empty = DeskFilter();

  final Set<DeskStatus> status;
  final Set<BrewMode> modes;
  final Set<GearType> types;
  final Set<String> brands;

  int get activeCount =>
      [status, modes, types, brands].where((s) => s.isNotEmpty).length;

  bool get isActive => activeCount > 0;

  bool matches(Gear g, {required bool inUse}) =>
      (status.isEmpty ||
          status.contains(inUse ? DeskStatus.inUse : DeskStatus.stored)) &&
      (modes.isEmpty || modes.any(g.usedFor)) &&
      (types.isEmpty || types.contains(g.type)) &&
      (brands.isEmpty ||
          brands.any((b) => b.toLowerCase() == g.brand?.toLowerCase()));
}

/// Free text: every word must appear in brand, model or a type field.
bool matchesDeskQuery(Gear g, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return true;
  final text = [
    g.brand,
    g.model,
    g.type.single,
    for (final v in g.specs.values)
      if (v is String || v is num) '$v',
  ].whereType<String>().join(' ').toLowerCase();
  return words.every(text.contains);
}

/// The gear search + filter leave over, as the sheet's count.
List<Gear> filterDesk(
  Iterable<Gear> gear, {
  required Set<String> inUse,
  required String query,
  required DeskFilter filter,
}) => [
  for (final g in gear)
    if (matchesDeskQuery(g, query) &&
        filter.matches(g, inUse: inUse.contains(g.id)))
      g,
];

/// Filter sheet; the pop result is the new filter (null when swiped away).
Future<DeskFilter?> showDeskFilterSheet(
  BuildContext context, {
  required List<Gear> gear,
  required Set<String> inUse,
  required String query,
  required DeskFilter initial,
}) => showModalBottomSheet<DeskFilter>(
  context: context,
  backgroundColor: context.colors.card,
  isScrollControlled: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.tile)),
  ),
  builder: (context) => _DeskFilterSheet(
    gear: gear,
    inUse: inUse,
    query: query,
    initial: initial,
  ),
);

class _DeskFilterSheet extends StatefulWidget {
  const _DeskFilterSheet({
    required this.gear,
    required this.inUse,
    required this.query,
    required this.initial,
  });

  final List<Gear> gear;
  final Set<String> inUse;
  final String query;
  final DeskFilter initial;

  @override
  State<_DeskFilterSheet> createState() => _DeskFilterSheetState();
}

class _DeskFilterSheetState extends State<_DeskFilterSheet> {
  late final _status = {...widget.initial.status};
  late final _modes = {...widget.initial.modes};
  late final _types = {...widget.initial.types};
  late final _brands = {...widget.initial.brands};

  DeskFilter get _filter => DeskFilter(
    status: {..._status},
    modes: {..._modes},
    types: {..._types},
    brands: {..._brands},
  );

  void _reset() => setState(() {
    for (final s in <Set<Object>>[_status, _modes, _types, _brands]) {
      s.clear();
    }
  });

  static void _toggle<T>(Set<T> set, T value) {
    if (!set.remove(value)) set.add(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filter = _filter;
    final count = filterDesk(
      widget.gear,
      inUse: widget.inUse,
      query: widget.query,
      filter: filter,
    ).length;
    // Only categories and brands that are on the desk.
    final types = [
      for (final t in GearType.values)
        if (widget.gear.any((g) => g.type == t)) t,
    ];
    final seen = <String>{};
    final brands = [
      for (final g in widget.gear)
        if (g.brand != null && seen.add(g.brand!.toLowerCase())) g.brand!,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Filter',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: filter.isActive ? _reset : null,
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _Section('Status', [
                for (final s in DeskStatus.values)
                  UnderlineItem(
                    label: s.label,
                    selected: _status.contains(s),
                    onTap: () => setState(() => _toggle(_status, s)),
                  ),
              ]),
              _Section('Used for', [
                for (final m in BrewMode.values)
                  UnderlineItem(
                    label: m.label,
                    selected: _modes.contains(m),
                    onTap: () => setState(() => _toggle(_modes, m)),
                  ),
              ]),
              if (types.isNotEmpty)
                _Section('Category', [
                  for (final t in types)
                    UnderlineItem(
                      label: t.label,
                      selected: _types.contains(t),
                      onTap: () => setState(() => _toggle(_types, t)),
                    ),
                ]),
              if (brands.isNotEmpty)
                _Section('Brand', [
                  for (final b in brands)
                    UnderlineItem(
                      label: b,
                      selected: _brands.contains(b),
                      onTap: () => setState(() => _toggle(_brands, b)),
                    ),
                ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: AppButton(
              label: count == 1 ? 'Show 1 piece' : 'Show $count pieces',
              onPressed: () => Navigator.of(context).pop(filter),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.items);

  final String title;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: items),
      ],
    ),
  );
}
