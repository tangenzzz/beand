import 'package:beand/services/origin_stats.dart';
import 'package:beand/services/statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 20, 12);

  StatShot shot(int beanId, int daysAgo, {int? rating}) => StatShot(
    time: now.subtract(Duration(days: daysAgo)),
    machine: 'meticulous',
    beanId: beanId,
    rating: rating,
  );

  final beans = {
    1: const StatBean(
      id: 1,
      name: 'Guji Hambela',
      country: 'Ethiopia',
      region: 'Guji',
      variety: 'Heirloom',
    ),
    2: const StatBean(
      id: 2,
      name: 'Kiambu AA',
      country: 'Kenia',
      variety: 'SL28, SL34',
    ),
    3: const StatBean(id: 3, name: 'House blend', country: 'Brazil, Ethiopia'),
    4: const StatBean(id: 4, name: 'Mystery', country: 'Atlantis'),
    5: const StatBean(id: 5, name: 'Never brewed', country: 'Panama'),
  };

  final data = StatisticsData([
    shot(1, 2, rating: 5),
    shot(1, 40, rating: 3),
    shot(2, 60, rating: 4),
    shot(3, 1),
    shot(4, 3),
  ], beans);

  test('countries count brewed beans only, blends count for each', () {
    final o = OriginStats.compute(data);
    expect(o.countries.keys, unorderedEquals(['ET', 'KE', 'BR']));
    expect(o.countries['ET']!.beans.map((b) => b.name), [
      'Guji Hambela',
      'House blend',
    ]);
    expect(o.countries['ET']!.shots, 3);
    expect(o.countries['ET']!.bestRating, 5);
    expect(o.countries['ET']!.regionBeans, {'et-guji': 1});
    expect(o.unknownOrigin, ['Mystery']);
  });

  test('the period only highlights, it never removes', () {
    final o = OriginStats.compute(
      data,
      periodStart: now.subtract(const Duration(days: 30)),
    );
    expect(o.countries.length, 3);
    expect(o.countries['ET']!.inPeriod, isTrue);
    expect(o.countries['KE']!.inPeriod, isFalse);
    expect(o.varieties['sl28']!.inPeriod, isFalse);
  });

  test('varieties from the bean field, with the best rating', () {
    final o = OriginStats.compute(data);
    expect(
      o.varieties.keys,
      unorderedEquals(['ethiopian-landrace', 'sl28', 'sl34']),
    );
    expect(o.varieties['sl28']!.bestRating, 4);
    expect(o.countries['KE']!.varieties.map((v) => v.id), ['sl28', 'sl34']);
  });

  test('next to try is an untried neighbour of the best country', () {
    final n = OriginStats.compute(data).nextToTry()!;
    expect(n.near.code, 'ET');
    expect(n.next.region, n.near.region);
    expect(['ET', 'KE', 'BR'], isNot(contains(n.next.code)));
  });
}
