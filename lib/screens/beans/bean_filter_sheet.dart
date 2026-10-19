import 'package:flutter/material.dart';

import '../../database/database.dart';
import '../../theme/app_theme.dart';
import 'bean_filter.dart';
import 'bean_widgets.dart';
import '../../widgets/underline_select.dart';
import '../../widgets/app_button.dart';

// Filter sheet for the bean list. Updates the count in the button live; the
// pop result is the new filter (null when swiped away = change nothing).
Future<BeanFilter?> showBeanFilterSheet(
  BuildContext context, {
  required List<Bean> beans,
  required BeanFilter initial,
  required String query,
}) {
  return showModalBottomSheet<BeanFilter>(
    context: context,
    backgroundColor: context.colors.card,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.tile)),
    ),
    builder: (context) =>
        _BeanFilterSheet(beans: beans, initial: initial, query: query),
  );
}

class _BeanFilterSheet extends StatefulWidget {
  const _BeanFilterSheet({
    required this.beans,
    required this.initial,
    required this.query,
  });

  final List<Bean> beans;
  final BeanFilter initial;
  final String query;

  @override
  State<_BeanFilterSheet> createState() => _BeanFilterSheetState();
}

class _BeanFilterSheetState extends State<_BeanFilterSheet> {
  static const _ageOptions = [7, 14, 30, 60];

  late final BeanFilterOptions _options = BeanFilterOptions(widget.beans);

  bool? _isBlend;
  late Set<String> _roastedFor;
  late Set<String> _roastLevels;
  late Set<String> _roasters;
  late Set<String> _countries;
  late Set<String> _processings;
  late Set<String> _varieties;
  late Set<String> _producers;
  late Set<String> _tastes;
  int? _maxAgeDays;
  RangeValues? _weight;
  RangeValues? _cost;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _isBlend = f.isBlend;
    _roastedFor = {...f.roastedFor};
    _roastLevels = {...f.roastLevels};
    _roasters = {...f.roasters};
    _countries = {...f.countries};
    _processings = {...f.processings};
    _varieties = {...f.varieties};
    _producers = {...f.producers};
    _tastes = {...f.tastes};
    _maxAgeDays = f.maxAgeDays;
    _weight = f.weight;
    _cost = f.cost;
  }

  BeanFilter get _filter => BeanFilter(
    isBlend: _isBlend,
    roastedFor: _roastedFor,
    roastLevels: _roastLevels,
    roasters: _roasters,
    countries: _countries,
    processings: _processings,
    varieties: _varieties,
    producers: _producers,
    tastes: _tastes,
    maxAgeDays: _maxAgeDays,
    weight: _weight,
    cost: _cost,
  );

  void _reset() => setState(() {
    _isBlend = null;
    _roastedFor = {};
    _roastLevels = {};
    _roasters = {};
    _countries = {};
    _processings = {};
    _varieties = {};
    _producers = {};
    _tastes = {};
    _maxAgeDays = null;
    _weight = null;
    _cost = null;
  });

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final count = filterBeans(
      widget.beans,
      query: widget.query,
      filter: filter,
    ).length;
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
                    color: context.colors.textPrimary,
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
              _Section('Type', [
                UnderlineItem(
                  label: 'Single Origin',
                  selected: _isBlend == false,
                  onTap: () => setState(
                    () => _isBlend = _isBlend == false ? null : false,
                  ),
                ),
                UnderlineItem(
                  label: 'Blend',
                  selected: _isBlend == true,
                  onTap: () =>
                      setState(() => _isBlend = _isBlend == true ? null : true),
                ),
              ]),
              // Fixed options instead of derived from the beans: there are
              // exactly these three.
              _Section('Roasted for', [
                for (final option in roastedForOptions)
                  UnderlineItem(
                    label: option.label,
                    selected: _roastedFor.contains(option.value),
                    onTap: () => setState(() {
                      if (!_roastedFor.remove(option.value)) {
                        _roastedFor.add(option.value);
                      }
                    }),
                  ),
              ]),
              _Section('Roast level', [
                for (final option in roastLevelOptions)
                  UnderlineItem(
                    label: option.label,
                    selected: _roastLevels.contains(option.value),
                    onTap: () => setState(() {
                      if (!_roastLevels.remove(option.value)) {
                        _roastLevels.add(option.value);
                      }
                    }),
                  ),
              ]),
              _multi('Roastery', _options.roasters, _roasters),
              _multi('Country', _options.countries, _countries),
              _multi('Producer', _options.producers, _producers),
              _multi('Variety', _options.varieties, _varieties),
              _multi('Processing', _options.processings, _processings),
              _multi('Taste', _options.tastes, _tastes),
              _Section('Roasted within', [
                for (final days in _ageOptions)
                  UnderlineItem(
                    label: '$days days',
                    selected: _maxAgeDays == days,
                    onTap: () => setState(
                      () => _maxAgeDays = _maxAgeDays == days ? null : days,
                    ),
                  ),
              ]),
              if (_options.weightBounds != null)
                _RangeSection(
                  title: 'Weight',
                  unit: 'g',
                  bounds: _options.weightBounds!,
                  value: _weight,
                  onChanged: (v) => setState(() => _weight = v),
                ),
              if (_options.costBounds != null)
                _RangeSection(
                  title: 'Cost',
                  unit: '€',
                  bounds: _options.costBounds!,
                  value: _cost,
                  onChanged: (v) => setState(() => _cost = v),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: AppButton(
              label: count == 1 ? 'Show 1 bean' : 'Show $count beans',
              onPressed: () => Navigator.of(context).pop(filter),
            ),
          ),
        ),
      ],
    );
  }

  Widget _multi(String title, List<String> values, Set<String> selected) {
    if (values.isEmpty) return const SizedBox.shrink();
    return _Section(title, [
      for (final v in values)
        UnderlineItem(
          label: v,
          selected: selected.any((s) => s.toLowerCase() == v.toLowerCase()),
          onTap: () => setState(() {
            final existing = selected
                .where((s) => s.toLowerCase() == v.toLowerCase())
                .toList();
            if (existing.isEmpty) {
              selected.add(v);
            } else {
              selected.removeAll(existing);
            }
          }),
        ),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.pills);

  final String title;
  final List<Widget> pills;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          Wrap(spacing: 8, runSpacing: 8, children: pills),
        ],
      ),
    );
  }
}

class _RangeSection extends StatelessWidget {
  const _RangeSection({
    required this.title,
    required this.unit,
    required this.bounds,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String unit;
  final RangeValues bounds;
  // null = full range (filter off).
  final RangeValues? value;
  final ValueChanged<RangeValues?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value ?? bounds;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                '${current.start.round()} – ${current.end.round()} $unit',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          RangeSlider(
            values: current,
            min: bounds.start,
            max: bounds.end,
            onChanged: (v) {
              final full = v.start <= bounds.start && v.end >= bounds.end;
              onChanged(full ? null : v);
            },
          ),
        ],
      ),
    );
  }
}
