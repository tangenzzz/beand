// Numbers for Settings → Statistics.
//
// [StatisticsData.load] reads only the columns it needs from shots and
// beans, plus an aggregate over the readings that is cached per shot;
// [Statistics.compute] then
// works on plain values only, so it is cheap to rerun when the period
// changes and easy to test.

import 'package:drift/drift.dart';

import '../database/database.dart';

enum StatsPeriod {
  // Longest first, as shown in the selector.
  all('All', null, 'all time'),
  year('Year', 365, 'last 12 months'),
  month('Month', 30, 'last 30 days'),
  week('Week', 7, 'last 7 days'),
  day('Day', 1, 'today');

  const StatsPeriod(this.label, this.days, this.description);
  final String label;
  final int? days;
  final String description;

  /// "Day" is the calendar day (since midnight), the others count back
  /// from now.
  DateTime? start(DateTime now) => switch (this) {
    all => null,
    day => DateTime(now.year, now.month, now.day),
    _ => now.subtract(Duration(days: days!)),
  };
}

/// One shot or brew, reduced to what the statistics use.
class StatShot {
  const StatShot({
    required this.time,
    required this.machine,
    this.beanId,
    this.profile,
    this.dose,
    this.finalWeight,
    this.beverage,
    this.durationMs,
    this.maxPressure,
    this.flowVolumeMl,
    this.pistonTravelMm,
    this.rating,
    this.grinder,
    this.burrs,
    this.grind,
    this.brewedWith,
    this.gearIds,
    this.chainId,
  });

  final DateTime time;
  final String machine;
  final int? beanId;
  final String? profile;
  final double? dose;

  /// Espresso: yield in the cup. Pour over: water poured.
  final double? finalWeight;

  /// Pour over: what ended up in the cup.
  final double? beverage;
  final int? durationMs;
  final double? maxPressure;

  /// Water pumped through the puck, from the flow readings.
  final double? flowVolumeMl;

  /// Total way the Meticulous piston moved, forth and back.
  final double? pistonTravelMm;

  /// Stars 1–5; null or 0 = not rated.
  final int? rating;

  /// Grinder name and fitted burrs at brew time (text, as on the shot).
  final String? grinder;
  final String? burrs;

  /// Grind setting as stored ("3.25").
  final String? grind;

  /// The chain's gear labels at brew time, one per line.
  final String? brewedWith;

  /// Desk gear IDs, comma-separated; null on shots before schema 29.
  final String? gearIds;
  final String? chainId;

  bool get isPourOver => machine == 'pourover';
}

class StatBean {
  const StatBean({
    required this.id,
    required this.name,
    this.roaster,
    this.country,
    this.region,
    this.variety,
    this.processing,
    this.cost,
    this.weightGrams,
    this.openedAt,
    this.emptiedAt,
    this.createdAt,
  });

  final int id;
  final String name;
  final String? roaster;
  final String? country;
  final String? region;
  final String? variety;
  final String? processing;
  final double? cost;
  final double? weightGrams;
  final DateTime? openedAt;
  final DateTime? emptiedAt;

  /// When the bag was added to the app — the closest thing to a purchase
  /// date the app has.
  final DateTime? createdAt;

  /// Price per gram, when both price and bag weight are known.
  double? get costPerGram =>
      (cost != null && weightGrams != null && weightGrams! > 0)
      ? cost! / weightGrams!
      : null;
}

class StatisticsData {
  const StatisticsData(this.shots, this.beans);

  final List<StatShot> shots;
  final Map<int, StatBean> beans;

  /// Per database: readings aggregates by shot id. Readings do not change
  /// once a shot is saved, so a reload only aggregates shots that are new
  /// (or whose readings changed, spotted by count and last row id).
  static final _aggCache = Expando<Map<int, _ShotAgg>>();

