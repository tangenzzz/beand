import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_filter.dart';
import 'package:beand/screens/beans/bean_suggestions.dart';
import 'package:beand/screens/beans/bean_widgets.dart';
import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_test/flutter_test.dart';

Bean bean(
  int id,
  String name, {
  String? roaster,
  String? country,
  String? taste,
  DateTime? roastDate,
  bool frozen = false,
  DateTime? thawedDate,
}) => Bean(
  syncId: 'test',
  updatedAt: 0,
  syncState: SyncState.pending,
  deleted: false,
  id: id,
  name: name,
  roaster: roaster,
  roastDate: roastDate,
  isBlend: false,
  country: country,
  taste: taste,
  isFrozen: frozen,
  thawedDate: thawedDate,
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  test('freshness: thaw date replaces the roast date as ring start', () {
    final now = DateTime(2026, 9, 20);
    final roasted = DateTime(2026, 7, 1);
    expect(daysSinceFreshnessStart(bean(1, 'A', roastDate: roasted), now), 81);
    expect(
      daysSinceFreshnessStart(
        bean(1, 'A', roastDate: roasted, thawedDate: DateTime(2026, 9, 17)),
        now,
      ),
      3,
    );
    expect(daysSinceFreshnessStart(bean(1, 'A'), now), isNull);
    // Roast filter ("Roasted within") stays on the roast date.
    expect(
      daysSinceRoast(
        bean(1, 'A', roastDate: roasted, thawedDate: DateTime(2026, 9, 17)),
        now,
      ),
      81,
    );
  });

  test('grouping: roasters A–Z (case-insensitive), beans A–Z, no roaster at the end', () {
    final groups = groupBeansByRoaster([
      bean(1, 'Perfecto', roaster: 'Coffee Collective'),
      bean(2, 'Kenya', roaster: 'bonanza'),
      bean(3, 'Ethiopia', roaster: 'Bonanza'),
      bean(4, 'Mystery'),
      bean(5, 'Colombia', roaster: '  '),
    ]);
    expect(groups.map((g) => g.roaster), [
      'bonanza',
      'Coffee Collective',
      null,
    ]);
    expect(groups[0].beans.map((b) => b.name), ['Ethiopia', 'Kenya']);
    expect(groups[2].beans.map((b) => b.name), ['Colombia', 'Mystery']);
  });

  test(
    'suggestions: frequency, then A–Z; taste word by word; spellings merged',
    () {
      final s = BeanSuggestions.fromBeans([
        bean(1, 'A', country: 'Kenya', taste: 'blackcurrant, grapefruit'),
        bean(2, 'B', country: 'kenya', taste: 'Grapefruit, jasmine'),
        bean(3, 'C', country: 'Ethiopia', taste: ' , jasmine'),
      ]);
      expect(s.countries, ['Kenya', 'Ethiopia']);
      expect(s.tastes, ['grapefruit', 'jasmine', 'blackcurrant']);
    },
  );

  test('days since roast exact to calendar day, never negative', () {
    final b = bean(1, 'A', roastDate: DateTime(2026, 9, 7, 23, 50));
    expect(daysSinceRoast(b, DateTime(2026, 9, 19, 0, 5)), 12);
    expect(daysSinceRoast(b, DateTime(2026, 9, 1)), 0);
    expect(daysSinceRoast(bean(2, 'B')), isNull);
  });

  filterTests();
}

Bean full(
  int id,
  String name, {
  String? roaster,
  bool blend = false,
  String? country,
  String? processing,
  String? variety,
  String? producer,
  String? taste,
  double? weight,
  double? cost,
  DateTime? roastDate,
}) => Bean(
  syncId: 'test',
  updatedAt: 0,
  syncState: SyncState.pending,
  deleted: false,
  id: id,
  name: name,
  roaster: roaster,
  roastDate: roastDate,
  isBlend: blend,
  country: country,
  processing: processing,
  variety: variety,
  producer: producer,
  weightGrams: weight,
  taste: taste,
  cost: cost,
  isFrozen: false,
  createdAt: DateTime(2026, 9, 1),
);

