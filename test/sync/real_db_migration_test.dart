import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/database/sync_ids.dart';
import 'package:beand/sync/records/shot_codec.dart';
import 'package:beand/sync/records/sync_envelope.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// Migration of a REAL app database (copy from the phone) to the current
// schema, with a row-by-row comparison of all previously existing columns.
// Only runs on demand, so no phone data has to go into the repo:
//
//   adb exec-out run-as app.beand --user 0 \
//       cat app_flutter/coffee_app.sqlite > /tmp/copy.sqlite
//   BEAND_REAL_DB=/tmp/copy.sqlite flutter test test/sync/real_db_migration_test.dart
//
// The copy itself is not modified (the test works on another copy).

const _keys = {
  'beans': ['id'],
  'shots': ['id'],
  'shot_readings': ['id'],
  'stored_profiles': ['id', 'machine'],
};

Map<String, Map<String, Object?>> _rows(sql.Database db, String table) {
  final result = <String, Map<String, Object?>>{};
  for (final row in db.select('SELECT * FROM $table')) {
    final key = _keys[table]!.map((k) => row[k]).join('|');
    result[key] = Map.of(row);
  }
  return result;
}

void main() {
  final source = Platform.environment['BEAND_REAL_DB'];

  test('real DB: migration to the current schema loses nothing', () async {
    final dir = Directory.systemTemp.createTempSync('beand_real_db');
    final copy = File(source!).copySync('${dir.path}/db.sqlite');

    final before = sql.sqlite3.open(copy.path);
    final oldVersion = before.select('PRAGMA user_version').first.values.first;
    final old = {for (final t in _keys.keys) t: _rows(before, t)};
    before.close();

    final db = AppDatabase(NativeDatabase(copy));
    await db.customSelect('SELECT 1').get(); // trigger the migration
    await db.close();

    final after = sql.sqlite3.open(copy.path);
    expect(after.select('PRAGMA user_version').first.values.first, 18);
    expect(
      after.select(
        "SELECT 1 FROM pragma_table_info('beans') WHERE name = 'photo_blob'",
      ),
      hasLength(1),
    );
    expect(
      after.select(
        "SELECT 1 FROM pragma_table_info('beans') WHERE name = 'emptied_at'",
      ),
      hasLength(1),
    );
    expect(
      after.select(
        "SELECT 1 FROM sqlite_master WHERE name = 'synced_settings'",
      ),
      hasLength(1),
    );
    expect(after.select('PRAGMA integrity_check').first.values.first, 'ok');
    expect(after.select('PRAGMA foreign_key_check'), isEmpty);

    for (final table in _keys.keys) {
      final now = _rows(after, table);
      expect(now.keys.toSet(), old[table]!.keys.toSet(), reason: table);
      for (final entry in old[table]!.entries) {
        final row = now[entry.key]!;
        for (final column in entry.value.entries) {
          expect(
            row[column.key],
            column.value,
            reason: '$table ${entry.key} ${column.key}',
          );
        }
      }
    }

    for (final table in ['beans', 'shots', 'stored_profiles']) {
      final ids = after.select('SELECT sync_id FROM $table');
      final set = {for (final r in ids) r['sync_id'] as String};
      expect(set, hasLength(ids.length), reason: '$table: syncId unique');
      // Only when jumping across schema 15: after that there are already
      // real sync states and fresh imports with updatedAt 0.
      if ((oldVersion as int) < 15) {
        expect(
          after.select(
            "SELECT 1 FROM $table WHERE sync_state != 'pending' "
            'OR updated_at <= 0',
          ),
          isEmpty,
          reason:
              '$table: everything awaits upload, nothing counts as untouched',
        );
      }
    }
    for (final r in after.select(
      'SELECT machine, external_id, sync_id FROM shots '
      'WHERE external_id IS NOT NULL',
    )) {
      expect(
        r['sync_id'],
        machineShotSyncId(r['machine'] as String, r['external_id'] as String),
      );
    }
    for (final r in after.select(
      'SELECT id, machine, sync_id FROM stored_profiles',
    )) {
      expect(
        r['sync_id'],
        machineProfileSyncId(r['machine'] as String, r['id'] as String),
      );
    }
    // The duplicate protection on import survives the table rebuild.
    expect(
      after.select(
        "SELECT 1 FROM sqlite_master WHERE name = 'shots_external_id'",
      ),
      hasLength(1),
    );
    final counts = {for (final t in _keys.keys) t: old[t]!.length};
    // ignore: avoid_print
    print('Migrated from v$oldVersion: $counts');
    after.close();

    // How large do the real shots get as sync records?
    final db2 = AppDatabase(NativeDatabase(copy));
    final beanIds = await db2.syncDao.beanSyncIds();
    final sizes = <int>[];
    for (final s in await db2.select(db2.shots).get()) {
      final envelope = SyncEnvelope(
        type: shotType,
        id: s.syncId,
        updatedAt: s.updatedAt,
        deviceId: 'x',
        deleted: s.deletedAt != null,
        data: shotToSyncData(
          s,
          beanSyncId: beanIds[s.beanId],
          readings: await db2.syncDao.readingsFor(s.id),
        ),
      );
      sizes.add(envelope.encode().length);
    }
    await db2.close();
    sizes.sort();
    // ignore: avoid_print
    print(
      'Shot envelopes: ${sizes.length}, median ${sizes[sizes.length ~/ 2]} B, '
      'largest ${sizes.last} B, over $maxInlineEnvelopeBytes B: '
      '${sizes.where((x) => x > maxInlineEnvelopeBytes).length}',
    );
    expect(sizes.where((x) => x > maxInlineEnvelopeBytes), isEmpty);
    dir.deleteSync(recursive: true);
  }, skip: source == null ? 'BEAND_REAL_DB not set' : false);
}