  static Future<StatisticsData> load(AppDatabase db) async {
    final agg = await _readingsAggregates(db);

    final s = db.shots;
    final shotRows =
        await (db.selectOnly(s)
              ..addColumns([
                s.id,
                s.timestamp,
                s.machine,
                s.beanId,
                s.profileName,
                s.doseGrams,
                s.finalWeight,
                s.beverageGrams,
                s.durationMs,
                s.rating,
                s.grinder,
                s.burrs,
                s.grindSize,
                s.brewedWith,
                s.gearIds,
                s.brewChainId,
              ])
              ..where(s.deletedAt.isNull()))
            .get();
    final b = db.beans;
    final beanRows =
        await (db.selectOnly(b)
              ..addColumns([
                b.id,
                b.name,
                b.roaster,
                b.country,
                b.region,
                b.variety,
                b.processing,
                b.cost,
                b.weightGrams,
                b.openedAt,
                b.emptiedAt,
                b.createdAt,
              ])
              ..where(b.deleted.equals(false)))
            .get();

    return StatisticsData(
      [
        for (final r in shotRows)
          () {
            final id = r.read(s.id)!;
            final machine = r.read(s.machine)!;
            final a = agg[id];
            return StatShot(
              time: r.read(s.timestamp)!,
              machine: machine,
              beanId: r.read(s.beanId),
              profile: r.read(s.profileName),
              dose: r.read(s.doseGrams),
              finalWeight: r.read(s.finalWeight),
              beverage: r.read(s.beverageGrams),
              durationMs: r.read(s.durationMs),
              maxPressure: a?.maxP,
              flowVolumeMl: machine == 'pourover' ? null : a?.volume,
              rating: r.read(s.rating),
              grinder: r.read(s.grinder),
              burrs: r.read(s.burrs),
              grind: r.read(s.grindSize),
              brewedWith: r.read(s.brewedWith),
              gearIds: r.read(s.gearIds),
              chainId: r.read(s.brewChainId),
              pistonTravelMm: machine == 'meticulous' ? a?.travel : null,
            );
          }(),
      ],
      {
        for (final r in beanRows)
          r.read(b.id)!: StatBean(
            id: r.read(b.id)!,
            name: r.read(b.name)!,
            roaster: r.read(b.roaster),
            country: r.read(b.country),
            region: r.read(b.region),
            variety: r.read(b.variety),
            processing: r.read(b.processing),
            cost: r.read(b.cost),
            weightGrams: r.read(b.weightGrams),
            openedAt: r.read(b.openedAt),
            emptiedAt: r.read(b.emptiedAt),
            createdAt: r.read(b.createdAt)!,
          ),
      },
    );
  }

  /// Highest pressure, water pumped (flow × time between two readings;
  /// gaps over 2 s are skipped) and piston travel per shot — cached, only
  /// shots with new or changed readings are aggregated again.
  static Future<Map<int, _ShotAgg>> _readingsAggregates(AppDatabase db) async {
    final cache = _aggCache[db] ??= {};
    // Cheap fingerprint per shot, answered from the shot_id index.
    final marks = await db
        .customSelect(
          'SELECT shot_id, COUNT(*) AS n, MAX(id) AS last_id '
          'FROM shot_readings GROUP BY shot_id',
          readsFrom: {db.shotReadings},
        )
        .get();
    final seen = <int>{};
    final stale = <int, ({int n, int lastId})>{};
    for (final r in marks) {
      final id = r.read<int>('shot_id');
      final mark = (n: r.read<int>('n'), lastId: r.read<int>('last_id'));
      seen.add(id);
      final hit = cache[id];
      if (hit == null || hit.n != mark.n || hit.lastId != mark.lastId) {
        stale[id] = mark;
      }
    }
    cache.removeWhere((id, _) => !seen.contains(id));

    final ids = stale.keys.toList();
    const chunk = 500;
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, (i + chunk).clamp(0, ids.length));
      final rows = await db
          .customSelect(
            '''
      SELECT shot_id,
             MAX(pressure) AS max_p,
             SUM(CASE WHEN flow > 0 AND dt > 0 AND dt <= 2000
                      THEN flow * dt / 1000.0 END) AS volume,
             SUM(ABS(dm)) AS travel
      FROM (
        SELECT shot_id, pressure, flow,
               time_ms - LAG(time_ms) OVER w AS dt,
               motor_position - LAG(motor_position) OVER w AS dm
        FROM shot_readings
        WHERE shot_id IN (${List.filled(part.length, '?').join(',')})
        WINDOW w AS (PARTITION BY shot_id ORDER BY time_ms)
      )
      GROUP BY shot_id
    ''',
            variables: [for (final id in part) Variable.withInt(id)],
            readsFrom: {db.shotReadings},
          )
          .get();
      for (final r in rows) {
        final id = r.read<int>('shot_id');
        final mark = stale[id]!;
        cache[id] = _ShotAgg(
          n: mark.n,
          lastId: mark.lastId,
          maxP: r.readNullable<double>('max_p'),
          volume: r.readNullable<double>('volume'),
          travel: r.readNullable<double>('travel'),
        );
      }
    }
    return cache;
  }
}

