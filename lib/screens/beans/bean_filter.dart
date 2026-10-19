import 'package:flutter/material.dart';

import '../../database/database.dart';
import 'bean_suggestions.dart';
import 'bean_widgets.dart';

// Text searched by the free-text search (lowercase).
String beanSearchText(Bean bean) => [
  bean.name,
  bean.roaster,
  bean.country,
  bean.processing,
  bean.variety,
  bean.producer,
  bean.taste,
  roastedForLabel(bean.roastedFor),
  roastLevelLabel(bean.roastLevel),
].whereType<String>().join(' ').toLowerCase();

// Free-text search over a bean's text fields. [lowerQuery] must be
// lowercase and trimmed.
bool beanMatchesQuery(Bean bean, String lowerQuery) =>
    lowerQuery.isEmpty || beanSearchText(bean).contains(lowerQuery);

// Filter for the bean list. Within a field OR applies (e.g. two roasters
// selected = beans from either one), between fields AND. Beans without a
// value in the filtered field drop out.
class BeanFilter {
  const BeanFilter({
    this.isBlend,
    this.roastedFor = const {},
    this.roastLevels = const {},
    this.roasters = const {},
    this.countries = const {},
    this.processings = const {},
    this.varieties = const {},
    this.producers = const {},
    this.tastes = const {},
    this.maxAgeDays,
    this.weight,
    this.cost,
  });

  static const empty = BeanFilter();

  // null = both types.
  final bool? isBlend;
  // Stored values ('filter'/'espresso'/'omni'), empty = all.
  final Set<String> roastedFor;
  // Stored values ('ultra-light' … 'dark'), empty = all.
  final Set<String> roastLevels;
  // Selected values in original spelling; compared case-insensitively.
  final Set<String> roasters;
  final Set<String> countries;
  final Set<String> processings;
  final Set<String> varieties;
  final Set<String> producers;
  final Set<String> tastes;
  // At most this many days since roasting.
  final int? maxAgeDays;
  // Only set if the range is narrower than the data.
  final RangeValues? weight;
  final RangeValues? cost;

  int get activeCount => [
    isBlend != null,
    roastedFor.isNotEmpty,
    roastLevels.isNotEmpty,
    roasters.isNotEmpty,
    countries.isNotEmpty,
    processings.isNotEmpty,
    varieties.isNotEmpty,
    producers.isNotEmpty,
    tastes.isNotEmpty,
    maxAgeDays != null,
    weight != null,
    cost != null,
  ].where((a) => a).length;

  bool get isActive => activeCount > 0;

  static bool _inSet(Set<String> selected, String? value) {
    if (selected.isEmpty) return true;
    final v = value?.trim().toLowerCase();
    return v != null && selected.any((s) => s.toLowerCase() == v);
  }

  static bool _inRange(RangeValues? range, double? value) {
    if (range == null) return true;
    return value != null && value >= range.start && value <= range.end;
  }

  bool matches(Bean bean, [DateTime? now]) {
    if (isBlend != null && bean.isBlend != isBlend) return false;
    if (!_inSet(roastedFor, bean.roastedFor)) return false;
    if (!_inSet(roastLevels, bean.roastLevel)) return false;
    if (!_inSet(roasters, bean.roaster)) return false;
    if (!_inSet(countries, bean.country)) return false;
    if (!_inSet(processings, bean.processing)) return false;
    if (!_inSet(varieties, bean.variety)) return false;
    if (!_inSet(producers, bean.producer)) return false;
    if (tastes.isNotEmpty) {
      final words = splitTaste(bean.taste).map((t) => t.toLowerCase()).toSet();
      if (!tastes.any((t) => words.contains(t.toLowerCase()))) return false;
    }
    if (maxAgeDays != null) {
      final age = daysSinceRoast(bean, now);
      if (age == null || age > maxAgeDays!) return false;
    }
    return _inRange(weight, bean.weightGrams) && _inRange(cost, bean.cost);
  }
}

List<Bean> filterBeans(
  Iterable<Bean> beans, {
  String query = '',
  BeanFilter filter = BeanFilter.empty,
  DateTime? now,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final b in beans)
      if (beanMatchesQuery(b, q) && filter.matches(b, now)) b,
  ];
}

// Options for the filter sheet, from all existing beans.
class BeanFilterOptions {
  BeanFilterOptions(Iterable<Bean> beans)
    : roasters = _sorted(beans.map((b) => b.roaster)),
      countries = _sorted(beans.map((b) => b.country)),
      processings = _sorted(beans.map((b) => b.processing)),
      varieties = _sorted(beans.map((b) => b.variety)),
      producers = _sorted(beans.map((b) => b.producer)),
      tastes = _sorted(beans.expand((b) => splitTaste(b.taste))),
      weightBounds = _bounds(beans.map((b) => b.weightGrams)),
      costBounds = _bounds(beans.map((b) => b.cost));

  final List<String> roasters;
  final List<String> countries;
  final List<String> processings;
  final List<String> varieties;
  final List<String> producers;
  final List<String> tastes;
  // null if there are fewer than two distinct values (slider pointless).
  final RangeValues? weightBounds;
  final RangeValues? costBounds;

  static List<String> _sorted(Iterable<String?> values) =>
      rankedDistinct(values)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  // Rounded to whole numbers so the slider ends are round values.
  static RangeValues? _bounds(Iterable<double?> values) {
    final v = values.whereType<double>().toList();
    if (v.isEmpty) return null;
    final lo = v.reduce((a, b) => a < b ? a : b).floorToDouble();
    final hi = v.reduce((a, b) => a > b ? a : b).ceilToDouble();
    return lo < hi ? RangeValues(lo, hi) : null;
  }
}
