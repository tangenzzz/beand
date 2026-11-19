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

  test('profiles are filled and short', () {
    for (final p in CoffeeCountryProfiles.all) {
      expect(p.altitude, endsWith(' m'), reason: p.code);
      expect(p.process, isNotEmpty, reason: p.code);
      expect(p.typicalCup.length, inInclusiveRange(2, 4), reason: p.code);
      expect(p.fact.length, lessThan(120), reason: p.code);
    }
  });

  test('production rank', () {
    expect(CoffeeCountryProfiles.productionRank('BR'), 1);
    expect(CoffeeCountryProfiles.productionRank('VN'), 2);
    expect(CoffeeCountryProfiles.productionRank('JM'), isNull);
  });
}
