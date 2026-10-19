import 'package:beand/database/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'support/legacy_shot_tables.dart';

void main() {
  test(
    'migration v1 -> v2 keeps beans and renames origin to country',
    () async {
      final raw = sql.sqlite3.openInMemory();
      raw.execute('''
      CREATE TABLE beans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        roaster TEXT NULL,
        roast_date INTEGER NULL,
        origin TEXT NULL,
        variety TEXT NULL,
        photo_path TEXT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', CURRENT_TIMESTAMP))
      );
    ''');
      raw.execute(legacyShotTables);
      raw.execute(
        "INSERT INTO beans (name, roaster, origin, variety) VALUES ('Guji', 'Bonanza', 'Ethiopia', 'Heirloom')",
      );
      raw.execute('PRAGMA user_version = 1');

      final db = AppDatabase(NativeDatabase.opened(raw));
      final beans = await db.select(db.beans).get();
      expect(beans, hasLength(1));
      expect(beans.single.name, 'Guji');
      expect(beans.single.country, 'Ethiopia');
      // v1 did not know the type yet: the column is added empty (since
      // schema 8 it is nullable, "no value" instead of "Single Origin").
      expect(beans.single.isBlend, isNull);
      expect(beans.single.taste, isNull);

      final added = await db.insertBean(
        BeansCompanion.insert(
          name: 'Kiambu',
          taste: const Value('blackcurrant, grapefruit'),
          cost: const Value(14.5),
        ),
      );
      expect(added.cost, 14.5);
      await db.close();
    },
  );

  test('migration v17 -> v18: emptiedAt is added, beans stay', () async {
    final raw = sql.sqlite3.openInMemory();
    // Create today's schema, then roll back to the v17 state.
    final fresh = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await fresh.insertBean(BeansCompanion.insert(name: 'Guji'));
    await fresh.close();
    raw.execute('ALTER TABLE beans DROP COLUMN emptied_at');
    raw.execute('ALTER TABLE shots DROP COLUMN grinder');
    raw.execute('ALTER TABLE shots DROP COLUMN burrs');
    raw.execute('ALTER TABLE shots DROP COLUMN brewed_with');
    raw.execute('PRAGMA user_version = 17');

    final db = AppDatabase(NativeDatabase.opened(raw));
    final bean = (await db.allBeans()).single;
    expect(bean.name, 'Guji');
    expect(bean.emptiedAt, isNull);
    await db.updateBean(
      bean.id,
      BeansCompanion(emptiedAt: Value(DateTime(2026, 10, 12))),
    );
    expect((await db.allBeans()).single.emptiedAt, DateTime(2026, 10, 12));
    await db.close();
  });

  test(
    'migration v18 -> v19: grinder and burrs are added, shots stay',
    () async {
      final raw = sql.sqlite3.openInMemory();
      final fresh = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      await fresh
          .into(fresh.shots)
          .insert(ShotsCompanion.insert(timestamp: DateTime(2026, 10, 1)));
      await fresh.close();
      raw.execute('ALTER TABLE shots DROP COLUMN grinder');
      raw.execute('ALTER TABLE shots DROP COLUMN burrs');
      raw.execute('ALTER TABLE shots DROP COLUMN brewed_with');
      raw.execute('PRAGMA user_version = 18');

      final db = AppDatabase(NativeDatabase.opened(raw));
      final shot = (await db.select(db.shots).get()).single;
      expect(shot.grinder, isNull);
      expect(shot.burrs, isNull);
      await (db.update(db.shots)..where((s) => s.id.equals(shot.id))).write(
        const ShotsCompanion(grinder: Value('Niche Zero'), burrs: Value('SSP')),
      );
      final updated = (await db.select(db.shots).get()).single;
      expect(updated.grinder, 'Niche Zero');
      expect(updated.burrs, 'SSP');
      await db.close();
    },
  );

  test('migration v19 -> v20: brewedWith is added, shots stay', () async {
    final raw = sql.sqlite3.openInMemory();
    final fresh = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await fresh
        .into(fresh.shots)
        .insert(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 1),
            grinder: const Value('Niche Zero'),
          ),
        );
    await fresh.close();
    raw.execute('ALTER TABLE shots DROP COLUMN brewed_with');
    raw.execute('PRAGMA user_version = 19');

    final db = AppDatabase(NativeDatabase.opened(raw));
    final shot = (await db.select(db.shots).get()).single;
    expect(shot.grinder, 'Niche Zero');
    expect(shot.brewedWith, isNull);
    await (db.update(db.shots)..where((s) => s.id.equals(shot.id))).write(
      const ShotsCompanion(brewedWith: Value('Niche Zero (SSP)\nIMS 18')),
    );
    expect(
      (await db.select(db.shots).get()).single.brewedWith,
      'Niche Zero (SSP)\nIMS 18',
    );
    await db.close();
  });
}