class _ShotAgg {
  const _ShotAgg({
    required this.n,
    required this.lastId,
    this.maxP,
    this.volume,
    this.travel,
  });
  final int n;
  final int lastId;
  final double? maxP;
  final double? volume;
  final double? travel;
}

class StatRecord {
  const StatRecord(this.value, this.shot);
  final double value;
  final StatShot shot;
}

class StatCount {
  const StatCount(this.label, this.count);
  final String label;
  final int count;
}

class Statistics {
  Statistics._({
    required this.period,
    required this.shotCount,
    required this.brewCount,
    required this.emptyBags,
    required this.groundGrams,
    required this.inCupGrams,
    required this.throughMl,
    required this.underPressureMs,
    required this.valueBrewed,
    required this.bagsBought,
    required this.bagsBoughtCount,
    required this.bagsWithoutPrice,
    required this.pricedShots,
    required this.dosedShots,
    required this.unpricedBeans,
    required this.byMachine,
    required this.fastest,
    required this.slowest,
    required this.highestPressure,
    required this.biggestYield,
    required this.pistonTravelMm,
    required this.perDay,
    required this.heatmapStart,
    required this.perHour,
    required this.earliestCoffee,
    required this.latestCoffee,
    required this.changesPerWeekday,
    required this.profileChangesOnLabDay,
    required this.beanChangesOnLabDay,
    required this.topRoasters,
    required this.countries,
    required this.processing,
    required this.bagDaysAvg,
    required this.gramsPerDay,
    required this.fastestBag,
    required this.fastestBagDays,
    required this.profilesByMachine,
  });

  final StatsPeriod period;

  // Overview
  final int shotCount;
  final int brewCount;
  final int emptyBags;
  final double groundGrams;
  final double inCupGrams;
  final double throughMl;
  final int underPressureMs;

  /// Null when no shot of the period has a bean with price and weight.
  final double? valueBrewed;

  /// Sum of the prices of the bags added in the period; null when none of
  /// them has a price.
  final double? bagsBought;

  /// Bags added in the period, with or without a price.
  final int bagsBoughtCount;

  /// Of those, how many have no price and are missing from [bagsBought].
  final int bagsWithoutPrice;

  /// Shots and brews of the period that went into [valueBrewed]: with a dose
  /// and a bean that has price and bag weight.
  final int pricedShots;

  /// Shots and brews of the period with a dose at all.
  final int dosedShots;

  /// Beans used in the period that lack price or bag weight, most used
  /// first — why [valueBrewed] may be lower than expected.
  final List<String> unpricedBeans;
  final List<StatCount> byMachine;

  // Records (espresso only)
  final StatRecord? fastest;
  final StatRecord? slowest;
  final StatRecord? highestPressure;
  final StatRecord? biggestYield;

  final double pistonTravelMm;

  /// Shots per calendar day of the last 17 weeks (independent of the
  /// period), key = midnight of the day.
  final Map<DateTime, int> perDay;

  /// Monday of the first heatmap column.
  final DateTime heatmapStart;

  /// Shots per hour of the day, index 0–23.
  final List<int> perHour;

  /// Shots and brews with the earliest and latest time of day; the value
  /// is minutes since midnight.
  final StatRecord? earliestCoffee;
  final StatRecord? latestCoffee;

  /// Profile or bean changes between two consecutive shots, per weekday
  /// (index 0 = Monday).
  final List<int> changesPerWeekday;
  final int profileChangesOnLabDay;
  final int beanChangesOnLabDay;

  // Beans
  final List<StatCount> topRoasters;
  final List<StatCount> countries;
  final List<StatCount> processing;
  final double? bagDaysAvg;
  final double? gramsPerDay;
  final String? fastestBag;
  final int? fastestBagDays;

  // Profiles: machine key → most used profiles.
  final Map<String, List<StatCount>> profilesByMachine;

  int get drinks => shotCount + brewCount;

  /// Weekday (0 = Monday) with the most changes, or null without any.
  int? get labDay {
    var best = -1, at = -1;
    for (var i = 0; i < 7; i++) {
      if (changesPerWeekday[i] > best) {
        best = changesPerWeekday[i];
        at = i;
      }
    }
    return best > 0 ? at : null;
  }

  /// The two neighbouring hours with the most shots, as the first hour.
  int? get busiestHour {
    var best = 0, at = -1;
    for (var h = 0; h < 24; h++) {
      final n = perHour[h] + perHour[(h + 1) % 24];
      if (n > best) {
        best = n;
        at = h;
      }
    }
    return at < 0 ? null : at;
  }

