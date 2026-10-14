import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import 'history_logic.dart';
import '../../widgets/dot_choice_group.dart';
import '../../widgets/app_button.dart';

// History filter sheet, built like the bean list's: updates the count in the
// button live; the pop result is the new filter (null when swiped away =
// change nothing).
Future<HistoryFilter?> showHistoryFilterSheet(
  BuildContext context, {
  required List<ShotEntry> entries,
  required HistoryFilter initial,
  required String query,
}) {
  return showModalBottomSheet<HistoryFilter>(
    context: context,
    backgroundColor: context.colors.card,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.tile)),
    ),
    builder: (context) =>
        _HistoryFilterSheet(entries: entries, initial: initial, query: query),
  );
}

class _HistoryFilterSheet extends StatefulWidget {
  const _HistoryFilterSheet({
    required this.entries,
    required this.initial,
    required this.query,
  });

  final List<ShotEntry> entries;
  final HistoryFilter initial;
  final String query;

  @override
  State<_HistoryFilterSheet> createState() => _HistoryFilterSheetState();
}

class _HistoryFilterSheetState extends State<_HistoryFilterSheet> {
  late final HistoryFilterOptions _options = HistoryFilterOptions(
    widget.entries,
    enabledMachines: context
        .read<AppSettings>()
        .enabledHomeModes
        .map(shotMachineForHomeMode)
        .toList(),
  );

  late Set<String> _machines;
  late Set<int> _beanIds;
  late Set<String> _roasters;
  late Set<String> _profiles;
  int? _minRating;
  late HistoryDateRange _dateRange;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _machines = {...f.machines};
    _beanIds = {...f.beanIds};
    _roasters = {...f.roasters};
    _profiles = {...f.profiles};
    _minRating = f.minRating;
    _dateRange = f.dateRange;
    _customRange = f.customRange;
  }

  HistoryFilter get _filter => HistoryFilter(
    machines: _machines,
    beanIds: _beanIds,
    roasters: _roasters,
    profiles: _profiles,
    minRating: _minRating,
    dateRange: _dateRange,
    customRange: _customRange,
  );

  void _reset() => setState(() {
    _machines = {};
    _beanIds = {};
    _roasters = {};
    _profiles = {};
    _minRating = null;
    _dateRange = HistoryDateRange.any;
    _customRange = null;
  });

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _dateRange = HistoryDateRange.custom;
    });
  }

  void _setRange(HistoryDateRange range) => setState(
    () => _dateRange = _dateRange == range ? HistoryDateRange.any : range,
  );

  String get _customLabel {
    final r = _customRange;
    if (_dateRange != HistoryDateRange.custom || r == null) {
      return 'Pick range…';
    }
    final a = '${r.start.day}.${r.start.month}.';
    final b = '${r.end.day}.${r.end.month}.';
    return '$a – $b';
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final count = filterShots(
      widget.entries,
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
              if (_options.machines.length > 1)
                _Section('Machine', [
                  for (final m in _options.machines)
                    DotChoiceItem(
                      label: m.label,
                      selected: _machines.contains(m.key),
                      onTap: () => setState(() {
                        if (!_machines.remove(m.key)) _machines.add(m.key);
                      }),
                    ),
                ]),
              if (_options.beans.isNotEmpty)
                _Section('Bean', [
                  for (final b in _options.beans)
                    DotChoiceItem(
                      label: b.name,
                      selected: _beanIds.contains(b.id),
                      onTap: () => setState(() {
                        if (!_beanIds.remove(b.id)) _beanIds.add(b.id);
                      }),
                    ),
                ]),
              _multi('Roastery', _options.roasters, _roasters),
              _multi('Profile', _options.profiles, _profiles),
              _Section('Rating', [
                DotChoiceItem(
                  label: 'Any',
                  selected: _minRating == null,
                  onTap: () => setState(() => _minRating = null),
                ),
                for (final n in [3, 4, 5])
                  DotChoiceItem(
                    label: n == 5 ? '5 ★' : '$n ★ +',
                    selected: _minRating == n,
                    onTap: () =>
                        setState(() => _minRating = _minRating == n ? null : n),
                  ),
              ]),
              _Section('Date', [
                DotChoiceItem(
                  label: 'Today',
                  selected: _dateRange == HistoryDateRange.today,
                  onTap: () => _setRange(HistoryDateRange.today),
                ),
                DotChoiceItem(
                  label: 'Last 7 days',
                  selected: _dateRange == HistoryDateRange.week,
                  onTap: () => _setRange(HistoryDateRange.week),
                ),
                DotChoiceItem(
                  label: 'Last 30 days',
                  selected: _dateRange == HistoryDateRange.month,
                  onTap: () => _setRange(HistoryDateRange.month),
                ),
                DotChoiceItem(
                  label: _customLabel,
                  selected: _dateRange == HistoryDateRange.custom,
                  onTap: _pickRange,
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
              label: count == 1 ? 'Show 1 shot' : 'Show $count shots',
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
        DotChoiceItem(
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
