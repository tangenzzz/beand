part of 'statistics_screen.dart';

// Statistics → Beans: coffee countries (spinning map + list) and varieties
// (lineage tree), each opening a sheet. Data comes from OriginStats; the
// collection counts all time, the period only highlights.

String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String _stars(int? r) => r == null ? '' : '$r★';

// --- Coffee countries block ---------------------------------------------------

class _CountriesBlock extends StatefulWidget {
  const _CountriesBlock(this.origins);
  final OriginStats origins;

  @override
  State<_CountriesBlock> createState() => _CountriesBlockState();
}

class _CountriesBlockState extends State<_CountriesBlock> {
  final _belt = GlobalKey<_CoffeeBeltState>();
  var _all = false;

  void _open(CoffeeCountry c) {
    _belt.currentState?.spinTo(c.lon);
    _showCountrySheet(context, c, widget.origins);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.origins;
    final colors = context.colors;
    final tried = o.countries.values.toList()
      ..sort((a, b) => b.beans.length.compareTo(a.beans.length));
    final next = o.nextToTry();
    return _Block(
      label: 'Coffee countries',
      trailing: 'all time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: '${o.countries.length}',
              children: [
                TextSpan(
                  text: ' of ${CoffeeCountries.all.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          Text(
            '${o.countries.length} country profiles unlocked',
            style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
          ),
          const SizedBox(height: 10),
          _CoffeeBelt(key: _belt, origins: o, onTap: _open),
          if (next != null) ...[
            const SizedBox(height: 6),
            _Hint([
              const TextSpan(text: 'Next to try: '),
              _bold(next.next.name),
              TextSpan(text: ' – close to ${next.near.name}'),
            ]),
          ],
          const SizedBox(height: 12),
          UnderlineSelect<bool>(
            options: const [
              UnderlineOption(false, 'Mine'),
              UnderlineOption(true, 'All'),
            ],
            value: _all,
            onChanged: (v) => setState(() => _all = v ?? false),
          ),
          const SizedBox(height: 4),
          if (!_all)
            for (final c in tried) _countryRow(context, c.country, c)
          else
            for (final region in CoffeeRegion.values) ...[
              _SubHead(
                region.label,
                '${CoffeeCountries.all.where((c) => c.region == region && o.countries.containsKey(c.code)).length}'
                ' / ${CoffeeCountries.all.where((c) => c.region == region).length}',
              ),
              for (final c in [
                ...CoffeeCountries.all.where(
                  (c) => c.region == region && o.countries.containsKey(c.code),
                ),
                ...CoffeeCountries.all.where(
                  (c) => c.region == region && !o.countries.containsKey(c.code),
                ),
              ])
                _countryRow(context, c, o.countries[c.code]),
            ],
          if (o.unknownOrigin.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: colors.divider),
            InkWell(
              onTap: () => _showUnknownSheet(context, o.unknownOrigin),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _Hint([
                  TextSpan(
                    text:
                        '${o.unknownOrigin.length} '
                        '${o.unknownOrigin.length == 1 ? 'bean' : 'beans'} '
                        'with unknown origin ',
                  ),
                  TextSpan(
                    text: '›',
                    style: TextStyle(color: colors.accent),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _countryRow(BuildContext context, CoffeeCountry c, CountryStat? s) {
    final colors = context.colors;
    final dim = s == null;
    return InkWell(
      onTap: () => _open(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                c.name,
                style: TextStyle(
                  fontSize: 14,
                  color: dim
                      ? colors.textTertiary
                      : (s.inPeriod
                            ? colors.textPrimary
                            : colors.textSecondary),
                ),
              ),
            ),
            if (s != null) ...[
              Text(
                '${s.beans.length} ${s.beans.length == 1 ? 'bean' : 'beans'}',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  _stars(s.bestRating),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: colors.star),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubHead extends StatelessWidget {
  const _SubHead(this.text, [this.trailing]);
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      letterSpacing: 1,
      fontWeight: FontWeight.w600,
      color: context.colors.textTertiary,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: style)),
          if (trailing != null)
            Text(
              trailing!,
              style: style.copyWith(
                letterSpacing: 0,
                fontWeight: FontWeight.w500,
                color: context.colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

// --- The spinning map --------------------------------------------------------

/// Equirectangular strip from 36° N to 36° S that wraps around: dragging
/// spins it like a globe, tapping a dot opens its country.
class _CoffeeBelt extends StatefulWidget {
  const _CoffeeBelt({super.key, required this.origins, required this.onTap});
  final OriginStats origins;
  final ValueChanged<CoffeeCountry> onTap;

  @override
  State<_CoffeeBelt> createState() => _CoffeeBeltState();
}

class _CoffeeBeltState extends State<_CoffeeBelt>
    with SingleTickerProviderStateMixin {
  static const lat = 36.0;
  // Degrees visible across the width; the height follows at the same scale.
  static const span = 130.0;

  late final AnimationController _spin = AnimationController.unbounded(
    vsync: this,
  );
  WorldGeo? _geo;
  double? _scale;
  var _centered = false;

  @override
  void initState() {
    super.initState();
    WorldGeo.load().then((g) {
      if (mounted) setState(() => _geo = g);
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  double get _world => 360 * _scale!;

  /// Turns the map until [lon] sits in the middle, the short way round.
  void spinTo(double lon) {
    final k = _scale;
    if (k == null) return;
    final width = span * k;
    final target = (lon + 180) * k - width / 2;
    var d = (target - _spin.value) % _world;
    if (d > _world / 2) d -= _world;
    _spin.animateTo(
      _spin.value + d,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final k = width / span;
        _scale = k;
        if (!_centered) {
          _centered = true;
          // Start on the best-known country, or Africa.
          final first = widget.origins.countries.values.toList()
            ..sort((a, b) => b.beans.length.compareTo(a.beans.length));
          final lon = first.isEmpty ? 20.0 : first.first.country.lon;
          _spin.value = (lon + 180) * k - width / 2;
        }
        final height = 2 * lat * k;
        return GestureDetector(
          onHorizontalDragStart: (_) => _spin.stop(),
          onHorizontalDragUpdate: (d) => _spin.value -= d.delta.dx,
          onHorizontalDragEnd: (d) {
            final v = (-d.velocity.pixelsPerSecond.dx).clamp(-1500.0, 1500.0);
            _spin.animateWith(FrictionSimulation(0.15, _spin.value, v));
          },
          onTapUp: (d) => _tap(d.localPosition, k),
          child: SizedBox(
            width: width,
            height: height + 18,
            child: AnimatedBuilder(
              animation: _spin,
              builder: (context, _) => CustomPaint(
                painter: _BeltPainter(
                  geo: _geo,
                  origins: widget.origins,
                  offset: _spin.value % _world,
                  scale: k,
                  colors: context.colors,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _tap(Offset at, double k) {
    final x = at.dx + _spin.value % _world;
    CoffeeCountry? best;
    var bestD = 16.0;
    for (final c in CoffeeCountries.all) {
      for (final shift in [-_world, 0.0, _world]) {
        final dx = (c.lon + 180) * k + shift - x;
        final dy = (lat - c.lat) * k - at.dy;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
    }
    if (best != null) widget.onTap(best);
  }
}

class _BeltPainter extends CustomPainter {
  _BeltPainter({
    required this.geo,
    required this.origins,
    required this.offset,
    required this.scale,
    required this.colors,
  });

  final WorldGeo? geo;
  final OriginStats origins;
  final double offset;
  final double scale;
  final AppColors colors;

  static const lat = _CoffeeBeltState.lat;

  // Coastlines in map pixels, built once per scale.
  static Path? _coast, _land;
  static double? _builtFor;

  Offset _p(double lon, double la) =>
      Offset((lon + 180) * scale, (lat - la) * scale);

  void _build() {
    if (_builtFor == scale || geo == null) return;
    final coast = Path(), land = Path();
    for (final line in geo!.coast) {
      coast.addPolygon([for (final q in line) _p(q.dx, q.dy)], false);
    }
    for (final f in geo!.land) {
      land.addPolygon([for (final q in f) _p(q.dx, q.dy)], true);
    }
    _coast = coast;
    _land = land;
    _builtFor = scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = 2 * lat * scale;
    final world = 360 * scale;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & Size(size.width, h),
      const Radius.circular(10),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Offset.zero & Size(size.width, h),
      Paint()..color = colors.accent.withValues(alpha: 0.05),
    );
    final dash = Paint()
      ..color = colors.divider
      ..strokeWidth = 1;
    for (final la in [23.44, -23.44]) {
      final y = (lat - la) * scale;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 2, y), dash);
      }
    }
    _build();
    final landPaint = Paint()
      ..color = colors.textPrimary.withValues(alpha: 0.05);
    final coastPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = colors.textSecondary.withValues(alpha: 0.75);
    final labelStyle = TextStyle(fontSize: 10.5, color: colors.textPrimary);
    final labels = <(String, Offset)>[];
    for (final shift in [-world, 0.0, world]) {
      canvas.save();
      canvas.translate(shift - offset, 0);
      if (_land != null) canvas.drawPath(_land!, landPaint);
      if (_coast != null) canvas.drawPath(_coast!, coastPaint);
      for (final c in CoffeeCountries.all) {
        final s = origins.countries[c.code];
        final at = _p(c.lon, c.lat);
        if (at.dx + shift - offset < -40 ||
            at.dx + shift - offset > size.width + 40) {
          continue;
        }
        if (s == null) {
          canvas.drawCircle(
            at,
            2.6,
            Paint()..color = colors.textTertiary.withValues(alpha: 0.9),
          );
          continue;
        }
        final strength = s.inPeriod ? 1.0 : 0.5;
        canvas.drawCircle(
          at,
          3.5 + math.min(s.beans.length, 8) * 1.3,
          Paint()..color = colors.accent.withValues(alpha: 0.22 * strength),
        );
        canvas.drawCircle(
          at,
          3.5,
          Paint()..color = colors.accent.withValues(alpha: strength),
        );
        labels.add((c.name, at));
      }
      // Names right of the dots, pushed down when two would overlap
      // (Ethiopia and Kenya, Rwanda and Burundi …).
      labels.sort((a, b) => a.$2.dy.compareTo(b.$2.dy));
      final placed = <Rect>[];
      for (final (name, at) in labels) {
        final tp = TextPainter(
          text: TextSpan(text: name, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        var r = Rect.fromLTWH(at.dx + 7, at.dy - 12, tp.width, tp.height);
        while (placed.any((p) => p.overlaps(r))) {
          r = r.shift(Offset(0, tp.height));
        }
        placed.add(r);
        tp.paint(canvas, r.topLeft);
      }
      labels.clear();
      canvas.restore();
    }
    // Soft edges: the surface seems to run round a ball.
    final fade = Paint()
      ..shader = LinearGradient(
        colors: [
          colors.card,
          colors.card.withValues(alpha: 0),
          colors.card.withValues(alpha: 0),
          colors.card,
        ],
        stops: const [0, 0.14, 0.86, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & Size(size.width, h), fade);
    canvas.restore();
    final small = TextStyle(fontSize: 9, color: colors.textTertiary);
    _text(
      canvas,
      'Tropic of Cancer',
      Offset(2, (lat - 23.44) * scale - 13),
      small,
    );
    _text(
      canvas,
      'Tropic of Capricorn',
      Offset(2, (lat + 23.44) * scale + 2),
      small,
    );
    // Continent names below the strip, moving with it.
    final names = TextStyle(
      fontSize: 10,
      letterSpacing: 0.8,
      color: colors.textTertiary,
    );
    for (final (name, lon) in [
      ('AMERICAS', -75.0),
      ('AFRICA', 20.0),
      ('ASIA', 95.0),
      ('PACIFIC', 160.0),
    ]) {
      for (final shift in [-world, 0.0, world]) {
        final x = (lon + 180) * scale + shift - offset;
        if (x < -40 || x > size.width + 40) continue;
        _textCentered(canvas, name, Offset(x, h + 4), names);
      }
    }
  }

  @override
  bool shouldRepaint(_BeltPainter old) =>
      old.offset != offset ||
      old.geo != geo ||
      old.origins != origins ||
      old.colors != colors ||
      old.scale != scale;
}

void _textCentered(Canvas canvas, String s, Offset at, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at - Offset(tp.width / 2, 0));
}

// --- Country sheet ------------------------------------------------------------

Future<void> _showCountrySheet(
  BuildContext context,
  CoffeeCountry c,
  OriginStats origins,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.colors.card,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
  ),
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.85,
    maxChildSize: 0.95,
    builder: (context, scroll) =>
        _CountrySheet(country: c, origins: origins, scroll: scroll),
  ),
);

class _CountrySheet extends StatelessWidget {
  const _CountrySheet({
    required this.country,
    required this.origins,
    required this.scroll,
  });
  final CoffeeCountry country;
  final OriginStats origins;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = origins.countries[country.code];
    final regions = CoffeeRegions.ofCountry(country.code);
    final profile = CoffeeCountryProfiles.byCode[country.code];
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
        Text(
          country.name,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          [country.region.label, ?country.area].join(' · ').toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
            color: colors.accent,
          ),
        ),
        const SizedBox(height: 16),
        if (s != null)
          _NumberRow4([
            ('${s.beans.length}', 'beans'),
            ('${s.shots}', 'shots'),
            (s.bestRating == null ? '–' : '${s.bestRating}★', 'best'),
            (s.firstCup == null ? '–' : _monthYear(s.firstCup!), 'first cup'),
          ])
        else
          _Hint([
            const TextSpan(text: 'Not yet – no beans from '),
            _bold(country.name),
            const TextSpan(text: ' so far.'),
          ]),
        if (regions.isNotEmpty) ...[
          _SubHead(
            'Regions',
            '${s?.regionBeans.length ?? 0} / ${regions.length}',
          ),
          _MiniMap(country: country, regionBeans: s?.regionBeans ?? const {}),
          for (final r in regions.where(
            (r) => s?.regionBeans.containsKey(r.id) ?? false,
          ))
            _lineRow(
              context,
              r.name,
              '${s!.regionBeans[r.id]} ${s.regionBeans[r.id] == 1 ? 'bean' : 'beans'}',
            ),
          if (regions.any((r) => !(s?.regionBeans.containsKey(r.id) ?? false)))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${s != null && s.regionBeans.isNotEmpty ? 'Not yet: ' : ''}'
                '${regions.where((r) => !(s?.regionBeans.containsKey(r.id) ?? false)).map((r) => r.name).join(' · ')}',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: colors.textTertiary,
                ),
              ),
            ),
        ],
        if (profile != null)
          _ProfileBlock(profile: profile, unlockedSince: s?.firstCup),
        if (s != null && s.varieties.isNotEmpty) ...[
          const _SubHead('Your varieties'),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final v in s.varieties)
                GestureDetector(
                  onTap: () => _showVarietySheet(context, v, origins),
                  child: _Underlined(v.name),
                ),
            ],
          ),
        ],
        if (s != null) ...[
          const _SubHead('Beans'),
          for (final b in s.beans)
            _lineRow(context, b.name, _stars(b.bestRating), star: true),
        ],
      ],
    );
  }
}

Widget _lineRow(
  BuildContext context,
  String left,
  String right, {
  bool star = false,
}) {
  final colors = context.colors;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            left,
            style: TextStyle(fontSize: 14, color: colors.textPrimary),
          ),
        ),
        Text(
          right,
          style: TextStyle(
            fontSize: 12,
            color: star ? colors.star : colors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _Underlined extends StatelessWidget {
  const _Underlined(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(bottom: 1),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.accent)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 14, color: context.colors.textPrimary),
    ),
  );
}

class _NumberRow4 extends StatelessWidget {
  const _NumberRow4(this.items);
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (final (value, label) in items)
          Expanded(
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: value.length > 6 ? 15 : 17,
                    fontWeight: FontWeight.w500,
                    color: value.endsWith('★')
                        ? colors.star
                        : colors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The country's profile — the reward: shown once a bean from the country
/// was brewed, otherwise blurred placeholders and a hint.
class _ProfileBlock extends StatelessWidget {
  const _ProfileBlock({required this.profile, required this.unlockedSince});
  final CoffeeCountryProfile profile;
  final DateTime? unlockedSince;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final p = profile;
    Widget head(String state, Color color) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'PROFILE',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: colors.textTertiary,
              ),
            ),
          ),
          Text(
            state,
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
    if (unlockedSince == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head('LOCKED', colors.textTertiary),
          for (final (label, w) in [
            ('TYPICAL CUP', 70.0),
            ('ALTITUDE', 120.0),
            ('HARVEST', 60.0),
            ('PROCESS', 140.0),
          ])
            _ProfileRow(
              label,
              child: Align(
                alignment: Alignment.centerLeft,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                  child: Container(
                    width: w,
                    height: 9,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.divider),
            ),
            child: _Hint([
              const TextSpan(text: 'Brew a bean from '),
              _bold(p.country.name),
              const TextSpan(text: ' to unlock its profile.'),
            ]),
          ),
        ],
      );
    }
    final rank = CoffeeCountryProfiles.productionRank(p.code);
    String? text(List<String> list) => list.isEmpty ? null : list.join(' · ');
    final rows = <(String, String?)>[
      ('TYPICAL CUP', text(p.typicalCup)),
      ('ALTITUDE', p.altitude),
      ('HARVEST', p.harvest),
      ('PROCESS', text(p.process)),
      (
        'VARIETIES',
        text([for (final v in p.varieties) CoffeeVarieties.byId[v]!.name]),
      ),
      (
        'PRODUCTION',
        p.productionTonnes == null
            ? 'small producer'
            : '#$rank · ${_thousands(p.productionTonnes!)} t',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head(
          'UNLOCKED ${_monthYear(unlockedSince!).toUpperCase()}',
          colors.accent,
        ),
        for (final (label, value) in rows)
          if (value != null)
            _ProfileRow(
              label,
              child: Text(
                value,
                style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
              ),
            ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Divider(height: 1, color: colors.divider),
        ),
        const SizedBox(height: 10),
        Text(
          p.fact,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sources: ${{for (final u in p.sources) Uri.parse(u).host.replaceFirst('www.', '')}.join(' · ')}',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

String _thousands(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

class _ProfileRow extends StatelessWidget {
  const _ProfileRow(this.label, {required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
              color: context.colors.textTertiary,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

// The country with its neighbours and its regions as dots.
class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.country, required this.regionBeans});
  final CoffeeCountry country;
  final Map<String, int> regionBeans;

  @override
  Widget build(BuildContext context) => FutureBuilder<WorldGeo>(
    future: WorldGeo.load(),
    builder: (context, snap) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 140,
          width: double.infinity,
          child: CustomPaint(
            painter: _MiniMapPainter(
              geo: snap.data,
              country: country,
              regionBeans: regionBeans,
              colors: context.colors,
            ),
          ),
        ),
      ),
    ),
  );
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({
    required this.geo,
    required this.country,
    required this.regionBeans,
    required this.colors,
  });
  final WorldGeo? geo;
  final CoffeeCountry country;
  final Map<String, int> regionBeans;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colors.accent.withValues(alpha: 0.05),
    );
    final regions = CoffeeRegions.ofCountry(country.code);
    final own = geo?.borders[country.code];
    // Frame the whole country when it is compact; big ones (Brazil, the
    // US with Hawaii, China) by their regions.
    var pts = <Offset>[
      for (final r in regions) Offset(r.lon, r.lat),
      if (regions.isEmpty) Offset(country.lon, country.lat),
    ];
    if (own != null) {
      final all = own.expand((r) => r).toList();
      final w =
          all.map((p) => p.dx).reduce(math.max) -
          all.map((p) => p.dx).reduce(math.min);
      if (w < 26) pts = all;
    }
    var x0 = pts.map((p) => p.dx).reduce(math.min);
    var x1 = pts.map((p) => p.dx).reduce(math.max);
    var y0 = pts.map((p) => p.dy).reduce(math.min);
    var y1 = pts.map((p) => p.dy).reduce(math.max);
    final pad = math.max(1.0, math.max((x1 - x0) * .08, (y1 - y0) * .08));
    x0 -= pad;
    x1 += pad;
    y0 -= pad;
    y1 += pad;
    final k = math.min(size.width / (x1 - x0), size.height / (y1 - y0));
    final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    Offset m(Offset q) => Offset(
      size.width / 2 + (q.dx - cx) * k,
      size.height / 2 - (q.dy - cy) * k,
    );
    if (geo != null) {
      final others = Path(), mine = Path();
      for (final MapEntry(key: iso, value: rings) in geo!.borders.entries) {
        for (final r in rings) {
          (iso == country.code ? mine : others).addPolygon([
            for (final q in r) m(q),
          ], true);
        }
      }
      canvas.drawPath(
        others,
        Paint()..color = colors.textPrimary.withValues(alpha: 0.035),
      );
      canvas.drawPath(
        others,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = colors.textTertiary,
      );
      canvas.drawPath(
        mine,
        Paint()..color = colors.accent.withValues(alpha: 0.10),
      );
      canvas.drawPath(
        mine,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.accent.withValues(alpha: 0.8),
      );
    }
    for (final r in regions.where((r) => !regionBeans.containsKey(r.id))) {
      canvas.drawCircle(
        m(Offset(r.lon, r.lat)),
        2.6,
        Paint()..color = colors.textTertiary,
      );
    }
    final tried = regions.where((r) => regionBeans.containsKey(r.id)).toList();
    for (final r in tried) {
      final at = m(Offset(r.lon, r.lat));
      canvas.drawCircle(
        at,
        3.5 + math.min(regionBeans[r.id]!, 6) * 1.5,
        Paint()..color = colors.accent.withValues(alpha: 0.22),
      );
      canvas.drawCircle(at, 3.5, Paint()..color = colors.accent);
    }
    // Labels to the right, nudged apart when dots sit close together.
    final style = TextStyle(fontSize: 10.5, color: colors.textPrimary);
    var lastY = -99.0;
    for (final (r, at) in [
      for (final r in tried) (r, m(Offset(r.lon, r.lat))),
    ]..sort((a, b) => a.$2.dy.compareTo(b.$2.dy))) {
      final y = math.max(at.dy - 7, lastY + 12);
      lastY = y;
      final right = at.dx < size.width - 90;
      final tp = TextPainter(
        text: TextSpan(text: r.name, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(right ? at.dx + 10 : at.dx - 10 - tp.width, y));
    }
  }

  @override
  bool shouldRepaint(_MiniMapPainter old) =>
      old.geo != geo || old.country != country || old.colors != colors;
}

Future<void> _showUnknownSheet(BuildContext context, List<String> beans) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Text(
            'Unknown origin',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const SettingsText(
            'The country of these beans is empty or not a coffee country '
            'the app knows. Add it in the bean to count it.',
          ),
          const SizedBox(height: 8),
          for (final b in beans) _lineRow(context, b, ''),
        ],
      ),
    );

// --- Varieties block ----------------------------------------------------------

class _VarietiesBlock extends StatefulWidget {
  const _VarietiesBlock(this.origins);
  final OriginStats origins;

  @override
  State<_VarietiesBlock> createState() => _VarietiesBlockState();
}

class _VarietiesBlockState extends State<_VarietiesBlock> {
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.origins;
    final colors = context.colors;
    // Ancestors of what you had: shown as the path to your varieties.
    final onPath = <String>{
      for (final id in o.varieties.keys)
        for (final a in CoffeeVarieties.ancestorsOf(id)) a.id,
    };
    final children = <Widget>[];
    for (final line in VarietyLine.values) {
      final inLine = [
        for (final v in CoffeeVarieties.all)
          if (v.line == line) v,
      ];
      final kids = <String, List<CoffeeVariety>>{};
      final top = <CoffeeVariety>[];
      for (final v in inLine) {
        final parent = v.parents
            .where((p) => CoffeeVarieties.byId[p]?.line == line)
            .firstOrNull;
        if (parent != null) {
          (kids[parent] ??= []).add(v);
        } else {
          top.add(v);
        }
      }
      bool keep(CoffeeVariety v) =>
          _all ||
          o.varieties.containsKey(v.id) ||
          onPath.contains(v.id) ||
          (kids[v.id] ?? const []).any(keep);
      final shown = top.where(keep).toList();
      if (shown.isEmpty) continue;
      final mine = inLine.where((v) => o.varieties.containsKey(v.id)).length;
      final hidden = _all ? 0 : inLine.length - inLine.where(keep).length;
      children.add(_SubHead(line.label, '$mine / ${inLine.length}'));
      for (final v in shown) {
        children.add(_node(context, v, kids, keep, onPath, line));
      }
      if (hidden > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 17, top: 2),
            child: Text(
              '+$hidden more',
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
          ),
        );
      }
    }
    return _Block(
      label: 'Varieties',
      trailing: 'all time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: '${o.varieties.length}',
              children: [
                TextSpan(
                  text: ' of ${CoffeeVarieties.all.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          UnderlineSelect<bool>(
            options: const [
              UnderlineOption(false, 'Mine'),
              UnderlineOption(true, 'All'),
            ],
            value: _all,
            onChanged: (v) => setState(() => _all = v ?? false),
          ),
          if (o.varieties.isEmpty && !_all)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SettingsText(
                'No known variety in your beans yet – fill in the variety '
                'of a bean to start your tree.',
              ),
            ),
          ...children,
          const SizedBox(height: 12),
          Text(
            'Lineage: World Coffee Research',
            style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _node(
    BuildContext context,
    CoffeeVariety v,
    Map<String, List<CoffeeVariety>> kids,
    bool Function(CoffeeVariety) keep,
    Set<String> onPath,
    VarietyLine line,
  ) {
    final colors = context.colors;
    final stat = widget.origins.varieties[v.id];
    final path = stat == null && onPath.contains(v.id);
    final children = (kids[v.id] ?? const []).where(keep).toList();
    final crossing = v.parents.length > 1
        ? v.parents.map((p) => CoffeeVarieties.byId[p]!.name).join(' × ')
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _showVarietySheet(context, v, widget.origins),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stat != null ? colors.accent : null,
                    border: Border.all(
                      color: stat != null || path
                          ? colors.accent
                          : colors.textTertiary,
                      width: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    v.name,
                    style: TextStyle(
                      fontSize: 14,
                      color: stat != null
                          ? (stat.inPeriod
                                ? colors.textPrimary
                                : colors.textSecondary)
                          : (path ? colors.textSecondary : colors.textTertiary),
                    ),
                  ),
                ),
                if (stat != null)
                  Text(
                    _stars(stat.bestRating),
                    style: TextStyle(fontSize: 12, color: colors.star),
                  )
                else if (crossing != null)
                  Flexible(
                    child: Text(
                      crossing,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (children.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: colors.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in children)
                  _node(context, c, kids, keep, onPath, line),
              ],
            ),
          ),
      ],
    );
  }
}

