// Coffee countries and varieties for Settings → Statistics → Beans.
//
// The collection — which countries and varieties you have had, and so which
// country profiles are unlocked — always counts all time: a profile must not
// lock again because the period changed. The period only decides which of
// them are highlighted as brewed "now".

import 'dart:math' as math;

import '../models/coffee_countries.dart';
import '../models/coffee_regions.dart';
import '../models/coffee_varieties.dart';
import 'statistics.dart';

/// A bean as it appears in a country or variety sheet.
class OriginBean {
  const OriginBean(this.name, this.bestRating, {this.roaster});
  final String name;
  final String? roaster;

  /// Best star rating of its shots, null without a rated shot.
  final int? bestRating;
}

class CountryStat {
  CountryStat(this.country);

  final CoffeeCountry country;
  final beans = <OriginBean>[];
  int shots = 0;
  int? bestRating;
  DateTime? firstCup;

  /// Beans per region id of this country.
  final regionBeans = <String, int>{};
  final varieties = <CoffeeVariety>[];

  /// Brewed within the chosen period.
  bool inPeriod = false;
}

class VarietyStat {
  VarietyStat(this.variety);

  final CoffeeVariety variety;
  final beans = <OriginBean>[];
  int? bestRating;
  bool inPeriod = false;
}

class OriginStats {
  OriginStats._(this.countries, this.varieties, this.unknownOrigin);

  /// Every country you have brewed a bean from, by ISO code.
  final Map<String, CountryStat> countries;

  /// Every known variety you have brewed, by id.
  final Map<String, VarietyStat> varieties;

  /// Brewed beans whose country could not be recognised.
  final List<String> unknownOrigin;

  static OriginStats compute(StatisticsData data, {DateTime? periodStart}) {
    // Shots per bean, all time.
    final byBean = <int, List<StatShot>>{};
    for (final s in data.shots) {
      if (s.beanId != null) (byBean[s.beanId!] ??= []).add(s);
    }

    final countries = <String, CountryStat>{};
    final varieties = <String, VarietyStat>{};
    final unknown = <String>[];

    for (final MapEntry(key: beanId, value: shots) in byBean.entries) {
      final bean = data.beans[beanId];
      if (bean == null) continue;
      int? best;
      DateTime? first;
      var recent = false;
      for (final s in shots) {
        final r = s.rating;
        if (r != null && r > 0) best = best == null ? r : math.max(best, r);
        if (first == null || s.time.isBefore(first)) first = s.time;
        if (periodStart == null || !s.time.isBefore(periodStart)) {
          recent = true;
        }
      }
      final origin = CoffeeRegions.forBean(bean.country, bean.region);
      final kinds = CoffeeVarieties.matchAll(bean.variety);
      final entry = OriginBean(bean.name, best, roaster: bean.roaster);

      if (origin.countries.isEmpty) {
        unknown.add(bean.name);
      }
      for (final c in origin.countries) {
        final stat = countries[c.code] ??= CountryStat(c);
        stat.beans.add(entry);
        stat.shots += shots.length;
        stat.bestRating = _max(stat.bestRating, best);
        if (stat.firstCup == null || first!.isBefore(stat.firstCup!)) {
          stat.firstCup = first;
        }
        stat.inPeriod |= recent;
        for (final r in origin.regions.where((r) => r.country == c.code)) {
          stat.regionBeans[r.id] = (stat.regionBeans[r.id] ?? 0) + 1;
        }
        for (final v in kinds) {
          if (!stat.varieties.contains(v)) stat.varieties.add(v);
        }
      }
      for (final v in kinds) {
        final stat = varieties[v.id] ??= VarietyStat(v);
        stat.beans.add(entry);
        stat.bestRating = _max(stat.bestRating, best);
        stat.inPeriod |= recent;
      }
    }
    for (final c in countries.values) {
      c.beans.sort(_byRating);
    }
    for (final v in varieties.values) {
      v.beans.sort(_byRating);
    }
    unknown.sort();
    return OriginStats._(countries, varieties, unknown);
  }

  static int? _max(int? a, int? b) =>
      a == null ? b : (b == null ? a : math.max(a, b));

  static int _byRating(OriginBean a, OriginBean b) =>
      (b.bestRating ?? 0).compareTo(a.bestRating ?? 0);
}
