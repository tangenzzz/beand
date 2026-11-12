import 'package:beand/database/database.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/bag_empty_watcher.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late AppSettings settings;
  late BagEmptyWatcher watcher;
  late List<(String, double)> told;
  final now = DateTime(2026, 11, 12, 9);

  Future<void> settle() async {
    // Let drift's watch emit, then the watcher finish its work.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await watcher.idle;
    }
  }

  Future<Bean> bag(double? weight) => db.insertBean(
    BeansCompanion.insert(
      openedAt: Value(DateTime(2026)),
      name: 'Guji',
      weightGrams: Value(weight),
    ),
  );

  Future<void> shot(int beanId, double dose, {DateTime? at}) => db
      .into(db.shots)
      .insert(
        ShotsCompanion.insert(
          timestamp: at ?? now,
          beanId: Value(beanId),
          doseGrams: Value(dose),
        ),
      );

  Future<Bean> reload(int id) =>
      (db.select(db.beans)..where((b) => b.id.equals(id))).getSingle();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    settings = AppSettings(emptyBelowGrams: 10);
    told = [];
    watcher = BagEmptyWatcher(
      database: db,
      settings: settings,
      now: () => now,
      settleDelay: const Duration(milliseconds: 30),
      onEmptied: (bean, left) async => told.add((bean.name, left)),
    );
  });

  tearDown(() async {
    await watcher.dispose();
    await db.close();
  });

  test('a shot that leaves less than the limit marks the bag', () async {
    final guji = await bag(50);
    await shot(guji.id, 18);
    watcher.start();
    await settle();
    await shot(guji.id, 18); // 14 g left: stays
    await settle();
    expect((await reload(guji.id)).emptiedAt, isNull);
    await shot(guji.id, 6); // 8 g left
    await settle();
    expect((await reload(guji.id)).emptiedAt, now);
    expect(told, [('Guji', 8.0)]);
  });

  test('bags already low at start stay as they are', () async {
    final guji = await bag(20);
    await shot(guji.id, 18);
    watcher.start();
    await settle();
    expect((await reload(guji.id)).emptiedAt, isNull);
    expect(told, isEmpty);
  });

  test('off (0 g), bag level off or no bag weight: nothing', () async {
    final guji = await bag(30);
    final loose = await bag(null);
    watcher.start();
    await settle();
    await settings.setEmptyBelowGrams(0);
    await shot(guji.id, 25);
    await settle();
    await settings.setEmptyBelowGrams(10);
    await settings.setShowBeanStock(false);
    await shot(guji.id, 1);
    await settle();
    await settings.setShowBeanStock(true);
    await shot(loose.id, 18);
    await settle();
    expect((await reload(guji.id)).emptiedAt, isNull);
    expect((await reload(loose.id)).emptiedAt, isNull);
    expect(told, isEmpty);
  });

  test('old shots from a sync do not mark a bag', () async {
    final guji = await bag(30);
    watcher.start();
    await settle();
    await shot(guji.id, 25, at: now.subtract(const Duration(days: 30)));
    await settle();
    expect((await reload(guji.id)).emptiedAt, isNull);
    expect(told, isEmpty);
  });

  test('a bag marked empty by hand is not reported again', () async {
    final guji = await bag(30);
    watcher.start();
    await settle();
    await db.updateBean(guji.id, BeansCompanion(emptiedAt: Value(now)));
    await shot(guji.id, 25);
    await settle();
    expect(told, isEmpty);
  });

  test('setting the amount marks bags already below it, quietly', () async {
    await settings.setEmptyBelowGrams(0);
    final low = await bag(30);
    final full = await bag(250);
    final loose = await bag(null);
    await shot(low.id, 25, at: now.subtract(const Duration(days: 30)));
    await shot(full.id, 18);
    watcher.start();
    await settle();
    // Sliding past 20 g on the way to 4 g: only the end value counts.
    await settings.setEmptyBelowGrams(20);
    await settings.setEmptyBelowGrams(4);
    await settle();
    expect((await reload(low.id)).emptiedAt, isNull);
    await settings.setEmptyBelowGrams(10);
    await settle();
    expect((await reload(low.id)).emptiedAt, now);
    expect((await reload(full.id)).emptiedAt, isNull);
    expect((await reload(loose.id)).emptiedAt, isNull);
    expect(told, isEmpty);
    // Set back to full by hand: stays so.
    await db.updateBean(low.id, const BeansCompanion(emptiedAt: Value(null)));
    await settle();
    expect((await reload(low.id)).emptiedAt, isNull);
  });
}
