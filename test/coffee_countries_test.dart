import 'package:beand/models/coffee_countries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('country table', () {
    test('codes are unique ISO-style codes', () {
      final codes = CoffeeCountries.all.map((c) => c.code).toList();
      expect(codes.toSet().length, codes.length);
      for (final c in codes) {
        expect(c, matches(RegExp(r'^[A-Z]{2}$')));
      }
    });

    test('no name or alias points to two countries', () {
      final seen = <String, String>{};
      for (final c in CoffeeCountries.all) {
        for (final n in [c.name, ...c.aliases]) {
          final hit = CoffeeCountries.match(n);
          expect(hit?.code, c.code, reason: n);
          expect(seen[n.toLowerCase()] == null, isTrue, reason: n);
          seen[n.toLowerCase()] = c.code;
        }
      }
    });

    test('positions lie in the coffee growing band', () {
      for (final c in CoffeeCountries.all) {
        expect(c.lat, inInclusiveRange(-30, 30), reason: c.name);
        expect(c.lon, inInclusiveRange(-180, 180), reason: c.name);
      }
    });
  });

  group('matching free text', () {
    test('names, German names, islands and areas', () {
      expect(CoffeeCountries.match('Kolumbien')?.code, 'CO');
      expect(CoffeeCountries.match('Äthiopien')?.code, 'ET');
      expect(
        CoffeeCountries.match('Côte d’Ivoire'.replaceAll('’', "'"))?.code,
        'CI',
      );
      expect(CoffeeCountries.match('Sumatra')?.code, 'ID');
      expect(CoffeeCountries.match('Kona')?.code, 'US');
      expect(CoffeeCountries.match('Yirgacheffe')?.code, 'ET');
      expect(CoffeeCountries.match('Atlantis'), isNull);
    });

    test('two-letter codes only in capitals', () {
      expect(CoffeeCountries.match('CO')?.code, 'CO');
      expect(CoffeeCountries.match('co'), isNull);
      expect(CoffeeCountries.match('in'), isNull);
    });

    test('blends list several countries', () {
      expect(CoffeeCountries.matchAll('Brazil, Ethiopia').map((c) => c.code), [
        'BR',
        'ET',
      ]);
      expect(CoffeeCountries.matchAll('Kolumbien & Peru').map((c) => c.code), [
        'CO',
        'PE',
      ]);
      expect(CoffeeCountries.matchAll('Brazil / Brazil').map((c) => c.code), [
        'BR',
      ]);
      expect(CoffeeCountries.matchAll(''), isEmpty);
    });
  });
}
