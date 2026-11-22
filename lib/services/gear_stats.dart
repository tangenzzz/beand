// What each piece on My Coffee Desk has done, for Statistics → Gear.
//
// A shot names its gear in two ways: since schema 29 by desk ID
// (Shots.gearIds), before that only as text (brewedWith, grinder). IDs win;
// older shots are matched by name against the desk as it is now. A grinder
// that is no longer on the desk keeps its numbers under its old name.

import 'dart:math' as math;

import '../models/gear.dart';
import 'statistics.dart';

class GearUse {
  GearUse({this.gear, required this.name, this.brand, required this.type});

  /// Null for a grinder that is no longer on the desk.
  final Gear? gear;
  final String name;
  final String? brand;
  final GearType type;

  int shots = 0;
  int brews = 0;
  double grams = 0;
  double waterMl = 0;

  /// All time, not only the period.
  DateTime? firstUse;
  DateTime? lastUse;

  /// Grinders: fitted burrs → what went through them.
  final burrs = <String, BurrUse>{};

  /// Grinders: lowest and highest grind setting used.
  double? grindMin, grindMax;

  /// Coffee by bean (grams), for the grinder sheet.
  final beanGrams = <int, double>{};

  /// Grinders: per bean, the settings, shot times and ratios used – the
  /// ground for comparing two grinders on the same beans.
  final beanRuns = <int, BeanRun>{};

  int get uses => shots + brews;
  bool get onDesk => gear != null;
}

class BurrUse {
  BurrUse(this.name);
  final String name;
  int shots = 0;
  double grams = 0;
  DateTime? first, last;
}

class BeanRun {
  final grinds = <double>[];

  /// Espresso only: shot time in seconds and yield ÷ dose.
  final seconds = <double>[];
  final ratios = <double>[];
}

/// Two grinders on the beans both have ground.
class GrinderPair {
  GrinderPair(this.a, this.b, this.beans);
  final GearUse a, b;

  /// Bean id → median grind on a and on b (null without a setting).
  final List<(int, double?, double?)> beans;

  double? get secondsA => _meanOf(a, (r) => r.seconds);
  double? get secondsB => _meanOf(b, (r) => r.seconds);
  double? get ratioA => _meanOf(a, (r) => r.ratios);
  double? get ratioB => _meanOf(b, (r) => r.ratios);

  // Averaged over the shared beans only, so one grinder getting the easy
  // beans does not tilt it.
  double? _meanOf(GearUse g, List<double> Function(BeanRun) pick) {
    final all = [for (final (id, _, _) in beans) ...pick(g.beanRuns[id]!)];
    return all.isEmpty ? null : all.reduce((x, y) => x + y) / all.length;
  }
}

double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

class ChainUse {
  ChainUse(this.chain);
  final BrewChain chain;
  int shots = 0;
  int brews = 0;
  double grams = 0;
  double waterMl = 0;
  DateTime? lastUse;
  int get uses => shots + brews;
}

class GearStats {
  GearStats._(this.pieces, this.chains);

  /// Grinder pairs that share beans in the period, most shared first (at
  /// most three pairs).
  List<GrinderPair> get grinderPairs {
    final grinders = ofType(GearType.grinder)
        .where((g) => g.beanRuns.isNotEmpty)
        .toList();
    final pairs = <GrinderPair>[];
    for (var i = 0; i < grinders.length; i++) {
      for (var j = i + 1; j < grinders.length; j++) {
        final a = grinders[i], b = grinders[j];
        final shared = [
          for (final id in a.beanRuns.keys)
            if (b.beanRuns.containsKey(id))
              (
                id,
                _median(a.beanRuns[id]!.grinds),
                _median(b.beanRuns[id]!.grinds),
              ),
        ];
        if (shared.isNotEmpty) pairs.add(GrinderPair(a, b, shared));
      }
    }
    pairs.sort((x, y) => y.beans.length.compareTo(x.beans.length));
    return pairs.take(3).toList();
  }

  /// Pieces used at least once (all time), most used in the period first.
  final List<GearUse> pieces;
  final List<ChainUse> chains;

  List<GearUse> ofType(GearType t) => [
    for (final p in pieces)
      if (p.type == t) p,
  ];

