import 'package:beand/database/database.dart';
import 'package:beand/services/setup_suggestion.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// User 2026-11-23: a shot brewed while the app was closed comes in without
// bean, dose and grind — suggest them (Pre-Shot card, else the last shot
// with the profile), for every brew method alike.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<int> bean(String name) =>
      db.into(db.beans).insert(BeansCompanion.insert(name: name));

  Future<Shot> shot(
    String machine,
    DateTime at, {
    String? profile,
    int? beanId,
    double? dose,
    String? grind,
    String? grinder,
    String? chain,
  }) async {
    final id = await db
        .into(db.shots)
        .insert(
          ShotsCompanion.insert(
            timestamp: at,
            machine: Value(machine),
            profileName: Value(profile),
            beanId: Value(beanId),
            doseGrams: Value(dose),
            grindSize: Value(grind),
            grinder: Value(grinder),
            brewChainId: Value(chain),
          ),
        );
    return (db.select(db.shots)..where((s) => s.id.equals(id))).getSingle();
  }

  for (final machine in ['meticulous', 'gaggimate', 'pourover', 'espresso']) {
    group(machine, () {
      test(
        'the last earlier shot with the same profile is suggested',
        () async {
          final b = await bean('Fazenda Matão');
          await shot(
            machine,
            DateTime(2026, 11, 20),
            profile: 'P',
            beanId: b,
            dose: 14,
            grind: '3.8',
            grinder: 'Niche Zero',
            chain: 'bar',
          );
          // Another profile and a later shot don't count.
          await shot(machine, DateTime(2026, 11, 21), profile: 'Q', beanId: b);
          final bare = await shot(
            machine,
            DateTime(2026, 11, 22),
            profile: 'P',
          );
          await shot(machine, DateTime(2026, 11, 23), profile: 'P', beanId: b);
          // Other machines neither.
          await shot(
            machine == 'gaggimate' ? 'meticulous' : 'gaggimate',
            DateTime(2026, 11, 21, 12),
            profile: 'P',
            beanId: b,
            dose: 99,
          );
          expect(shotNeedsDetails(bare), isTrue);

          final options = await suggestSetups(db, bare);
          expect(options, hasLength(1));
          final s = options.single;
          expect(s.source, SetupSource.lastShot);
          expect(s.beanId, b);
          expect(s.doseGrams, 14);
          expect(s.grindSize, '3.8');

          await s.applyTo(db, bare.id);
          final after = (await db.watchShotEntry(bare.id).first)!.shot;
          expect(after.beanId, b);
          expect(after.doseGrams, 14);
          expect(after.grindSize, '3.8');
          expect(after.grinder, 'Niche Zero');
          expect(after.brewChainId, 'bar');
          expect(shotNeedsDetails(after), isFalse);
        },
      );

      test('nothing earlier with the profile: no suggestion', () async {
        final bare = await shot(machine, DateTime(2026, 11, 22), profile: 'P');
        expect(await suggestSetups(db, bare), isEmpty);
      });
    });
  }

  test(
    'the Pre-Shot card comes first for the newest shot with its profile',
    () async {
      final b = await bean('Old bag');
      final fresh = await bean('New bag');
      await shot('meticulous', DateTime(2026, 11, 20), profile: 'P', beanId: b);
      final bare = await shot(
        'meticulous',
        DateTime(2026, 11, 22),
        profile: 'P',
      );
      final setup = ShotSetup.inMemory()
        ..setProfile('p', 'P')
        ..setBean(fresh)
        ..setDose(15)
        ..setGrind(3.6);
      final setups = ShotSetups(
        meticulous: setup,
        gaggimate: ShotSetup.inMemory(machineKey: 'gaggimate'),
      );

      final options = await suggestSetups(db, bare, setups: setups);
      expect(options.map((o) => o.source), [
        SetupSource.preShot,
        SetupSource.lastShot,
      ]);
      expect(options.first.beanId, fresh);
      expect(options.first.doseGrams, 15);
      expect(options.first.grindSize, '3.6');

      // Another profile in the card: only the last shot.
      setup.setProfile('q', 'Q');
      expect(
        (await suggestSetups(db, bare, setups: setups)).map((o) => o.source),
        [SetupSource.lastShot],
      );

      // Not the newest shot any more: the card belongs to the later one.
      setup.setProfile('p', 'P');
      await shot('meticulous', DateTime(2026, 11, 23), profile: 'P');
      expect(
        (await suggestSetups(db, bare, setups: setups)).map((o) => o.source),
        [SetupSource.lastShot],
      );
    },
  );

  test('a suggestion fills only empty fields; Copy from replaces', () async {
    final a = await bean('A');
    final b = await bean('B');
    final source = await shot(
      'meticulous',
      DateTime(2026, 11, 20),
      profile: 'P',
      beanId: a,
      dose: 14,
      grind: '3.8',
    );
    // Dose already entered by hand.
    final target = await shot(
      'meticulous',
      DateTime(2026, 11, 22),
      profile: 'P',
      dose: 18,
    );
    await SetupSuggestion.fromShot(source).applyTo(db, target.id);
    var after = (await db.watchShotEntry(target.id).first)!.shot;
    expect(after.beanId, a);
    expect(after.doseGrams, 18);
    expect(after.grindSize, '3.8');

    final other = await shot(
      'meticulous',
      DateTime(2026, 11, 21),
      profile: 'Q',
      beanId: b,
      dose: 16,
      grind: '4.0',
    );
    await SetupSuggestion.fromShot(other)
        .applyTo(db, target.id, onlyEmpty: false);
    after = (await db.watchShotEntry(target.id).first)!.shot;
    expect(after.beanId, b);
    expect(after.doseGrams, 16);
    expect(after.grindSize, '4.0');
  });

  test(
    'old machine history before the first shot with a bean stays unmarked',
    () async {
      final b = await bean('A');
      // Backfilled from the machine before bean'd was used (257 on the test
      // phone): no hint, or every history row would say "Needs details".
      final old = await shot('meticulous', DateTime(2026, 9, 1), profile: 'P');
      await shot('meticulous', DateTime(2026, 10, 1), profile: 'P', beanId: b);
      final missed = await shot(
        'meticulous',
        DateTime(2026, 11, 22),
        profile: 'P',
      );
      // A machine without any bean yet: nothing marked at all.
      final gm = await shot('gaggimate', DateTime(2026, 11, 22), profile: 'G');

      final since = setupSince([old, missed, gm]);
      expect(since, isEmpty, reason: 'only shots with a bean set the start');
      final all = await db.select(db.shots).get();
      final from = setupSince(all);
      expect(shotNeedsDetailsSince(old, from), isFalse);
      expect(shotNeedsDetailsSince(missed, from), isTrue);
      expect(shotNeedsDetailsSince(gm, from), isFalse);
    },
  );
}
