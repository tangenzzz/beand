import 'package:beand/models/coffee_varieties.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('variety table', () {
    test('ids are unique', () {
      final ids = CoffeeVarieties.all.map((v) => v.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every parent exists and no variety descends from itself', () {
      for (final v in CoffeeVarieties.all) {
        for (final p in v.parents) {
          expect(CoffeeVarieties.byId[p], isNotNull, reason: '${v.id} → $p');
        }
        expect(
          CoffeeVarieties.ancestorsOf(v.id).map((a) => a.id),
          isNot(contains(v.id)),
        );
      }
    });

    test('no name or alias points to two varieties', () {
      final seen = <String, String>{};
      for (final v in CoffeeVarieties.all) {
        for (final n in [v.name, ...v.aliases]) {
          final key = n.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          expect(
            seen[key] == null || seen[key] == v.id,
            isTrue,
            reason: '$n: ${seen[key]} / ${v.id}',
          );
          seen[key] = v.id;
        }
      }
    });

    test('DNA-based placements', () {
      expect(CoffeeVarieties.byId['sl34']!.line, VarietyLine.typica);
      expect(CoffeeVarieties.byId['sl28']!.line, VarietyLine.bourbon);
      expect(CoffeeVarieties.byId['pink-bourbon']!.line, VarietyLine.landrace);
    });
  });

  group('matching free text', () {
    test('spelling variants', () {
      expect(CoffeeVarieties.match('SL-28')?.id, 'sl28');
      expect(CoffeeVarieties.match('sl 28')?.id, 'sl28');
      expect(CoffeeVarieties.match('Geisha')?.id, 'gesha');
      expect(CoffeeVarieties.match('Catuaí')?.id, 'catuai');
      expect(CoffeeVarieties.match('Heirloom')?.id, 'ethiopian-landrace');
      expect(CoffeeVarieties.match('Something new'), isNull);
    });

    test('several varieties in one field', () {
      expect(CoffeeVarieties.matchAll('SL28 & SL34').map((v) => v.id), [
        'sl28',
        'sl34',
      ]);
      expect(
        CoffeeVarieties.matchAll('Caturra, Castillo und Colombia')
            .map((v) => v.id),
        ['caturra', 'castillo', 'colombia'],
      );
      expect(CoffeeVarieties.matchAll('Bourbon / Typica').map((v) => v.id), [
        'bourbon',
        'typica',
      ]);
      expect(CoffeeVarieties.matchAll(null), isEmpty);
    });

    test('a name with a separator inside still matches whole', () {
      expect(CoffeeVarieties.matchAll('Pop3303/21').map((v) => v.id), [
        'pop3303',
      ]);
      expect(CoffeeVarieties.matchAll('Jackson 2/1257').map((v) => v.id), [
        'jackson',
      ]);
    });
  });

  test('ancestors walk up all lines', () {
    final ids = CoffeeVarieties.ancestorsOf('pacamara').map((v) => v.id);
    expect(ids, containsAll(['pacas', 'maragogipe', 'bourbon', 'typica']));
  });
}