  static GearStats compute(
    StatisticsData data, {
    required List<Gear> gear,
    required List<BrewChain> chains,
    DateTime? periodStart,
  }) {
    final byId = {for (final g in gear) g.id: g};
    final byLabel = <String, Gear>{
      for (final g in gear) _norm(g.label): g,
      // A grinder's label carries its burrs; older lines may not.
      for (final g in gear) _norm(_withoutBurrs(g.label)): g,
    };
    final uses = <String, GearUse>{};
    GearUse useOf(Gear g) => uses[g.id] ??= GearUse(
      gear: g,
      name: g.displayName,
      brand: g.brand,
      type: g.type,
    );
    final chainUses = <String, ChainUse>{
      for (final c in chains) c.id: ChainUse(c),
    };

    for (final s in data.shots) {
      final inPeriod = periodStart == null || !s.time.isBefore(periodStart);
      final pieces = <GearUse>[];
      final ids = s.gearIds?.split(',').where((e) => e.isNotEmpty).toList();
      if (ids != null) {
        for (final id in ids) {
          if (byId[id] case final g?) pieces.add(useOf(g));
        }
      } else {
        for (final line in (s.brewedWith ?? '').split('\n')) {
          if (line.trim().isEmpty) continue;
          if (byLabel[_norm(line)] case final g?) pieces.add(useOf(g));
        }
      }
      // The grinder: from the pieces, else by its name on the shot; a
      // grinder that left the desk keeps its own entry.
      if (!pieces.any((p) => p.type == GearType.grinder)) {
        final name = s.grinder?.trim();
        if (name != null && name.isNotEmpty) {
          final g = gear
              .where(
                (g) =>
                    g.type == GearType.grinder && _norm(g.model) == _norm(name),
              )
              .firstOrNull;
          pieces.add(
            g != null
                ? useOf(g)
                : (uses['grinder:${_norm(name)}'] ??= GearUse(
                    name: name,
                    type: GearType.grinder,
                  )),
          );
        }
      }

      final water = s.isPourOver
          ? (s.finalWeight ?? 0)
          : (s.flowVolumeMl ?? s.finalWeight ?? 0);
      for (final p in {...pieces}) {
        if (p.firstUse == null || s.time.isBefore(p.firstUse!)) {
          p.firstUse = s.time;
        }
        if (p.lastUse == null || s.time.isAfter(p.lastUse!)) {
          p.lastUse = s.time;
        }
        if (!inPeriod) continue;
        if (s.isPourOver) {
          p.brews++;
        } else {
          p.shots++;
        }
        p.waterMl += water;
        if (p.type == GearType.grinder) {
          final dose = s.dose ?? 0;
          p.grams += dose;
          if (s.beanId != null) {
            p.beanGrams[s.beanId!] = (p.beanGrams[s.beanId!] ?? 0) + dose;
          }
          final burr = s.burrs?.trim();
          if (burr != null && burr.isNotEmpty) {
            final b = p.burrs[burr] ??= BurrUse(burr);
            b.shots++;
            b.grams += dose;
            if (b.first == null || s.time.isBefore(b.first!)) b.first = s.time;
            if (b.last == null || s.time.isAfter(b.last!)) b.last = s.time;
          }
          final grind = double.tryParse(s.grind ?? '');
          if (s.beanId != null) {
            final run = p.beanRuns[s.beanId!] ??= BeanRun();
            if (grind != null) run.grinds.add(grind);
            if (!s.isPourOver) {
              if ((s.durationMs ?? 0) >= 10000) {
                run.seconds.add(s.durationMs! / 1000);
              }
              if ((s.dose ?? 0) > 0 && (s.finalWeight ?? 0) > 0) {
                run.ratios.add(s.finalWeight! / s.dose!);
              }
            }
          }
          if (grind != null) {
            p.grindMin = p.grindMin == null
                ? grind
                : math.min(p.grindMin!, grind);
            p.grindMax = p.grindMax == null
                ? grind
                : math.max(p.grindMax!, grind);
          }
        }
      }

      if (chainUses[s.chainId] case final c?) {
        if (c.lastUse == null || s.time.isAfter(c.lastUse!)) c.lastUse = s.time;
        if (inPeriod) {
          if (s.isPourOver) {
            c.brews++;
          } else {
            c.shots++;
          }
          c.grams += s.dose ?? 0;
          c.waterMl += water;
        }
      }
    }

    final pieces = uses.values.toList()
      ..sort((a, b) {
        final byUse = b.uses.compareTo(a.uses);
        return byUse != 0 ? byUse : a.name.compareTo(b.name);
      });
    final usedChains = chainUses.values.where((c) => c.lastUse != null).toList()
      ..sort((a, b) => b.uses.compareTo(a.uses));
    return GearStats._(pieces, usedChains);
  }

  static String _norm(String s) => s.trim().toLowerCase();

  static String _withoutBurrs(String label) =>
      label.replaceFirst(RegExp(r'\s*\([^)]*\)$'), '');
}
