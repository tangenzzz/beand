import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../models/coffee_countries.dart';
import '../../models/coffee_country_profiles.dart';
import '../../models/coffee_regions.dart';
import '../../models/coffee_varieties.dart';
import '../../services/app_settings.dart';
import '../../services/origin_stats.dart';
import '../../services/statistics.dart';
import '../../theme/app_theme.dart';
import '../../widgets/underline_select.dart';
import '../../widgets/world_geo.dart';
import '../history/history_logic.dart';
import 'settings_widgets.dart';

part 'statistics_origins.dart';

enum _Section { activity, beans, profiles }

const _sectionLabels = {
  _Section.activity: 'Activity',
  _Section.beans: 'Beans',
  _Section.profiles: 'Profiles',
};

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
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

/// Home mode → machine key in Shots.machine.
const _modeMachine = {
  HomeMode.meticulous: 'meticulous',
  HomeMode.pourOver: 'pourover',
  HomeMode.gaggimate: 'gaggimate',
  HomeMode.espresso: 'espresso',
};

// Settings → Statistics: three tabs (Activity, Beans, Profiles) over one
// period. The data is read once when the page opens; switching tab or
// period only recomputes.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late final Future<StatisticsData> _data;
  var _section = _Section.activity;
  HomeMode? _profileMode;

  @override
  void initState() {
    super.initState();
    _data = StatisticsData.load(context.read<AppDatabase>());
  }

  // Remembered in AppSettings, so the page opens on the last period even
  // after the app was closed.
  StatsPeriod get _period =>
      StatsPeriod.values.asNameMap()[context
          .watch<AppSettings>()
          .statisticsPeriod] ??
      StatsPeriod.month;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: FutureBuilder<StatisticsData>(
        future: _data,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
                child: UnderlineSelect<_Section>(
                  options: [
                    for (final s in _Section.values)
                      UnderlineOption(s, _sectionLabels[s]!),
                  ],
                  value: _section,
                  onChanged: (s) => setState(() => _section = s ?? _section),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: UnderlineSelect<StatsPeriod>(
                  options: [
                    for (final p in StatsPeriod.values)
                      UnderlineOption(p, p.label),
                  ],
                  value: _period,
                  onChanged: (p) {
                    if (p != null) {
                      context.read<AppSettings>().setStatisticsPeriod(p.name);
                    }
                  },
                ),
              ),
              if (snapshot.hasError)
                SettingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.dividerInset),
                      child: SettingsText(
                        'Could not read the statistics: ${snapshot.error}',
                      ),
                    ),
                  ],
                )
              else if (data == null)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                _card(context, data, Statistics.compute(data, _period)),
            ],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, StatisticsData data, Statistics s) {
    final settings = context.watch<AppSettings>();
    return SettingsCard(
      children: switch (_section) {
        _Section.activity => _activity(context, s),
        _Section.beans => _beans(
          context,
          s,
          OriginStats.compute(data, periodStart: _period.start(DateTime.now())),
        ),
        _Section.profiles => _profiles(context, s, settings),
      },
    );
  }

  // --- Activity -----------------------------------------------------------

  List<Widget> _activity(BuildContext context, Statistics s) {
    final currency = context.read<AppSettings>().beanCurrency.symbol;
    return [
      _Block(
        label: 'Overview',
        trailing: s.period.description,
        child: Column(
          children: [
            // Grouped by theme, one row each: what you made · coffee and
            // water · the bags · the money.
            _NumberRow([
              _Num('Shots', '${s.shotCount}'),
              _Num('Brews', '${s.brewCount}'),
              _duration('Under pressure', s.underPressureMs),
            ]),
            const SizedBox(height: 18),
            _NumberRow([
              _weight('Ground', s.groundGrams),
              _volume('Through', s.throughMl),
              _volume('In cup', s.inCupGrams),
            ]),
            const SizedBox(height: 18),
            _NumberRow([
              _Num('Empty bags', '${s.emptyBags}'),
              s.bagDaysAvg == null
                  ? const _Num('Bag lasts', '–')
                  : _Num('Bag lasts', '${s.bagDaysAvg!.round()}', 'days', true),
              s.gramsPerDay == null
                  ? const _Num('Per day', '–')
                  : _Num('Per day', '${s.gramsPerDay!.round()}', 'g', true),
            ]),
            const SizedBox(height: 18),
            _NumberRow([
              _Num(
                'Value brewed',
                s.valueBrewed == null
                    ? '–'
                    : '$currency ${s.valueBrewed!.round()}',
              ),
              _Num(
                'Bags bought',
                s.bagsBought == null
                    ? '–'
                    : '$currency ${s.bagsBought!.round()}',
              ),
            ]),
          ],
        ),
      ),
      if (s.byMachine.isNotEmpty)
        _Block(
          label: 'Brewed with',
          child: _StackedBar([
            for (final m in s.byMachine)
              _Part(
                '${ShotMachine.fromKey(m.label).label} ${m.count}',
                m.count,
                // The same colors as the History badges.
                ShotMachine.fromKey(m.label).color,
              ),
          ]),
        ),
      if (s.fastest != null ||
          s.highestPressure != null ||
          s.biggestYield != null)
        _Block(
          label: 'Records',
          trailing: 'espresso',
          child: Column(
            children: [
              if (s.fastest case final r?)
                _RecordRow(
                  'Fastest shot',
                  '${(r.value / 1000).toStringAsFixed(1)} s',
                  r.shot,
                ),
              if (s.slowest case final r?)
                _RecordRow(
                  'Slowest shot',
                  '${(r.value / 1000).toStringAsFixed(1)} s',
                  r.shot,
                ),
              if (s.highestPressure case final r?)
                _RecordRow(
                  'Highest pressure',
                  '${r.value.toStringAsFixed(1)} bar',
                  r.shot,
                ),
              if (s.biggestYield case final r?)
                _RecordRow(
                  'Biggest yield',
                  '${r.value.toStringAsFixed(1)} g',
                  r.shot,
                ),
            ],
          ),
        ),
      if (s.pistonTravelMm > 0)
        _Block(
          label: 'Meticulous',
          child: Row(
            children: [
              _Mini(_formatDistance(s.pistonTravelMm), 'piston traveled'),
            ],
          ),
        ),
      _Block(
        label: 'Activity',
        trailing: 'last ${Statistics.heatmapWeeks} weeks',
        child: _Heatmap(start: s.heatmapStart, perDay: s.perDay),
      ),
      if (s.drinks > 0) ...[
        _Block(
          label: 'Coffee hours',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HourBars(s.perHour),
              if (s.busiestHour case final h?) ...[
                const SizedBox(height: 10),
                _Hint([
                  const TextSpan(text: 'Most between '),
                  _bold('${_hour(h)} and ${_hour((h + 2) % 24)}'),
                ]),
              ],
            ],
          ),
        ),
        _Block(
          label: 'Habits',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Mini(_clock(s.earliestMinute!), 'earliest coffee'),
                  _Mini(_clock(s.latestMinute!), 'latest coffee'),
                ],
              ),
              if (s.labDay case final d?) ...[
                const SizedBox(height: 14),
                _Hint([
                  _bold(_weekdays[d]),
                  TextSpan(
                    text:
                        ' is your lab day · ${_changes(s.profileChangesOnLabDay, 'profile')}'
                        '${s.profileChangesOnLabDay > 0 && s.beanChangesOnLabDay > 0 ? ' and ' : ''}'
                        '${_changes(s.beanChangesOnLabDay, 'bean')}',
                  ),
                ]),
                const SizedBox(height: 8),
                _WeekdayBars(s.changesPerWeekday, highlight: d),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  // --- Beans --------------------------------------------------------------

  List<Widget> _beans(BuildContext context, Statistics s, OriginStats origins) {
    final palette = _palette(context.colors);
    List<_Part> parts(List<StatCount> list) {
      final total = list.fold<int>(0, (t, c) => t + c.count);
      final shown = list.take(4).toList();
      final rest = total - shown.fold<int>(0, (t, c) => t + c.count);
      return [
        for (var i = 0; i < shown.length; i++)
          _Part(
            '${shown[i].label} ${(shown[i].count * 100 / total).round()} %',
            shown[i].count,
            palette[i],
          ),
        if (rest > 0)
          _Part(
            'Other ${(rest * 100 / total).round()} %',
            rest,
            context.colors.textTertiary,
          ),
      ];
    }

    // Where the coffee comes from first (countries, then varieties), then
    // how it was processed and who roasted it.
    final blocks = <Widget>[
      _CountriesBlock(origins),
      _VarietiesBlock(origins),
      if (s.processing.isNotEmpty)
        _Block(label: 'Processing', child: _StackedBar(parts(s.processing))),
      if (s.topRoasters.isNotEmpty)
        _Block(label: 'Top roasters', child: _BarList(s.topRoasters)),
      // The bag numbers moved to the Activity overview; the quickest bag
      // stays here, it names a bean.
      if (s.fastestBag case final name?)
        _Block(
          label: 'Bags',
          child: _Hint([
            const TextSpan(text: 'Fastest gone: '),
            _bold(name),
            TextSpan(text: ' in ${s.fastestBagDays} days'),
          ]),
        ),
    ];
    return blocks.isEmpty
        ? [const _Empty('No beans with shots in this period.')]
        : blocks;
  }

  // --- Profiles -----------------------------------------------------------

  List<Widget> _profiles(
    BuildContext context,
    Statistics s,
    AppSettings settings,
  ) {
    final modes = settings.enabledHomeModes;
    if (modes.isEmpty) return [const _Empty('No home mode is switched on.')];
    final mode = modes.contains(_profileMode) ? _profileMode! : modes.first;
    final top = s.profilesByMachine[_modeMachine[mode]] ?? const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.dividerInset,
          14,
          AppSpacing.dividerInset,
          4,
        ),
        child: UnderlineSelect<HomeMode>(
          options: [for (final m in modes) UnderlineOption(m, m.label)],
          value: mode,
          onChanged: (m) => setState(() => _profileMode = m ?? mode),
        ),
      ),
      _Block(
        label: 'Top 5 profiles',
        child: top.isEmpty
            ? const SettingsText('No brews in this period.')
            : _BarList(top),
      ),
    ];
  }
}

