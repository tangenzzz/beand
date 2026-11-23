part of 'statistics_screen.dart';

// Statistics → Gear: what each piece on My Coffee Desk has done – machines
// first, grinders by coffee ground, brewers, filters with their stock, the rest by use –
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
    final machines = stats.ofType(GearType.machine);
    const own = {
      GearType.machine,
      GearType.grinder,
      GearType.brewer,
      GearType.filter,
    };
    final others = [
      for (final p in stats.pieces)
        if (!own.contains(p.type)) p,
    ];
    final blocks = <Widget>[
      if (machines.isNotEmpty)
        _Block(
          label: 'Machines',
          child: Column(
            children: [
              for (final m in machines)
                _GearRow(
                  use: m,
                  value: '${m.uses}',
                  detail: [
                    if (m.firstUse != null) 'since ${_date(m.firstUse!)}',
                    if (m.uses > 0) _usesText(m),
                    if (m.waterMl > 0) '${_litres(m.waterMl)} water',
                  ].join(' · '),
                ),
            ],
          ),
        ),
      if (grinders.isNotEmpty)
        _Block(
          label: 'Grinders',
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
      if (stats.grinderPairs case final pairs when pairs.isNotEmpty)
        _Block(
          label: 'Grinder vs. grinder',
          info:
              'Only shots with the same bean, the same profile and the same '
              'brew method are compared. Grind is the typical setting per '
              'bean; time and ratio are averaged over those shots only.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, pair) in pairs.indexed) ...[
                if (i > 0) const SizedBox(height: 18),
                _PairTable(pair, data.beans),
              ],
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
            // Stretch: a short row would otherwise sit centred, looking
            // indented.
            crossAxisAlignment: CrossAxisAlignment.stretch,
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

// Two grinders on the beans both have ground: the setting per bean – a
// translation when switching – then shot time and ratio over those beans.
class _PairTable extends StatelessWidget {
  const _PairTable(this.pair, this.beans);
  final GrinderPair pair;
  final Map<int, StatBean> beans;

  static String _grind(double? v) => v == null
      ? '–'
      : (v == v.roundToDouble()
            ? v.toStringAsFixed(0)
            : '${(v * 100).round() / 100}');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget cell(
      String text, {
      Color? color,
      double size = 13.5,
      FontWeight? weight,
    }) => SizedBox(
      width: 78,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color ?? colors.textPrimary,
        ),
      ),
    );
    Widget head(GearUse g) => SizedBox(
      width: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (g.brand != null && g.brand!.isNotEmpty)
            Text(
              g.brand!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
          Text(
            g.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
          ),
        ],
      ),
    );
    Widget row(String label, String a, String b, {bool dimLabel = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dimLabel ? 12.5 : 14,
                    color: dimLabel ? colors.textSecondary : colors.textPrimary,
                  ),
                ),
              ),
              cell(a),
              cell(b),
            ],
          ),
        );
    // Pour-over times in minutes, shots in seconds.
    String secs(double? v) {
      if (v == null) return '–';
      if (v < 90) return '${v.round()} s';
      final t = v.round();
      return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
    }

    String ratio(double? v) => v == null ? '–' : '1:${v.toStringAsFixed(1)}';
    // A run row: the bean, under it the profile it was brewed with.
    Widget runRow(RunKey k, double? a, double? b) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  beans[k.bean]?.name ?? '–',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
                if (k.profile.isNotEmpty)
                  Text(
                    k.profile,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.textTertiary),
                  ),
              ],
            ),
          ),
          cell(_grind(a)),
          cell(_grind(b)),
        ],
      ),
    );
    final methods = pair.methods;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [const Spacer(), head(pair.a), head(pair.b)],
        ),
        for (final pourOver in methods) ...[
          // Espresso and pour over never mix: each has its own rows and
          // its own averages.
          if (methods.length > 1)
            _SubHead(pourOver ? 'Pour over' : 'Espresso')
          else
            const SizedBox(height: 6),
          for (final (k, a, b)
              in pair.runs.where((r) => r.$1.pourOver == pourOver).take(6))
            runRow(k, a, b),
          if (pair.runs.where((r) => r.$1.pourOver == pourOver).length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+${pair.runs.where((r) => r.$1.pourOver == pourOver).length - 6} more',
                style: TextStyle(fontSize: 12, color: colors.textTertiary),
              ),
            ),
          if (pair.seconds(pair.a, pourOver: pourOver) != null ||
              pair.seconds(pair.b, pourOver: pourOver) != null)
            row(
              pourOver ? 'Brew time' : 'Shot time',
              secs(pair.seconds(pair.a, pourOver: pourOver)),
              secs(pair.seconds(pair.b, pourOver: pourOver)),
              dimLabel: true,
            ),
          if (pair.ratio(pair.a, pourOver: pourOver) != null ||
              pair.ratio(pair.b, pourOver: pourOver) != null)
            row(
              'Ratio',
              ratio(pair.ratio(pair.a, pourOver: pourOver)),
              ratio(pair.ratio(pair.b, pourOver: pourOver)),
              dimLabel: true,
            ),
        ],
      ],
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
          _FoldHead(
            'Beans ground',
            open: context.watch<AppSettings>().gearBeansOpen,
            onTap: () {
              final s = context.read<AppSettings>();
              s.setGearBeansOpen(!s.gearBeansOpen);
            },
          ),
          // Folded or not is remembered, also after the app was closed.
          if (context.watch<AppSettings>().gearBeansOpen)
            ..._groupedBeans(context, [
              for (final e in topBeans.take(8))
                if (beans[e.key] case final b?) (b, e.value),
            ]),
        ],
      ],
    );
  }
}

// A sub-heading that folds what is below it, with a chevron at the right.
class _FoldHead extends StatelessWidget {
  const _FoldHead(this.text, {required this.open, required this.onTap});
  final String text;
  final bool open;
  final VoidCallback onTap;

  @override
  // No ripple: the whole row would flash light for a moment.
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Row(
      children: [
        Expanded(child: _SubHead(text)),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Icon(
            open ? Icons.expand_less : Icons.expand_more,
            size: 20,
            color: context.colors.textTertiary,
          ),
        ),
      ],
    ),
  );
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