// --- Variety sheet --------------------------------------------------------------

Future<void> _showVarietySheet(
  BuildContext context,
  CoffeeVariety v,
  OriginStats origins,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.colors.card,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
  ),
  builder: (context) {
    final colors = context.colors;
    final stat = origins.varieties[v.id];
    // One line per parent: its line's root → parent → this variety.
    final lineage = v.parents.isEmpty
        ? ['${v.name} is the root of its line']
        : [
            for (final p in v.parents)
              [
                ...CoffeeVarieties.ancestorsOf(p).reversed
                    .where((a) => a.isRoot)
                    .map((a) => a.name),
                CoffeeVarieties.byId[p]!.name,
                v.name,
              ].join(' → '),
          ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            v.name,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
          Text(
            v.line.label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
              color: colors.accent,
            ),
          ),
          const SizedBox(height: 14),
          if (stat != null)
            _NumberRow4([
              (
                '${stat.beans.length}',
                stat.beans.length == 1 ? 'bean' : 'beans',
              ),
              (stat.bestRating == null ? '–' : '${stat.bestRating}★', 'best'),
            ])
          else
            const SettingsText('Not in your beans yet.'),
          const _SubHead('Lineage'),
          for (final l in lineage)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                l,
                style: TextStyle(fontSize: 14, color: colors.textPrimary),
              ),
            ),
          if (v.note != null) ...[
            const SizedBox(height: 8),
            SettingsText(v.note!),
          ],
          if (stat != null) ...[
            const _SubHead('Beans'),
            for (final b in stat.beans)
              _lineRow(context, b.name, _stars(b.bestRating), star: true),
          ],
          if (v.wcr != null) ...[
            const SizedBox(height: 12),
            Text(
              'Source: World Coffee Research',
              style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  },
);
