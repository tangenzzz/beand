import 'package:beand/models/coffee_countries.dart';
import 'package:beand/models/coffee_country_profiles.dart';
import 'package:beand/models/coffee_varieties.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every coffee country has exactly one profile', () {
    final codes = CoffeeCountryProfiles.all.map((p) => p.code).toList();
    expect(codes.toSet().length, codes.length);
    expect(codes.toSet(), CoffeeCountries.all.map((c) => c.code).toSet());
  });

  test('varieties point into the variety table', () {
    for (final p in CoffeeCountryProfiles.all) {
      for (final v in p.varieties) {
        expect(CoffeeVarieties.byId[v], isNotNull, reason: '${p.code}: $v');
      }
    }
  });

  test('profiles are short and every one names its sources', () {
    for (final p in CoffeeCountryProfiles.all) {
      if (p.altitude case final a?) expect(a, contains(' m'), reason: p.code);
      expect(p.typicalCup.length, lessThanOrEqualTo(4), reason: p.code);
      expect(p.fact.length, lessThan(120), reason: p.code);
      expect(p.sources, isNotEmpty, reason: p.code);
      for (final url in p.sources) {
        expect(url, startsWith('https://'), reason: '${p.code}: $url');
      }
    }
  });

  test('production rank', () {
    expect(CoffeeCountryProfiles.productionRank('BR'), 1);
    expect(CoffeeCountryProfiles.productionRank('VN'), 2);
    expect(CoffeeCountryProfiles.productionRank('JM'), isNull);
  });
}