  static const heatmapWeeks = 17;

  static Statistics compute(
    StatisticsData data,
    StatsPeriod period, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final from = period.start(today);
    bool inPeriod(DateTime t) => from == null || !t.isBefore(from);

    final shots = [
      for (final s in data.shots)
        if (inPeriod(s.time) && !s.time.isAfter(today)) s,
    ]..sort((a, b) => a.time.compareTo(b.time));
    final espresso = [
      for (final s in shots)
        if (!s.isPourOver) s,
    ];

    // --- Overview ---------------------------------------------------------
    var ground = 0.0, cup = 0.0, through = 0.0, pressureMs = 0;
    double? cost;
    var priced = 0, dosed = 0;
    final unpriced = <String, int>{};
    for (final s in shots) {
      ground += s.dose ?? 0;
      if (s.isPourOver) {
        cup += s.beverage ?? 0;
        through += s.finalWeight ?? 0;
      } else {
        cup += s.finalWeight ?? 0;
        through += s.flowVolumeMl ?? 0;
        pressureMs += s.durationMs ?? 0;
      }
      if (s.dose == null) continue;
      dosed++;
      final bean = data.beans[s.beanId];
      final perGram = bean?.costPerGram;
      if (perGram != null) {
        cost = (cost ?? 0) + perGram * s.dose!;
        priced++;
      } else if (bean != null) {
        unpriced[bean.name] = (unpriced[bean.name] ?? 0) + 1;
      }
    }
    double? bought;
    var boughtCount = 0, boughtNoPrice = 0;
    for (final b in data.beans.values) {
      if (b.createdAt == null || !inPeriod(b.createdAt!)) continue;
      boughtCount++;
      if (b.cost == null) {
        boughtNoPrice++;
      } else {
        bought = (bought ?? 0) + b.cost!;
      }
    }
    final emptied = [
      for (final b in data.beans.values)
        if (b.emptiedAt != null && inPeriod(b.emptiedAt!)) b,
    ];

    final machineCounts = <String, int>{};
    for (final s in shots) {
      machineCounts[s.machine] = (machineCounts[s.machine] ?? 0) + 1;
    }

    // --- Records ----------------------------------------------------------
    // Shots under 10 s are aborted or test shots, not records.
    final timed = [
      for (final s in espresso)
        if ((s.durationMs ?? 0) >= 10000) s,
    ];
    StatRecord? best(
      Iterable<StatShot> list,
      double? Function(StatShot) value, {
      bool lowest = false,
    }) {
      StatRecord? r;
      for (final s in list) {
        final v = value(s);
        if (v == null) continue;
        if (r == null || (lowest ? v < r.value : v > r.value)) {
          r = StatRecord(v, s);
        }
      }
      return r;
    }

    // --- Activity -----------------------------------------------------------
    final day0 = DateTime(today.year, today.month, today.day);
    // From the Monday [heatmapWeeks] - 1 weeks back. Built by calendar
    // fields, not Durations, so a daylight-saving switch can't shift a day.
    final heatStart = DateTime(
      day0.year,
      day0.month,
      day0.day - (heatmapWeeks - 1) * 7 - (day0.weekday - 1),
    );
    final perDay = <DateTime, int>{};
    for (final s in data.shots) {
      final d = DateTime(s.time.year, s.time.month, s.time.day);
      if (d.isBefore(heatStart) || d.isAfter(day0)) continue;
      perDay[d] = (perDay[d] ?? 0) + 1;
    }
    final perHour = List.filled(24, 0);
    StatRecord? earliest, latest;
    for (final s in shots) {
      perHour[s.time.hour]++;
      final m = (s.time.hour * 60 + s.time.minute).toDouble();
      if (earliest == null || m < earliest.value) earliest = StatRecord(m, s);
      if (latest == null || m > latest.value) latest = StatRecord(m, s);
    }
    final changes = List.filled(7, 0);
    final profileChanges = List.filled(7, 0);
    final beanChanges = List.filled(7, 0);
    for (var i = 1; i < shots.length; i++) {
      final a = shots[i - 1], b = shots[i];
      final wd = b.time.weekday - 1;
      final p =
          a.profile != null && b.profile != null && a.profile != b.profile;
      final n = a.beanId != null && b.beanId != null && a.beanId != b.beanId;
      if (p) profileChanges[wd]++;
      if (n) beanChanges[wd]++;
      if (p || n) changes[wd]++;
    }

    // --- Beans --------------------------------------------------------------
    List<StatCount> countBy(String? Function(StatBean) field, {int? top}) {
      final counts = <String, int>{};
      final names = <String, String>{};
      for (final s in shots) {
        final raw = field(data.beans[s.beanId] ?? _noBean)?.trim();
        if (raw == null || raw.isEmpty) continue;
        final key = raw.toLowerCase();
        names.putIfAbsent(key, () => raw);
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final list = [
        for (final e in counts.entries) StatCount(names[e.key]!, e.value),
      ]..sort((a, b) => b.count.compareTo(a.count));
      return top == null ? list : list.take(top).toList();
    }

    final bagDays = <(StatBean, int)>[
      for (final b in emptied)
        if (b.openedAt != null)
          (b, b.emptiedAt!.difference(b.openedAt!).inDays.clamp(1, 9999)),
    ];
    // Days the period really covers: it can't start before the very first
    // shot, or a year with two months of data would be divided by 365.
    DateTime? firstEver;
    for (final s in data.shots) {
      if (firstEver == null || s.time.isBefore(firstEver)) firstEver = s.time;
    }
    final spanStart = firstEver == null
        ? null
        : (from != null && from.isAfter(firstEver) ? from : firstEver);
    final spanDays = spanStart == null
        ? 0
        : today.difference(spanStart).inDays + 1;
    (StatBean, int)? quickest;
    for (final e in bagDays) {
      if (quickest == null || e.$2 < quickest.$2) quickest = e;
    }

    // --- Profiles -------------------------------------------------------
    final byMachine = <String, Map<String, int>>{};
    for (final s in shots) {
      final p = s.profile?.trim();
      if (p == null || p.isEmpty) continue;
      final m = byMachine.putIfAbsent(s.machine, () => {});
      m[p] = (m[p] ?? 0) + 1;
    }

    final labDay = () {
      var best = 0, at = -1;
      for (var i = 0; i < 7; i++) {
        if (changes[i] > best) {
          best = changes[i];
          at = i;
        }
      }
      return at;
    }();

    return Statistics._(
      period: period,
      shotCount: espresso.length,
      brewCount: shots.length - espresso.length,
      emptyBags: emptied.length,
      groundGrams: ground,
      inCupGrams: cup,
      throughMl: through,
      underPressureMs: pressureMs,
      valueBrewed: cost,
      bagsBought: bought,
      bagsBoughtCount: boughtCount,
      bagsWithoutPrice: boughtNoPrice,
      pricedShots: priced,
      dosedShots: dosed,
      unpricedBeans:
          (unpriced.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .map((e) => e.key)
              .toList(),
      byMachine: [
        for (final e in machineCounts.entries) StatCount(e.key, e.value),
      ]..sort((a, b) => b.count.compareTo(a.count)),
      fastest: best(timed, (s) => s.durationMs!.toDouble(), lowest: true),
      slowest: best(timed, (s) => s.durationMs!.toDouble()),
      highestPressure: best(espresso, (s) => s.maxPressure),
      biggestYield: best(espresso, (s) => s.finalWeight),
      pistonTravelMm: shots.fold(0.0, (t, s) => t + (s.pistonTravelMm ?? 0)),
      perDay: perDay,
      heatmapStart: heatStart,
      perHour: perHour,
      earliestCoffee: earliest,
      latestCoffee: latest,
      changesPerWeekday: changes,
      profileChangesOnLabDay: labDay < 0 ? 0 : profileChanges[labDay],
      beanChangesOnLabDay: labDay < 0 ? 0 : beanChanges[labDay],
      topRoasters: countBy((b) => b.roaster, top: 5),
      countries: countBy((b) => b.country),
      processing: countBy((b) => b.processing),
      bagDaysAvg: bagDays.isEmpty
          ? null
          : bagDays.fold(0, (t, e) => t + e.$2) / bagDays.length,
      gramsPerDay: spanDays > 0 && ground > 0 ? ground / spanDays : null,
      fastestBag: quickest?.$1.name,
      fastestBagDays: quickest?.$2,
      profilesByMachine: {
        for (final e in byMachine.entries)
          e.key: ([
            for (final p in e.value.entries) StatCount(p.key, p.value),
          ]..sort((a, b) => b.count.compareTo(a.count))).take(5).toList(),
      },
    );
  }
}

const _noBean = StatBean(id: -1, name: '');
