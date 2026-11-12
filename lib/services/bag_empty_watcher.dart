import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;

import '../database/database.dart';
import 'app_settings.dart';
import 'connection_log.dart';

/// Marks a bag as empty once a shot or brew leaves less than
/// [AppSettings.emptyBelowGrams] in it (Settings → Beans → Empty below),
/// and reports it through [onEmptied] (the "Bag empty" notification).
///
/// It follows the grams used per bean: only a rise counts, and only for a
/// bag whose newest shot is recent — so the first sync of a new device,
/// which brings in months of old shots, does not mark (and announce) old
/// bags. A bag the user marks as full again stays so until the next shot.
class BagEmptyWatcher {
  BagEmptyWatcher({
    required this.database,
    required this.settings,
    this.onEmptied,
    DateTime Function()? now,
  }) : _now = now ?? (() => clock.now());

  final AppDatabase database;
  final AppSettings settings;
  final Future<void> Function(Bean bean, double left)? onEmptied;
  final DateTime Function() _now;

  /// A shot older than this is not "just made" (a sync, an import).
  static const recent = Duration(hours: 6);

  StreamSubscription<Map<int, double>>? _sub;
  Map<int, double>? _last;
  Future<void> _running = Future.value();

  void start() {
    _sub = database.watchBeanUsage().listen(
      // One after the other: a bag is never marked twice.
      (usage) => _running = _running.then((_) => _check(usage)),
    );
  }

  /// Done with every change seen so far (tests).
  Future<void> get idle => _running;

  Future<void> dispose() async => _sub?.cancel();

  Future<void> _check(Map<int, double> usage) async {
    final before = _last;
    _last = usage;
    // The first reading is what was there before: nothing just happened.
    if (before == null) return;
    final below = settings.emptyBelowGrams;
    if (below <= 0 || !settings.showBeanStock) return;
    for (final MapEntry(key: id, value: used) in usage.entries) {
      if (used <= (before[id] ?? 0)) continue;
      final bean = await (database.select(
        database.beans,
      )..where((b) => b.id.equals(id))).getSingleOrNull();
      final total = bean?.weightGrams;
      if (bean == null ||
          bean.deleted ||
          bean.emptiedAt != null ||
          total == null ||
          total <= 0) {
        continue;
      }
      final left = total - used;
      if (left >= below) continue;
      final last = await database.lastShotOfBean(id);
      if (last == null || _now().difference(last) > recent) continue;
      await database.updateBean(id, BeansCompanion(emptiedAt: Value(_now())));
      ConnectionLog.write(
        'beans',
        'bag marked empty (${left < 0 ? 0 : left.round()} g left, '
            'limit ${below.round()} g)',
      );
      await onEmptied?.call(bean, left < 0 ? 0 : left);
    }
  }
}