// --- Formatting -------------------------------------------------------------

_Num _weight(String label, double grams) => grams >= 1000
    ? _Num(label, (grams / 1000).toStringAsFixed(1), 'kg')
    : _Num(label, '${grams.round()}', 'g');

_Num _volume(String label, double ml) => ml >= 1000
    ? _Num(label, (ml / 1000).toStringAsFixed(1), 'l')
    : _Num(label, '${ml.round()}', 'ml');

_Num _duration(String label, int ms) {
  final minutes = (ms / 60000).round();
  if (minutes < 60) return _Num(label, '$minutes', 'min');
  return _Num(
    label,
    '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}',
    null,
  );
}

String _formatDistance(double mm) => mm >= 1000000
    ? '${(mm / 1000000).toStringAsFixed(2)} km'
    : mm >= 1000
    ? '${(mm / 1000).toStringAsFixed(1)} m'
    : '${mm.round()} mm';

String _clock(int minute) {
  final h = minute ~/ 60, m = minute % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

String _hour(int h) => h == 0
    ? '12 am'
    : h < 12
    ? '$h am'
    : h == 12
    ? '12 pm'
    : '${h - 12} pm';

String _changes(int n, String what) =>
    n == 0 ? '' : '$n $what change${n == 1 ? '' : 's'}';

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

List<Color> _palette(AppColors c) => [
  c.accent,
  c.sensorMid,
  c.sensorDown,
  c.sensorUp,
];

TextSpan _bold(String text) => TextSpan(
  text: text,
  style: const TextStyle(fontWeight: FontWeight.w500),
);

// --- Building blocks --------------------------------------------------------

// One block of the card: uppercase label (with an optional grey note on the
// right), then the content.
class _Block extends StatelessWidget {
  const _Block({required this.label, required this.child, this.trailing});

  final String label;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsGroupLabel(
        label,
        trailing: trailing == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.colors.textTertiary,
                  ),
                ),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.dividerInset,
          10,
          AppSpacing.dividerInset,
          18,
        ),
        child: child,
      ),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.dividerInset),
    child: SettingsText(text),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.spans);
  final List<InlineSpan> spans;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: spans,
      style: TextStyle(
        fontSize: 13,
        color: context.colors.textSecondary,
        height: 1.4,
      ),
    ),
  );
}

