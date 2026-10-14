import '../../database/database.dart';

// Suggestions for the bean form: everything that has ever been entered in the
// same field for any bean. Sorted by frequency, then A–Z. Taste is split into
// single words (comma-separated), all other fields return the whole value.
class BeanSuggestions {
  const BeanSuggestions({
    this.names = const [],
    this.roasters = const [],
    this.countries = const [],
    this.processings = const [],
    this.varieties = const [],
    this.producers = const [],
    this.tastes = const [],
  });

  factory BeanSuggestions.fromBeans(Iterable<Bean> beans) => BeanSuggestions(
    names: rankedDistinct(beans.map((b) => b.name)),
    roasters: rankedDistinct(beans.map((b) => b.roaster)),
    countries: rankedDistinct(beans.map((b) => b.country)),
    processings: rankedDistinct(beans.map((b) => b.processing)),
    varieties: rankedDistinct(beans.map((b) => b.variety)),
    producers: rankedDistinct(beans.map((b) => b.producer)),
    tastes: rankedDistinct(beans.expand((b) => splitTaste(b.taste))),
  );

  final List<String> names;
  final List<String> roasters;
  final List<String> countries;
  final List<String> processings;
  final List<String> varieties;
  final List<String> producers;
  final List<String> tastes;
}

// "Blackcurrant, grapefruit" -> ["Blackcurrant", "grapefruit"]
List<String> splitTaste(String? taste) => (taste ?? '')
    .split(',')
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList();

// Duplicates merged case-insensitively; the most frequently used spelling
// wins.
List<String> rankedDistinct(Iterable<String?> values) {
  final counts = <String, Map<String, int>>{};
  for (final raw in values) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) continue;
    final spellings = counts.putIfAbsent(value.toLowerCase(), () => {});
    spellings[value] = (spellings[value] ?? 0) + 1;
  }
  final entries =
      counts.values.map((spellings) {
        final total = spellings.values.fold(0, (a, b) => a + b);
        final best =
            (spellings.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key;
        return (value: best, total: total);
      }).toList()..sort((a, b) {
        final byCount = b.total.compareTo(a.total);
        return byCount != 0
            ? byCount
            : a.value.toLowerCase().compareTo(b.value.toLowerCase());
      });
  return [for (final e in entries) e.value];
}
