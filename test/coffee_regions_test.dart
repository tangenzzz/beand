import 'package:beand/models/coffee_countries.dart';
import 'package:beand/models/coffee_regions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('region table', () {
    test('ids are unique and every country exists', () {
      final ids = CoffeeRegions.all.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final r in CoffeeRegions.all) {
        expect(CoffeeCountries.byCode[r.country], isNotNull, reason: r.id);
      }
    });

    test('every region lies near its country', () {
      for (final r in CoffeeRegions.all) {
        final c = CoffeeCountries.byCode[r.country]!;
        // Countries are wide (Brazil, Indonesia, Hawaii's islands), but a
        // region far away from its country's dot is a typo in lon/lat.
        expect(
          (r.lon - c.lon).abs() + (r.lat - c.lat).abs(),
          lessThan(50),
          reason: r.id,
        );
      }
    });

    test('every name and alias finds its own region', () {
      for (final r in CoffeeRegions.all) {
        for (final n in [r.name, ...r.aliases]) {
          expect(
            CoffeeRegions.match(n, country: r.country)?.id,
            r.id,
            reason: n,
          );
        }
      }
    });

    test('the official lists are complete', () {
      expect(CoffeeRegions.ofCountry('GT'), hasLength(8)); // Anacafé
      expect(CoffeeRegions.ofCountry('CR'), hasLength(8)); // ICAFE
      expect(CoffeeRegions.ofCountry('HN'), hasLength(6)); // IHCAFE
      expect(CoffeeRegions.ofCountry('SV'), hasLength(6));
    });
  });

  group('matching free text', () {
    test('towns and spellings point to the region', () {
      expect(CoffeeRegions.match('Pitalito')?.id, 'co-huila');
      expect(CoffeeRegions.match('sidamo')?.id, 'et-sidama');
      expect(CoffeeRegions.match('Narino')?.id, 'co-narino');
      expect(CoffeeRegions.match('Dak Lak')?.id, 'vn-dak-lak');
      expect(CoffeeRegions.match('Nowhere'), isNull);
    });

    test('several regions in one field, duplicates once', () {
      expect(CoffeeRegions.matchAll('Sidama / Guji').map((r) => r.id), [
        'et-sidama',
        'et-guji',
      ]);
      expect(CoffeeRegions.matchAll('Huila, Pitalito').map((r) => r.id), [
        'co-huila',
      ]);
    });
  });

  group('origin of a bean', () {
    test('country field wins, region refines it', () {
      final o = CoffeeRegions.forBean('Colombia', 'Huila');
      expect(o.countries.map((c) => c.code), ['CO']);
      expect(o.regions.map((r) => r.id), ['co-huila']);
    });

    test('a region from another country is ignored, not guessed', () {
      final o = CoffeeRegions.forBean('Kenya', 'Huila');
      expect(o.countries.map((c) => c.code), ['KE']);
      expect(o.regions, isEmpty);
    });

    test('an empty country is filled from the region', () {
      final o = CoffeeRegions.forBean(null, 'Yirgacheffe');
      expect(o.countries.map((c) => c.code), ['ET']);
      expect(o.regions.map((r) => r.id), ['et-yirgacheffe']);
    });

    test('a region typed into the country field still counts', () {
      final o = CoffeeRegions.forBean('Gayo', null);
      expect(o.countries.map((c) => c.code), ['ID']);
      expect(o.regions.map((r) => r.id), ['id-gayo']);
    });

    test('blends keep each region with its country', () {
      final o = CoffeeRegions.forBean('Brazil, Ethiopia', 'Cerrado / Guji');
      expect(o.countries.map((c) => c.code), ['BR', 'ET']);
      expect(o.regions.map((r) => r.id), ['br-cerrado', 'et-guji']);
    });

    test('unknown stays empty', () {
      final o = CoffeeRegions.forBean('Atlantis', 'Somewhere');
      expect(o.countries, isEmpty);
      expect(o.regions, isEmpty);
    });
  });
}