void filterTests() {
  final now = DateTime(2026, 9, 19);
  final beans = [
    full(
      1,
      'Kiambu',
      roaster: 'Bonanza',
      country: 'Kenya',
      processing: 'Washed',
      taste: 'blackcurrant, grapefruit',
      weight: 250,
      cost: 14.5,
      roastDate: DateTime(2026, 9, 10),
    ),
    full(
      2,
      'Guji',
      roaster: 'bonanza',
      country: 'Ethiopia',
      processing: 'Natural',
      taste: 'Blueberry, jasmine',
      weight: 250,
      cost: 16,
      roastDate: DateTime(2026, 8, 1),
    ),
    full(
      3,
      'Perfecto',
      roaster: 'Coffee Collective',
      blend: true,
      country: 'Brazil',
      weight: 1000,
      cost: 30,
    ),
  ];
  List<String> names(BeanFilter f, [String q = '']) => filterBeans(
    beans,
    query: q,
    filter: f,
    now: now,
  ).map((b) => b.name).toList();

  group('Filter', () {
    test('empty lets everything through', () {
      expect(names(BeanFilter.empty), ['Kiambu', 'Guji', 'Perfecto']);
      expect(BeanFilter.empty.isActive, false);
    });

    test('type, roaster (OR, case-insensitive) and field AND', () {
      expect(names(const BeanFilter(isBlend: true)), ['Perfecto']);
      expect(names(const BeanFilter(roasters: {'Bonanza'})), [
        'Kiambu',
        'Guji',
      ]);
      expect(
        names(const BeanFilter(roasters: {'Bonanza', 'Coffee Collective'}))
            .length,
        3,
      );
      expect(
        names(const BeanFilter(roasters: {'Bonanza'}, countries: {'kenya'})),
        ['Kiambu'],
      );
    });

    test('taste word by word, beans without a value drop out', () {
      expect(names(const BeanFilter(tastes: {'Jasmine'})), ['Guji']);
      expect(names(const BeanFilter(processings: {'Washed'})), ['Kiambu']);
    });

    test('roast age, weight, cost', () {
      expect(names(const BeanFilter(maxAgeDays: 14)), ['Kiambu']);
      expect(names(const BeanFilter(weight: RangeValues(500, 1000))), [
        'Perfecto',
      ]);
      expect(names(const BeanFilter(cost: RangeValues(15, 20))), ['Guji']);
    });

    test('variety/producer: filter (OR, case-insensitive) and search', () {
      final withNew = [
        full(1, 'A', variety: 'Heirloom', producer: 'Gesha Village'),
        full(2, 'B', variety: 'SL28', producer: 'Kiambu Co-op'),
        full(3, 'C'),
      ];
      List<String> n(BeanFilter f, [String q = '']) =>
          filterBeans(withNew, query: q, filter: f).map((b) => b.name).toList();
      expect(n(const BeanFilter(varieties: {'heirloom'})), ['A']);
      expect(n(const BeanFilter(varieties: {'Heirloom', 'SL28'})), ['A', 'B']);
      expect(n(const BeanFilter(producers: {'Kiambu Co-op'})), ['B']);
      expect(
        n(const BeanFilter(varieties: {'SL28'}, producers: {'Gesha Village'})),
        isEmpty,
      );
      expect(
        const BeanFilter(varieties: {'x'}, producers: {'y'}).activeCount,
        2,
      );
      expect(n(BeanFilter.empty, 'gesha'), ['A']);
      final o = BeanFilterOptions(withNew);
      expect(o.varieties, ['Heirloom', 'SL28']);
      expect(o.producers, ['Gesha Village', 'Kiambu Co-op']);
    });

    test('search and filter combined; activeCount counts fields', () {
      expect(names(BeanFilter.empty, 'berry'), ['Guji']);
      expect(names(const BeanFilter(roasters: {'Bonanza'}), 'kenya'), [
        'Kiambu',
      ]);
      expect(
        const BeanFilter(
          isBlend: false,
          tastes: {'a', 'b'},
          maxAgeDays: 7,
        ).activeCount,
        3,
      );
    });

    test('options: A–Z, slider bounds only with differing values', () {
      final o = BeanFilterOptions(beans);
      expect(o.roasters, ['Bonanza', 'Coffee Collective']);
      expect(o.countries, ['Brazil', 'Ethiopia', 'Kenya']);
      expect(o.weightBounds, const RangeValues(250, 1000));
      expect(BeanFilterOptions([beans[0]]).weightBounds, isNull);
    });
  });
}
