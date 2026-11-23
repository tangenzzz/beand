import 'package:beand/database/database.dart';
import 'package:beand/services/statistics.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Thursday noon.
  final now = DateTime(2026, 11, 19, 12);

  StatShot shot(
    int daysAgo, {
    int hour = 8,
    int minute = 0,
    String machine = 'meticulous',
    int? beanId = 1,
    String? profile = 'Classic',
    double? dose = 18,
    double? yieldG = 36,
    double? beverage,
    int? durationMs = 30000,
    double? maxPressure = 9,
    double? flowVolumeMl = 50,
    double? pistonTravelMm,
  }) => StatShot(
    time: DateTime(now.year, now.month, now.day - daysAgo, hour, minute),
    machine: machine,
    beanId: beanId,
    profile: profile,
    dose: dose,
    finalWeight: yieldG,
    beverage: beverage,
    durationMs: durationMs,
    maxPressure: maxPressure,
    flowVolumeMl: flowVolumeMl,
    pistonTravelMm: pistonTravelMm,
  );

  final beans = {
    1: StatBean(
      id: 1,
      name: 'Kiambu AA',
      roaster: 'Square Mile',
      country: 'Kenya',
      processing: 'Washed',
      cost: 20,
      weightGrams: 250,
      openedAt: DateTime(2026, 11, 1),
      emptiedAt: DateTime(2026, 11, 12),
      createdAt: DateTime(2026, 10, 30),
    ),
    2: StatBean(
      id: 2,
      name: 'Guji',
      roaster: 'square mile ',
      country: 'Ethiopia',
      processing: 'Natural',
      openedAt: DateTime(2026, 10, 1),
      emptiedAt: DateTime(2026, 10, 5),
      createdAt: DateTime(2026, 9, 28),
    ),
  };

  group('overview', () {
    test('sums shots and brews of the period only', () {
      final data = StatisticsData([
        shot(1),
        shot(2, beanId: 2, profile: 'Turbo'),
        shot(
          3,
          machine: 'pourover',
          dose: 15,
          yieldG: 250,
          beverage: 220,
          maxPressure: null,
          flowVolumeMl: null,
        ),
        shot(40), // outside the month
      ], beans);
      final s = Statistics.compute(data, StatsPeriod.month, now: now);

      expect(s.shotCount, 2);
      expect(s.brewCount, 1);
      expect(s.drinks, 3);
      expect(s.groundGrams, 18 + 18 + 15);
      // Espresso yield + pour over beverage; water: pumped + poured.
      expect(s.inCupGrams, 36 + 36 + 220);
      expect(s.throughMl, 50 + 50 + 250);
      // Pour over brews are not "under pressure".
      expect(s.underPressureMs, 60000);
      // Only bean 1 has price and weight (espresso 18 g + pour over 15 g)
      // × 20 € / 250 g.
      expect(s.valueBrewed, closeTo(2.64, 1e-9));
      // Bean 1 emptied 7 days ago; bean 2 long before the month.
      expect(s.emptyBags, 1);
    });

    test('cost coverage names the beans without a price', () {
      final data = StatisticsData([
        shot(1),
        shot(2, beanId: 2),
        shot(3, beanId: 2),
        shot(4, beanId: null),
        shot(5, dose: null),
      ], beans);
      final s = Statistics.compute(data, StatsPeriod.week, now: now);
      expect(s.dosedShots, 4);
      expect(s.pricedShots, 1);
      expect(s.unpricedBeans, ['Guji']);
    });

    test('bags bought: prices of the bags added in the period', () {
      final data = StatisticsData([shot(1)], beans);
      final month = Statistics.compute(data, StatsPeriod.month, now: now);
      // Only bean 1 was added within 30 days; it costs 20.
      expect(month.bagsBought, 20);
      expect(month.bagsBoughtCount, 1);
      final all = Statistics.compute(data, StatsPeriod.all, now: now);
      // Bean 2 has no price: counted, but missing from the sum.
      expect(all.bagsBought, 20);
      expect(all.bagsBoughtCount, 2);
      expect(all.bagsWithoutPrice, 1);
    });

    test('no bean prices → no cost instead of 0', () {
      final data = StatisticsData([shot(1, beanId: 2)], beans);
      expect(
        Statistics.compute(data, StatsPeriod.all, now: now).valueBrewed,
        isNull,
      );
    });

    test('machines counted and sorted', () {
      final data = StatisticsData([
        shot(1),
        shot(2),
        shot(3, machine: 'pourover'),
      ], beans);
      final s = Statistics.compute(data, StatsPeriod.week, now: now);
      expect(s.byMachine.map((c) => '${c.label}:${c.count}'), [
        'meticulous:2',
        'pourover:1',
      ]);
    });
  });

  test('day = since midnight, periods listed longest first', () {
    final data = StatisticsData([
      shot(0, hour: 7),
      shot(1, hour: 20), // yesterday evening, within 24 h but not today
    ], beans);
    expect(Statistics.compute(data, StatsPeriod.day, now: now).shotCount, 1);
    expect(StatsPeriod.values.first, StatsPeriod.all);
    expect(StatsPeriod.values.last, StatsPeriod.day);
  });

  group('records', () {
    test('espresso only, short test shots ignored', () {
      final data = StatisticsData([
        shot(1, durationMs: 24000, yieldG: 40, maxPressure: 9.5),
        shot(2, durationMs: 41000, yieldG: 45),
        shot(3, durationMs: 4000), // aborted
        shot(4, machine: 'pourover', durationMs: 200000, yieldG: 300),
      ], beans);
      final s = Statistics.compute(data, StatsPeriod.all, now: now);
      expect(s.fastest!.value, 24000);
      expect(s.slowest!.value, 41000);
      expect(s.highestPressure!.value, 9.5);
      expect(s.biggestYield!.value, 45);
    });

    test('piston travel adds up', () {
      final data = StatisticsData([
        shot(1, pistonTravelMm: 62),
        shot(2, pistonTravelMm: 60),
      ], beans);
      expect(
        Statistics.compute(data, StatsPeriod.all, now: now).pistonTravelMm,
        122,
      );
    });
  });

  group('activity', () {
    test('heatmap starts on a Monday and counts per day', () {
      final data = StatisticsData([shot(0), shot(0, hour: 14), shot(1)], beans);
      final s = Statistics.compute(data, StatsPeriod.week, now: now);
      expect(s.heatmapStart.weekday, DateTime.monday);
      expect(s.perDay[DateTime(2026, 11, 19)], 2);
      expect(s.perDay[DateTime(2026, 11, 18)], 1);
    });

    test('hours, earliest and latest', () {
      final data = StatisticsData([
        shot(1, hour: 5, minute: 42),
        shot(1, hour: 7),
        shot(2, hour: 8),
        shot(3, hour: 23, minute: 8),
      ], beans);
      final s = Statistics.compute(data, StatsPeriod.week, now: now);
      expect(s.earliestCoffee!.value, 5 * 60 + 42);
      expect(s.latestCoffee!.value, 23 * 60 + 8);
      expect(s.latestCoffee!.shot.time.day, now.day - 3);
      expect(s.perHour[7], 1);
      expect(s.busiestHour, 7);
    });

    test('lab day = weekday with most profile or bean changes', () {
      // Sunday 15 Nov: three shots with changes; Tuesday 17: one change.
      final data = StatisticsData([
        shot(4, hour: 8, profile: 'A'),
        shot(4, hour: 9, profile: 'B'),
        shot(4, hour: 10, profile: 'B', beanId: 2),
        shot(2, hour: 8, profile: 'C'),
      ], beans);
      final s = Statistics.compute(data, StatsPeriod.week, now: now);
      expect(s.labDay, DateTime.sunday - 1);
      expect(s.profileChangesOnLabDay, 1);
      expect(s.beanChangesOnLabDay, 1);
    });
  });

  group('beans and profiles', () {
    test('roasters grouped regardless of case and spaces', () {
      final data = StatisticsData([shot(1), shot(2, beanId: 2)], beans);
      final s = Statistics.compute(data, StatsPeriod.all, now: now);
      expect(s.topRoasters.single.count, 2);
      expect(
        s.countries.map((c) => c.label),
        containsAll(['Kenya', 'Ethiopia']),
      );
    });

    test('bags: average days and the quickest one', () {
      final data = StatisticsData([shot(1)], beans);
      final s = Statistics.compute(data, StatsPeriod.all, now: now);
      expect(s.bagDaysAvg, (11 + 4) / 2);
      expect(s.fastestBag, 'Guji');
      expect(s.fastestBagDays, 4);
    });

    test('grams per day only count the days since the first shot', () {
      // 10 days of data, 18 g each: a year must not divide by 365.
      final data = StatisticsData([
        for (var d = 0; d < 10; d++) shot(d),
      ], beans);
      final year = Statistics.compute(data, StatsPeriod.year, now: now);
      final all = Statistics.compute(data, StatsPeriod.all, now: now);
      expect(year.gramsPerDay, closeTo(180 / 10, 0.01));
      expect(all.gramsPerDay, year.gramsPerDay);
    });

    test('top profiles per machine', () {
      final data = StatisticsData([
        shot(1, profile: 'A'),
        shot(2, profile: 'A'),
        shot(3, profile: 'B'),
        shot(4, machine: 'pourover', profile: '4:6'),
      ], beans);
      final s = Statistics.compute(data, StatsPeriod.all, now: now);
      expect(s.profilesByMachine['meticulous']!.first.label, 'A');
      expect(s.profilesByMachine['pourover']!.single.label, '4:6');
    });
  });

  test('load reads readings aggregates from the database', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertShotWithReadings(
      ShotsCompanion.insert(
        timestamp: now,
        machine: const Value('meticulous'),
        durationMs: const Value(30000),
      ),
      [
        for (var i = 0; i < 4; i++)
          (id) => ShotReadingsCompanion.insert(
            shotId: id,
            timeMs: i * 500,
            pressure: Value(6.0 + i),
            flow: const Value(2.0),
            motorPosition: Value(10.0 + i * 5),
          ),
      ],
    );
    final data = await StatisticsData.load(db);
    final s = data.shots.single;
    expect(s.maxPressure, 9);
    // Three steps of 0.5 s at 2 ml/s.
    expect(s.flowVolumeMl, closeTo(3, 1e-9));
    expect(s.pistonTravelMm, 15);
  });

  test('load only aggregates shots with new readings, cached per db', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    Future<int> shot(double pressure) => db.insertShotWithReadings(
      ShotsCompanion.insert(timestamp: now, machine: const Value('meticulous')),
      [
        for (var i = 0; i < 3; i++)
          (id) => ShotReadingsCompanion.insert(
            shotId: id,
            timeMs: i * 500,
            pressure: Value(pressure + i),
          ),
      ],
    );
    final first = await shot(5);
    var data = await StatisticsData.load(db);
    expect(data.shots.single.maxPressure, 7);

    final second = await shot(8);
    data = await StatisticsData.load(db);
    final byPressure = [for (final s in data.shots) s.maxPressure]..sort();
    expect(byPressure, [7, 10]);

    // More readings for an existing shot are picked up, too.
    await db
        .into(db.shotReadings)
        .insert(
          ShotReadingsCompanion.insert(
            shotId: first,
            timeMs: 2000,
            pressure: const Value(12),
          ),
        );
    data = await StatisticsData.load(db);
    expect([for (final s in data.shots) s.maxPressure]..sort(), [10, 12]);

    // A fresh database starts with its own cache.
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    expect((await StatisticsData.load(other)).shots, isEmpty);
    expect(second, isNot(first));
  });
}
