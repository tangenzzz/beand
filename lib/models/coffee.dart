import 'package:drift/drift.dart' show Value;

import '../database/database.dart';
import '../screens/beans/bean_stock.dart';

// A coffee and its bags. Every row of Beans is one bag; the rows that share a
// name and roaster are one coffee, unless [Bean.coffeeId] keeps one apart (a
// new harvest under the same name). Nothing else ties them together, so shots
// go on pointing at a single bag.

enum BagState { open, sealed, frozen, empty }

String _norm(String? s) => (s ?? '').trim().toLowerCase();

/// Same [coffeeKey] = same coffee.
String coffeeKey(Bean b) =>
    b.coffeeId ?? 'name:${_norm(b.name)}|${_norm(b.roaster)}';

/// The key a coffee of this name would get without an own [Bean.coffeeId].
String coffeeNameKey(String name, String? roaster) =>
    'name:${_norm(name)}|${_norm(roaster)}';

BagState bagState(Bean b, Map<int, double> usage, {required bool stock}) {
  if (beanUsedUp(b, usage, stock: stock)) return BagState.empty;
  if (b.isFrozen) return BagState.frozen;
  return b.openedAt == null ? BagState.sealed : BagState.open;
}

// Bags in the order they are shown: what's in use first, oldest first within.
int _compareBags(
  Bean a,
  Bean b,
  Map<int, double> usage, {
  required bool stock,
}) {
  final byState = bagState(
    a,
    usage,
    stock: stock,
  ).index.compareTo(bagState(b, usage, stock: stock).index);
  if (byState != 0) return byState;
  final ar = a.roastDate ?? a.createdAt;
  final br = b.roastDate ?? b.createdAt;
  return ar.compareTo(br);
}

class Coffee {
  Coffee._(this.key, this.bags, this._usage, this._stock);

  final String key;

  /// All bags, in display order: open, sealed, frozen, empty.
  final List<Bean> bags;
  final Map<int, double> _usage;
  final bool _stock;

  BagState stateOf(Bean bag) => bagState(bag, _usage, stock: _stock);

  /// The bags still to use.
  List<Bean> get activeBags => [
    for (final b in bags)
      if (stateOf(b) != BagState.empty) b,
  ];

  bool has(BagState state) => bags.any((b) => stateOf(b) == state);

  /// First bag in [state], null without one.
  Bean? firstIn(BagState state) {
    for (final b in bags) {
      if (stateOf(b) == state) return b;
    }
    return null;
  }

  /// What stands for the coffee in a list: the bag in use.
  Bean get lead => bags.first;

  /// The fields of the coffee, for the card: the newest bag knows most. The
  /// photo may be on an older one.
  Bean get details {
    final newest = bags.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    if (newest.photoPath != null) return newest;
    for (final b in bags) {
      if (b.photoPath != null) {
        return newest.copyWith(photoPath: Value(b.photoPath));
      }
    }
    return newest;
  }

  /// Bags by their number: stays the same whatever happens to their state.
  int numberOf(Bean bag) {
    final byAge = [...bags]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return byAge.indexWhere((b) => b.id == bag.id) + 1;
  }

  /// Bags besides [lead] still to use, in display order.
  List<Bean> get moreBags => [
    for (final b in activeBags)
      if (b.id != lead.id) b,
  ];
}

/// Coffees of [beans], each with its bags in display order. Order of the
/// coffees: as their first bag came in.
List<Coffee> groupCoffees(
  Iterable<Bean> beans,
  Map<int, double> usage, {
  required bool stock,
}) {
  final byKey = <String, List<Bean>>{};
  for (final b in beans) {
    byKey.putIfAbsent(coffeeKey(b), () => []).add(b);
  }
  return [
    for (final e in byKey.entries)
      Coffee._(
        e.key,
        e.value..sort((a, b) => _compareBags(a, b, usage, stock: stock)),
        usage,
        stock,
      ),
  ];
}

/// The ids of all bags of [bag]'s coffee.
List<int> coffeeBagIds(Iterable<Bean> beans, Bean bag) {
  final key = coffeeKey(bag);
  return [
    for (final b in beans)
      if (coffeeKey(b) == key) b.id,
  ];
}

/// What a shot can be made with. A coffee with an open bag offers its open
/// bags and hides the sealed ones; with only sealed ones the oldest stands in,
/// and the first shot opens it. Frozen and empty ones are out.
List<Bean> pickableBags(
  Iterable<Bean> beans,
  Map<int, double> usage, {
  required bool stock,
}) => [
  for (final c in groupCoffees(beans, usage, stock: stock))
    ...c.has(BagState.open)
        ? c.bags.where((b) => c.stateOf(b) == BagState.open)
        : [?c.firstIn(BagState.sealed)],
];
