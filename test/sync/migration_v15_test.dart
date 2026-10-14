import 'package:beand/database/database.dart';
import 'package:beand/database/sync_ids.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import '../support/schema_v14.dart';

// Migration 14 → 15 (sync columns) on a reconstructed v14 database.
// With a real copy from a device: real_db_migration_test.dart.

void main() {
  test('v14 -> v17: everything stays, every row gets syncId + stamp', () async {
    final raw = sql.sqlite3.openInMemory();
    for (final statement in schemaV14) {
      raw.execute(statement);
    }
    raw.execute('''
      INSERT INTO beans (id, name, is_frozen) VALUES (1, 'Guji', 0), (2, 'Kiambu', 0);
      INSERT INTO shots (id, timestamp, bean_id, rating, external_id, machine)
        VALUES (1, 1790000000, 1, 4, 'm-1', 'meticulous'),
               (2, 1790000100, NULL, NULL, 'g-7', 'gaggimate'),
               (3, 1790000200, 2, 5, NULL, 'pourover');
      INSERT INTO shots (id, timestamp, external_id, deleted_at)
        VALUES (4, 1790000300, 'm-2', 1790000400);
      INSERT INTO shot_readings (shot_id, time_ms, pressure) VALUES (1, 0, 1.5), (1, 100, 9.0);
      INSERT INTO stored_profiles (id, machine, name, json, position, fetched_at)
        VALUES ('p1', 'meticulous', 'Turbo', '{}', 0, 1790000000),
               ('p1', 'gaggimate', 'Turbo', '{}', 0, 1790000000);
    ''');
    raw.execute('PRAGMA user_version = 14');

    final migratedAt = DateTime(2026, 10, 10, 18);
    final db = AppDatabase(NativeDatabase.opened(raw));
    final beans = await withClock(
      Clock.fixed(migratedAt),
      () => db.select(db.beans).get(),
    );
    final shots = await db.select(db.shots).get();
    final profiles = await db.select(db.storedProfiles).get();

    expect(beans.map((b) => b.name), ['Guji', 'Kiambu']);
    expect(shots, hasLength(4));
    expect(await db.readingsFor(1), hasLength(2));
    expect(profiles, hasLength(2));

    final all = [
      for (final b in beans) (b.syncId, b.updatedAt, b.syncState),
      for (final s in shots) (s.syncId, s.updatedAt, s.syncState),
      for (final p in profiles) (p.syncId, p.updatedAt, p.syncState),
    ];
    expect({for (final r in all) r.$1}, hasLength(all.length));
    for (final r in all) {
      expect(r.$2, migratedAt.millisecondsSinceEpoch);
      expect(r.$3, SyncState.pending);
    }
    expect(beans.every((b) => !b.deleted), isTrue);
    expect(profiles.every((p) => !p.deleted), isTrue);

    Shot byId(int id) => shots.firstWhere((s) => s.id == id);
    expect(byId(1).syncId, machineShotSyncId('meticulous', 'm-1'));
    expect(byId(2).syncId, machineShotSyncId('gaggimate', 'g-7'));
    expect(byId(4).syncId, machineShotSyncId('meticulous', 'm-2'));
    expect(byId(4).deletedAt, isNotNull);
    expect(
      byId(3).syncId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(byId(1).rating, 4);
    expect(byId(1).beanId, 1);
    for (final p in profiles) {
      expect(p.syncId, machineProfileSyncId(p.machine, p.id));
    }

    // The duplicate guard for machine shots still applies.
    expect(await db.knownExternalIds(), {'m-1', 'g-7', 'm-2'});
    await expectLater(
      db.customStatement(
        "INSERT INTO shots (timestamp, external_id, sync_id, updated_at) "
        "VALUES (1, 'm-1', 'x', 1)",
      ),
      throwsA(anything),
    );
    await db.close();
  });
}
