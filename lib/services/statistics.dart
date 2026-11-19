// Numbers for Settings → Statistics.
//
// [StatisticsData.load] reads what is needed in three queries (shots,
// beans, and one aggregate over the readings); [Statistics.compute] then
// works on plain values only, so it is cheap to rerun when the period
// changes and easy to test.

import '../database/database.dart';

enum StatsPeriod {
  week('Week', 7, 'last 7 days'),
  month('Month', 30, 'last 30 days'),
  year('Year', 365, 'last 12 months'),
  all('All', null, 'all time');

  const StatsPeriod(this.label, this.days, this.description);
  final String label;
  final int? days;
  final String description;

  DateTime? start(DateTime now) =>
      days == null ? null : now.subtract(Duration(days: days!));
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

  bool get isPourOver => machine == 'pourover';
}

class StatBean {
  const StatBean({
    required this.id,
    required this.name,
    this.roaster,
    this.country,
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

  static Future<StatisticsData> load(AppDatabase db) async {
    // Per shot: highest pressure, water pumped (flow × time between two
    // readings; gaps over 2 s are skipped) and piston travel.
    final aggregates = await db
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
        WINDOW w AS (PARTITION BY shot_id ORDER BY time_ms)
      )
      GROUP BY shot_id
    ''',
          readsFrom: {db.shotReadings},
        )
        .get();
    final agg = {
      for (final r in aggregates)
        r.read<int>('shot_id'): (
          maxP: r.readNullable<double>('max_p'),
          volume: r.readNullable<double>('volume'),
          travel: r.readNullable<double>('travel'),
        ),
    };

    final shotRows = await (db.select(
      db.shots,
    )..where((s) => s.deletedAt.isNull())).get();
    final beanRows = await db.allBeans();

    return StatisticsData(
      [
        for (final s in shotRows)
          StatShot(
            time: s.timestamp,
            machine: s.machine,
            beanId: s.beanId,
            profile: s.profileName,
            dose: s.doseGrams,
            finalWeight: s.finalWeight,
            beverage: s.beverageGrams,
            durationMs: s.durationMs,
            maxPressure: agg[s.id]?.maxP,
            flowVolumeMl: s.machine == 'pourover' ? null : agg[s.id]?.volume,
            pistonTravelMm: s.machine == 'meticulous'
                ? agg[s.id]?.travel
                : null,
          ),
      ],
      {
        for (final b in beanRows)
          b.id: StatBean(
            id: b.id,
            name: b.name,
            roaster: b.roaster,
            country: b.country,
            processing: b.processing,
            cost: b.cost,
            weightGrams: b.weightGrams,
            openedAt: b.openedAt,
            emptiedAt: b.emptiedAt,
            createdAt: b.createdAt,
          ),
      },
    );
  }
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
    required this.earliestMinute,
    required this.latestMinute,
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
  final int? earliestMinute;
  final int? latestMinute;

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
    int? earliest, latest;
    for (final s in shots) {
      perHour[s.time.hour]++;
      final m = s.time.hour * 60 + s.time.minute;
      if (earliest == null || m < earliest) earliest = m;
      if (latest == null || m > latest) latest = m;
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
      earliestMinute: earliest,
      latestMinute: latest,
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
