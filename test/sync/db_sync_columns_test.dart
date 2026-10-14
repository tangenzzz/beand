import 'package:beand/database/database.dart';
import 'package:beand/database/sync_ids.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Sync columns (schema 15): every write path in AppDatabase stamps
// updatedAt/deviceId/syncState, deleting leaves tombstones, machine shots
// and profiles get deterministic IDs.

void main() {
  late AppDatabase db;
  var now = DateTime(2026, 10, 10, 12);

  // Control the database clock: each step is one minute later.
  Future<T> at<T>(Future<T> Function() body) {
    now = now.add(const Duration(minutes: 1));
    return withClock(Clock.fixed(now), body);
  }

  int ms() => now.millisecondsSinceEpoch;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory())..deviceId = 'device-a';
  });
  tearDown(() => db.close());

  Future<Shot> shot(int id) =>
      (db.select(db.shots)..where((s) => s.id.equals(id))).getSingle();
  Future<Bean> bean(int id) =>
      (db.select(db.beans)..where((b) => b.id.equals(id))).getSingle();

  group('Beans', () {
    test('create and update stamp; syncId stays', () async {
      final created = await at(
        () => db.insertBean(BeansCompanion.insert(name: 'Guji')),
      );
      expect(created.syncId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(created.updatedAt, ms());
      expect(created.deviceId, 'device-a');
      expect(created.syncState, SyncState.pending);

      db.deviceId = 'device-b';
      final changed = await at(
        () => db.updateBean(
          created.id,
          const BeansCompanion(roaster: Value('Bonanza')),
        ),
      );
      expect(changed.syncId, created.syncId);
      expect(changed.updatedAt, ms());
      expect(changed.deviceId, 'device-b');
    });

    test(
      'delete: tombstone, removed from all lists, shots stay untouched',
      () async {
        final b = await db.insertBean(BeansCompanion.insert(name: 'Kiambu'));
        final s = await at(
          () => db.insertShotWithReadings(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 10, 1),
              beanId: Value(b.id),
              rating: const Value(4),
            ),
            const [],
          ),
        );
        final before = await shot(s);
        expect(await db.countShotsOfBean(b.id), 1);
        await at(() => db.deleteBean(b.id));

        final tomb = await bean(b.id);
        expect(tomb.deleted, isTrue);
        expect(tomb.name, '');
        expect(tomb.syncId, b.syncId);
        expect(tomb.updatedAt, ms());
        expect(tomb.syncState, SyncState.pending);

        expect(await db.watchBeans().first, isEmpty);
        expect(await db.allBeans(), isEmpty);
        expect(await db.beanExists(b.id), isFalse);

        // No new stamp: otherwise the shot would overwrite the other
        // device's version on sync (data loss).
        final kept = await shot(s);
        expect(kept.updatedAt, before.updatedAt);
        expect(kept.syncState, before.syncState);
        expect(kept.rating, 4);
        final entry = await db.watchShotEntry(s).first;
        expect(entry!.bean, isNull, reason: 'tombstone counts as no bean');
        expect((await db.watchShotEntries().first).single.bean, isNull);
      },
    );
  });

  group('Shots', () {
    test('own changes stamp, backfills from the machine do not', () async {
      final id = await at(
        () => db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 1),
            externalId: const Value('abc'),
          ),
          const [],
          untouchedImport: true,
        ),
      );
      expect((await shot(id)).updatedAt, 0);

      await at(() => db.backfillProfileTemps({'abc': 92}));
      await at(() => db.backfillShotProfiles({'abc': '{}'}));
      expect((await shot(id)).updatedAt, 0, reason: 'backfill ≠ change');
      expect((await shot(id)).profileTemp, 92);

      for (final edit in <Future<void> Function()>[
        () => db.setShotRating(id, 5),
        () => db.setShotNotes(id, 'süß'),
        () => db.setShotDose(id, 18),
        () => db.setShotGrind(id, '2.5'),
        () => db.setShotBean(id, null),
        () => db.setShotTasteExtras(id, ['Erdbeere']),
        () => db.setShotAnalysis(id, json: '{}', model: 'test'),
      ]) {
        await at(edit);
        final row = await shot(id);
        expect(row.updatedAt, ms());
        expect(row.deviceId, 'device-a');
        expect(row.syncState, SyncState.pending);
      }
    });

    test(
      'machine shot: deterministic syncId; with setup it counts as a change',
      () async {
        final plain = await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 1),
            externalId: const Value('m-1'),
          ),
          const [],
          untouchedImport: true,
        );
        final withSetup = await at(
          () => db.insertShotWithReadings(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 10, 2),
              externalId: const Value('g-1'),
              machine: const Value('gaggimate'),
              doseGrams: const Value(18),
            ),
            const [],
          ),
        );
        final manual = await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 3),
            machine: const Value('pourover'),
          ),
          const [],
        );
        expect(
          (await shot(plain)).syncId,
          machineShotSyncId('meticulous', 'm-1'),
        );
        expect(
          (await shot(withSetup)).syncId,
          machineShotSyncId('gaggimate', 'g-1'),
        );
        expect((await shot(withSetup)).updatedAt, ms());
        expect(
          machineShotSyncId('meticulous', 'm-1'),
          isNot(machineShotSyncId('gaggimate', 'm-1')),
        );
        final pour = await shot(manual);
        expect(pour.syncId, isNot((await shot(plain)).syncId));
        expect(pour.updatedAt, greaterThan(0));
      },
    );

    test('delete: tombstone with stamp, without data and curve', () async {
      final id = await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 10, 1),
          rating: const Value(3),
          tasteBody: const Value(4),
          tasteExtras: const Value('Asche'),
        ),
        [(id) => ShotReadingsCompanion.insert(shotId: id, timeMs: 0)],
      );
      final syncId = (await shot(id)).syncId;
      await at(() => db.deleteShots([id]));
      final tomb = await shot(id);
      expect(tomb.deletedAt, isNotNull);
      expect(tomb.syncId, syncId);
      expect(tomb.updatedAt, ms());
      expect(tomb.rating, isNull);
      expect(tomb.tasteBody, isNull);
      expect(tomb.tasteExtras, isNull);
      expect(await db.readingsFor(id), isEmpty);

      // A tombstone can no longer be edited.
      await at(() => db.setShotRating(id, 5));
      expect((await shot(id)).rating, isNull);

      // Deleting twice no longer changes the timestamp.
      final stamped = (await shot(id)).updatedAt;
      await at(() => db.deleteShots([id]));
      expect((await shot(id)).updatedAt, stamped);
    });
  });

  group('Profiles', () {
    StoredProfilesCompanion profile(String json) =>
        StoredProfilesCompanion.insert(
          id: 'p1',
          name: 'Turbo',
          json: json,
          fetchedAt: DateTime(2026, 10, 1),
        );

    Future<StoredProfile> row() => (db.select(
      db.storedProfiles,
    )..where((p) => p.id.equals('p1'))).getSingle();

    test('new = fresh import (0), changed version = change', () async {
      await db.upsertStoredProfile(profile('{"v":1}'));
      final first = await row();
      expect(first.syncId, machineProfileSyncId('meticulous', 'p1'));
      expect(first.updatedAt, 0);
      expect(first.machine, 'meticulous');

      await at(() => db.upsertStoredProfile(profile('{"v":2}')));
      final second = await row();
      expect(second.json, '{"v":2}');
      expect(second.updatedAt, ms());
      expect(second.syncId, first.syncId);

      await at(
        () => db.setProfileCustomDescription(
          'p1',
          'mein Text',
          machine: 'meticulous',
        ),
      );
      expect((await row()).updatedAt, ms());
    });

    test(
      'forget: tombstone, invisible; if it shows up again, it comes back',
      () async {
        await db.upsertStoredProfile(profile('{"v":1}'));
        await at(() => db.deleteStoredProfile('p1', machine: 'meticulous'));
        final tomb = await row();
        expect(tomb.deleted, isTrue);
        expect(tomb.json, '');
        expect(tomb.updatedAt, ms());
        expect(await db.watchStoredProfiles().first, isEmpty);
        expect(await db.storedProfilesById(), isEmpty);
        expect(await db.storedProfileByName('Turbo'), isNull);
        expect(await db.storedProfile('p1', machine: 'meticulous'), isNull);

        await at(() => db.upsertStoredProfile(profile('{"v":1}')));
        final back = await row();
        expect(back.deleted, isFalse);
        expect(back.json, '{"v":1}');
        expect(back.syncId, tomb.syncId);
        expect(await db.watchStoredProfiles().first, hasLength(1));
      },
    );
  });

  test('syncId is unique (UNIQUE)', () async {
    final a = await db.insertBean(BeansCompanion.insert(name: 'A'));
    await expectLater(
      db.insertBean(BeansCompanion.insert(name: 'B', syncId: Value(a.syncId))),
      throwsA(anything),
    );
  });
}
