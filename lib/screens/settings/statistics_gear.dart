part of 'statistics_screen.dart';

// Statistics → Gear: what each piece on My Coffee Desk has done – grinders
// by coffee ground, brewers, filters with their stock, the rest by use –
// and the brew chains. No ratings here: gear has no target to rate.

String _amount(double grams) => grams >= 1000
    ? '${(grams / 1000).toStringAsFixed(1)} kg'
    : '${grams.round()} g';

String _litres(double ml) =>
    ml >= 1000 ? '${(ml / 1000).toStringAsFixed(1)} l' : '${ml.round()} ml';

String _count(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';

String _usesText(GearUse u) => [
  if (u.shots > 0) _count(u.shots, 'shot'),
  if (u.brews > 0) _count(u.brews, 'brew'),
].join(' · ');

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return 'just now';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 30) return '${d.inDays} d ago';
  return _date(t);
}

/// New on the desk: first used in the last 30 days.
bool _isNew(GearUse u) =>
    u.firstUse != null && DateTime.now().difference(u.firstUse!).inDays < 30;

extension on _StatisticsScreenState {
  List<Widget> _gear(BuildContext context, StatisticsData data) {
    final store = context.watch<GearStore>();
    final stats = GearStats.compute(
      data,
      gear: store.gear,
      chains: store.chains,
      periodStart: _period.start(DateTime.now()),
    );
    final grinders = stats.ofType(GearType.grinder);
    final brewers = stats.ofType(GearType.brewer);
    final filters = stats.ofType(GearType.filter);
    const own = {GearType.grinder, GearType.brewer, GearType.filter};
    final others = [
      for (final p in stats.pieces)
        if (!own.contains(p.type)) p,
    ];
    final blocks = <Widget>[
      if (grinders.isNotEmpty)
        _Block(
          label: 'Grinders',
          trailing: 'coffee through',
          child: Column(
            children: [
              for (final g in grinders)
                _GearRow(
                  use: g,
                  value: _amount(g.grams),
                  detail: g.onDesk
                      ? [
                          if (g.firstUse != null) 'since ${_date(g.firstUse!)}',
                          if (g.uses > 0) _usesText(g),
                        ].join(' · ')
                      : [
                          if (g.firstUse != null && g.lastUse != null)
                            '${_date(g.firstUse!)} – ${_date(g.lastUse!)}',
                          if (g.uses > 0) _usesText(g),
                        ].join(' · '),
                ),
            ],
          ),
        ),
      if (brewers.isNotEmpty)
        _Block(
          label: 'Brewers',
          child: Column(
            children: [
              for (final b in brewers)
                _GearRow(
                  use: b,
                  value: '${b.uses}',
                  detail: [
                    if (b.uses > 0) _usesText(b),
                    if (b.waterMl > 0) '${_litres(b.waterMl)} water',
                  ].join(' · '),
                ),
            ],
          ),
        ),
      if (filters.isNotEmpty)
        _Block(
          label: 'Filters',
          child: Column(
            children: [
              for (final f in filters)
                _GearRow(
                  use: f,
                  value: '${f.uses}',
                  detail: [
                    'used ${f.uses}',
                    if (f.gear?.stock case final left?) '$left left in stock',
                  ].join(' · '),
                ),
            ],
          ),
        ),
      if (others.isNotEmpty)
        _Block(
          label: 'Other gear',
          child: Column(
            children: [
              for (final o in others)
                _GearRow(
                  use: o,
                  overline: o.type.single,
                  value: o.type == GearType.water
                      ? _litres(o.waterMl)
                      : '${o.uses}',
                  detail: o.type == GearType.water
                      ? '${_litres(o.waterMl)} brewed'
                      : _usesText(o),
                ),
            ],
          ),
        ),
      if (stats.chains.isNotEmpty)
        _Block(
          label: 'Brew chains',
          child: Column(
            children: [for (final c in stats.chains) _ChainRow(c, store)],
          ),
        ),
    ];
    return blocks.isEmpty
        ? [
            const _Empty(
              'Choose a brew chain when you brew, and your gear shows up '
              'here.',
            ),
          ]
        : blocks;
  }
}

// Photo of the piece when there is one, else its line icon.
class _GearAvatar extends StatelessWidget {
  const _GearAvatar(this.use, {this.size = 40});
  final GearUse use;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gear = use.gear;
    final file = gear == null
        ? null
        : context.watch<GearStore>().photoFile(gear);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.bg,
        shape: BoxShape.circle,
        border: Border.all(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: file != null
          ? Image.file(
              file,
              width: size,
              height: size,
              fit: (gear?.isCutout ?? false) ? BoxFit.contain : BoxFit.cover,
              cacheWidth: 160,
            )
          : GearIcon(
              asset: use.type.iconAsset(gear?.specs ?? const {}),
              size: size * 0.55,
              color: use.onDesk ? colors.textSecondary : colors.textTertiary,
            ),
    );
  }
}

class _GearRow extends StatelessWidget {
  const _GearRow({
    required this.use,
    required this.value,
    required this.detail,
    this.overline,
  });
  final GearUse use;
  final String value;
  final String detail;

