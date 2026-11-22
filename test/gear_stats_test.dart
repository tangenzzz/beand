import 'package:beand/models/gear.dart';
import 'package:beand/services/gear_stats.dart';
import 'package:beand/services/statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 22, 12);

  const niche = Gear(
    id: 'g-niche',
    type: GearType.grinder,
    brand: 'Niche',
    model: 'Zero',
  );
  const zerno = Gear(
    id: 'g-zerno',
    type: GearType.grinder,
    brand: 'Zerno',
    model: 'Z1',
    specs: {'activeBurr': 'SSP HU'},
  );
  const orea = Gear(
    id: 'g-orea',
    type: GearType.brewer,
    brand: 'Orea',
    model: 'V4',
  );
  const filter = Gear(
    id: 'g-filter',
    type: GearType.filter,
    brand: 'Sibarist',
    model: 'Fast',
    stock: 77,
  );
  const daily = BrewChain(id: 'c-daily', name: 'Daily', gearIds: ['g-niche']);
  const morning = BrewChain(
    id: 'c-orea',
    name: 'Orea morning',
    gearIds: ['g-orea', 'g-filter'],
  );

  StatShot shot(
    int daysAgo, {
    String machine = 'meticulous',
    String? gearIds,
    String? brewedWith,
    String? grinder,
    String? burrs,
    String? grind,
    String? chain,
    double dose = 18,
    double? water,
    int? beanId,
    String? profile,
  }) => StatShot(
    time: now.subtract(Duration(days: daysAgo)),
    machine: machine,
    gearIds: gearIds,
    brewedWith: brewedWith,
    grinder: grinder,
    burrs: burrs,
    grind: grind,
    chainId: chain,
    dose: dose,
    finalWeight: water,
    beanId: beanId,
    profile: profile,
  );

  GearStats compute(List<StatShot> shots, {DateTime? from}) =>
      GearStats.compute(
        StatisticsData(shots, const {}),
        gear: const [niche, zerno, orea, filter],
        chains: const [daily, morning],
        periodStart: from,
      );

  test('IDs win, renamed gear still counts', () {
    final s = compute([
      // The grinder was renamed after this shot: the text no longer
      // matches, the ID does.
      shot(
        1,
        gearIds: 'g-niche',
        brewedWith: 'Niche OldName',
        chain: 'c-daily',
      ),
      shot(2, gearIds: 'g-niche', chain: 'c-daily', dose: 20),
    ]);
    final g = s.ofType(GearType.grinder).single;
    expect(g.gear, niche);
    expect(g.shots, 2);
    expect(g.grams, 38);
    expect(s.chains.single.chain, daily);
    expect(s.chains.single.grams, 38);
  });

  test('older shots without IDs are matched by name, burrs included', () {
    final s = compute([
      shot(
        3,
        brewedWith: 'Zerno Z1 (SSP HU)',
        grinder: 'Z1',
        burrs: 'SSP HU',
        grind: '2.5',
      ),
      shot(4, grinder: 'Z1', burrs: 'Stock', grind: '3.25'),
    ]);
    final z = s.ofType(GearType.grinder).single;
    expect(z.gear, zerno);
    expect(z.shots, 2);
    expect(z.burrs.keys, unorderedEquals(['SSP HU', 'Stock']));
    expect(z.grindMin, 2.5);
    expect(z.grindMax, 3.25);
  });

  test('a grinder no longer on the desk keeps its numbers', () {
    final s = compute([shot(5, grinder: 'Encore')]);
    final old = s.ofType(GearType.grinder).single;
    expect(old.onDesk, isFalse);
    expect(old.name, 'Encore');
    expect(old.grams, 18);
  });

  test('pour over brews, water and filters', () {
    final s = compute([
      shot(
        1,
        machine: 'pourover',
        gearIds: 'g-orea,g-filter',
        chain: 'c-orea',
        dose: 15,
        water: 250,
      ),
      shot(
        2,
        machine: 'pourover',
        gearIds: 'g-orea,g-filter',
        chain: 'c-orea',
        dose: 15,
        water: 250,
      ),
    ]);
    final brewer = s.ofType(GearType.brewer).single;
    expect(brewer.brews, 2);
    expect(brewer.waterMl, 500);
    final f = s.ofType(GearType.filter).single;
    expect(f.uses, 2);
    expect(f.gear!.stock, 77);
  });

  test('the period limits the counts, not first use', () {
    final s = compute([
      shot(1, gearIds: 'g-niche'),
      shot(60, gearIds: 'g-niche'),
    ], from: now.subtract(const Duration(days: 30)));
    final g = s.ofType(GearType.grinder).single;
    expect(g.shots, 1);
    expect(g.firstUse, now.subtract(const Duration(days: 60)));
  });

  test('grinder vs. grinder on the beans both have ground', () {
    final s = compute([
      // Bean 1 on both, bean 2 only on the Niche.
      shot(1, gearIds: 'g-niche', beanId: 1, grind: '14', dose: 18),
      shot(2, gearIds: 'g-niche', beanId: 1, grind: '15', dose: 18),
      shot(3, gearIds: 'g-zerno', beanId: 1, grind: '2.5', dose: 18),
      shot(4, gearIds: 'g-niche', beanId: 2, grind: '20'),
    ]);
    final pair = s.grinderPairs.single;
    final names = {pair.a.name, pair.b.name};
    expect(names, {'Zero', 'Z1'});
    expect(pair.runs, hasLength(1));
    final (key, ga, gb) = pair.runs.single;
    expect(key.bean, 1);
    final niche = pair.a.name == 'Zero' ? ga : gb;
    final zerno = pair.a.name == 'Zero' ? gb : ga;
    expect(niche, 14.5); // median of 14 and 15
    expect(zerno, 2.5);
  });

  test('only the same profile and brew method are compared', () {
    final s = compute([
      shot(1, gearIds: 'g-niche', beanId: 1, grind: '14', profile: 'Classic'),
      // Same bean, other profile: not comparable.
      shot(2, gearIds: 'g-zerno', beanId: 1, grind: '2.5', profile: 'Turbo'),
      // Same bean and "profile" name, but pour over: not comparable.
      shot(
        3,
        machine: 'pourover',
        gearIds: 'g-zerno',
        beanId: 1,
        grind: '6',
        profile: 'Classic',
      ),
    ]);
    expect(s.grinderPairs, isEmpty);

    final like = compute([
      shot(1, gearIds: 'g-niche', beanId: 1, grind: '14', profile: 'Classic'),
      shot(2, gearIds: 'g-zerno', beanId: 1, grind: '2.5', profile: 'Classic'),
    ]);
    final run = like.grinderPairs.single.runs.single.$1;
    expect(run.profile, 'Classic');
    expect(run.pourOver, isFalse);
  });
}