class _Num {
  const _Num(this.label, this.value, [this.unit, this.average = false]);
  final String label;
  final String value;
  final String? unit;

  /// An average, marked with ⌀ in front of the number.
  final bool average;
}

// The overview: small uppercase label above the number, both centered.
class _NumberRow extends StatelessWidget {
  const _NumberRow(this.items);
  final List<_Num> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (final n in items)
          Expanded(
            child: Builder(
              builder: (context) {
                final labelText = Text(
                  n.label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: colors.textTertiary,
                  ),
                );
                return Column(
                  children: [
                    labelText,
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (n.average)
                                  TextSpan(
                                    text: '⌀ ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                TextSpan(text: n.value),
                                if (n.unit != null)
                                  TextSpan(
                                    text: ' ${n.unit}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        // Always three columns: a shorter row lines up under the ones
        // above instead of spreading out.
        for (var i = items.length; i < 3; i++)
          const Expanded(child: SizedBox.shrink()),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
        ),
      ],
    ),
  );
}

class _RecordRow extends StatelessWidget {
  const _RecordRow(this.title, this.value, this.shot);
  final String title;
  final String value;
  final StatShot shot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detail = [
      _date(shot.time),
      if (shot.profile != null) shot.profile!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textTertiary),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 15, color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Part {
  const _Part(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

// One bar split into parts, legend dots below.
class _StackedBar extends StatelessWidget {
  const _StackedBar(this.parts);
  final List<_Part> parts;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: 10,
          // stretch: without it the parts get no height and only the
          // legend shows.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: math.max(1, parts[i].value),
                  child: ColoredBox(color: parts[i].color),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          for (final p in parts)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: p.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  p.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

// Name, bar relative to the first, count. The first bar in the accent.
class _BarList extends StatelessWidget {
  const _BarList(this.items);
  final List<StatCount> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final max = items.first.count;
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    items[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      children: [
                        Container(
                          height: 6,
                          color: colors.divider.withValues(alpha: 0.5),
                        ),
                        FractionallySizedBox(
                          widthFactor: items[i].count / max,
                          child: Container(
                            height: 6,
                            color: i == 0
                                ? colors.accent
                                : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${items[i].count}',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// --- Charts -----------------------------------------------------------------

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.start, required this.perDay});
  final DateTime start;
  final Map<DateTime, int> perDay;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 126,
    child: CustomPaint(
      size: Size.infinite,
      painter: _HeatmapPainter(start, perDay, context.colors, DateTime.now()),
    ),
  );
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter(this.start, this.perDay, this.colors, this.now);
  final DateTime start;
  final Map<DateTime, int> perDay;
  final AppColors colors;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    const weeks = Statistics.heatmapWeeks, labelW = 16.0, top = 16.0;
    final step = math.min(
      (size.width - labelW) / weeks,
      (size.height - top) / 7,
    );
    final cell = step * 0.8;
    final max = perDay.values.fold(0, math.max);
    final today = DateTime(now.year, now.month, now.day);
    final text = TextStyle(fontSize: 10, color: colors.textTertiary);
    for (final (i, d) in [(0, 'M'), (2, 'W'), (4, 'F'), (6, 'S')]) {
      _text(canvas, d, Offset(0, top + i * step + cell / 2 - 6), text);
    }
    int? lastMonth;
    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < 7; d++) {
        final day = DateTime(start.year, start.month, start.day + w * 7 + d);
        if (day.isAfter(today)) continue;
        if (d == 0 && day.month != lastMonth) {
          lastMonth = day.month;
          _text(
            canvas,
            _months[day.month - 1],
            Offset(labelW + w * step, 0),
            text,
          );
        }
        final n = perDay[day] ?? 0;
        final level = n == 0 || max == 0 ? 0.0 : 0.25 + 0.75 * (n / max);
        final paint = Paint()
          ..color = n == 0
              ? colors.divider.withValues(alpha: 0.6)
              : colors.accent.withValues(alpha: level);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(labelW + w * step, top + d * step, cell, cell),
            Radius.circular(cell * 0.25),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.perDay != perDay || old.colors != colors;
}

class _HourBars extends StatelessWidget {
  const _HourBars(this.perHour);
  final List<int> perHour;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 92,
    child: CustomPaint(
      size: Size.infinite,
      painter: _HourPainter(perHour, context.colors),
    ),
  );
}

class _HourPainter extends CustomPainter {
  _HourPainter(this.perHour, this.colors);
  final List<int> perHour;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    const base = 70.0;
    final max = perHour.fold(0, math.max);
    final bw = size.width / 24;
    for (var h = 0; h < 24; h++) {
      final v = perHour[h];
      final height = max == 0 ? 0.0 : math.max(1.5, v / max * 64);
      final strong = max > 0 && v >= max * 0.75;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(h * bw + 1.5, base - height, bw - 3, height),
          const Radius.circular(2),
        ),
        Paint()..color = strong ? colors.accent : colors.textTertiary,
      );
    }
    canvas.drawLine(
      const Offset(0, base + .5),
      Offset(size.width, base + .5),
      Paint()..color = colors.divider,
    );
    final text = TextStyle(fontSize: 10, color: colors.textTertiary);
    for (final h in [0, 6, 12, 18]) {
      _text(
        canvas,
        h.toString().padLeft(2, '0'),
        Offset(h * bw + 1, base + 6),
        text,
      );
    }
  }

  @override
  bool shouldRepaint(_HourPainter old) =>
      old.perHour != perHour || old.colors != colors;
}

class _WeekdayBars extends StatelessWidget {
  const _WeekdayBars(this.values, {required this.highlight});
  final List<int> values;
  final int highlight;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: CustomPaint(
      size: Size.infinite,
      painter: _WeekdayPainter(values, highlight, context.colors),
    ),
  );
}

class _WeekdayPainter extends CustomPainter {
  _WeekdayPainter(this.values, this.highlight, this.colors);
  final List<int> values;
  final int highlight;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final max = values.fold(1, math.max);
    final bw = size.width / 7;
    final text = TextStyle(fontSize: 10, color: colors.textTertiary);
    for (var i = 0; i < 7; i++) {
      final h = math.max(2.0, values[i] / max * 34);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * bw + 8, 40 - h, bw - 16, h),
          const Radius.circular(3),
        ),
        Paint()..color = i == highlight ? colors.accent : colors.textTertiary,
      );
      _text(canvas, 'MTWTFSS'[i], Offset(i * bw + bw / 2 - 3, 44), text);
    }
  }

  @override
  bool shouldRepaint(_WeekdayPainter old) =>
      old.values != values || old.colors != colors;
}

void _text(Canvas canvas, String s, Offset at, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at);
}