  /// Above the name; the brand when not given.
  final String? overline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final over = overline ?? use.brand;
    final dim = !use.onDesk;
    return InkWell(
      onTap: () => _showGearSheet(context, use),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _GearAvatar(use),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (over != null && over.isNotEmpty)
                    Text(
                      over.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        color: dim ? colors.textTertiary : colors.accent,
                      ),
                    ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          dim ? '${use.name} · not on desk' : use.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: dim
                                ? colors.textTertiary
                                : colors.textPrimary,
                          ),
                        ),
                      ),
                      if (!dim && _isNew(use)) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'NEW',
                            style: TextStyle(
                              fontSize: 9.5,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                              color: colors.bg,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: dim ? colors.textTertiary : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainRow extends StatelessWidget {
  const _ChainRow(this.use, this.store);
  final ChainUse use;
  final GearStore store;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pieces = store.gearOf(use.chain).map((g) => g.label).join(' · ');
    final facts = [
      if (use.shots > 0) _count(use.shots, 'shot'),
      if (use.brews > 0) _count(use.brews, 'brew'),
      if (use.grams > 0) _amount(use.grams),
      if (use.brews > 0 && use.waterMl > 0) _litres(use.waterMl),
      if (use.lastUse != null) 'last ${_ago(use.lastUse!)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            use.chain.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          if (pieces.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                pieces,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: colors.textTertiary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              facts.join(' · '),
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Gear sheet ---------------------------------------------------------------

Future<void> _showGearSheet(BuildContext context, GearUse use) {
  final data = context.findAncestorStateOfType<_StatisticsScreenState>()?._data;
  final store = context.read<GearStore>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => ChangeNotifierProvider<GearStore>.value(
      value: store,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) =>
            _GearSheet(use: use, data: data, store: store, scroll: scroll),
      ),
    ),
  );
}

class _GearSheet extends StatelessWidget {
  const _GearSheet({
    required this.use,
    required this.data,
    required this.store,
    required this.scroll,
  });
  final GearUse use;
  final StatisticsData? data;
  final GearStore store;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final grinder = use.type == GearType.grinder;
    final days = use.firstUse == null
        ? 0
        : DateTime.now().difference(use.firstUse!).inDays + 1;
    final chains = [
      for (final c in store.chains)
        if (use.gear != null && c.gearIds.contains(use.gear!.id)) c.name,
    ];
    final beans = data?.beans ?? const <int, StatBean>{};
    final topBeans = use.beanGrams.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final range = (use.grindMin, use.grindMax);
    String grindText(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _GearAvatar(use, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: _SheetTitle(
                overline: [
                  if (use.brand != null && use.brand!.isNotEmpty) use.brand!,
                  use.type.single,
                ].join(' · '),
                title: use.onDesk ? use.name : '${use.name} · not on desk',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (grinder) ...[
          _NumberRow([
            _Num(
              'Ground',
              _amount(use.grams).split(' ').first,
              _amount(use.grams).split(' ').last,
            ),
            _Num('Shots', '${use.uses}'),
            _Num('Since', use.firstUse == null ? '–' : _date(use.firstUse!)),
          ]),
          const SizedBox(height: 16),
          _NumberRow([
            _Num(
              'Per day',
              days == 0 ? '–' : '${(use.grams / days).round()}',
              'g',
              true,
            ),
            _Num(
              'Grind',
              range.$1 == null
                  ? '–'
                  : range.$1 == range.$2
                  ? grindText(range.$1!)
                  : '${grindText(range.$1!)}–${grindText(range.$2!)}',
            ),
          ]),
        ] else
          _NumberRow([
            _Num('Used', '${use.uses}'),
            if (use.waterMl > 0)
              _Num(
                'Water',
                _litres(use.waterMl).split(' ').first,
                _litres(use.waterMl).split(' ').last,
              ),
            _Num('Since', use.firstUse == null ? '–' : _date(use.firstUse!)),
          ]),
        if (use.gear?.stock case final left? when use.type == GearType.filter)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _Hint([
              _bold('$left'),
              const TextSpan(text: ' left in stock'),
            ]),
          ),
        if (use.burrs.isNotEmpty) ...[
          const _SubHead('Burrs'),
          for (final b
              in use.burrs.values.toList()
                ..sort((a, b) => b.last!.compareTo(a.last!)))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.name,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          '${_date(b.first!)} – ${_date(b.last!)} · '
                          '${_count(b.shots, 'shot')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _amount(b.grams),
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
        ],
        if (chains.isNotEmpty) ...[
          const _SubHead('In chains'),
          Text(
            chains.join(' · '),
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
        ],
        if (topBeans.isNotEmpty) ...[
          const _SubHead('Beans ground'),
          ..._groupedBeans(context, [
            for (final e in topBeans.take(8))
              if (beans[e.key] case final b?) (b, e.value),
          ]),
        ],
      ],
    );
  }
}

// Beans by roaster (accent) with the coffee ground for each (white).
List<Widget> _groupedBeans(
  BuildContext context,
  List<(StatBean, double)> beans,
) {
  final byRoaster = <String, List<(StatBean, double)>>{};
  for (final e in beans) {
    final r = e.$1.roaster?.trim() ?? '';
    (byRoaster[r] ??= []).add(e);
  }
  final roasters = byRoaster.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return [
    for (final r in roasters) ...[
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          (r.isEmpty ? 'No roastery' : r).toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
            color: context.colors.accent,
          ),
        ),
      ),
      for (final (b, grams) in byRoaster[r]!)
        _lineRow(context, b.name, _amount(grams), vertical: 2),
    ],
  ];
}
