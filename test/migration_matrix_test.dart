import 'package:beand/database/database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const introduced = <String, Map<String, int>>{
  'beans': {
    'is_blend': 2,
    'processing': 2,
    'weight_grams': 2,
    'taste': 2,
    'cost': 2,
    'producer': 3,
    'is_frozen': 3,
    'thawed_date': 3,
    'roasted_for': 8,
    'sync_id': 15,
    'updated_at': 15,
    'device_id': 15,
    'sync_state': 15,
    'deleted': 15,
    'photo_blob': 17,
    'emptied_at': 18,
    'roast_level': 22,
    'frozen_date': 27,
    'frozen_days': 27,
    'region': 28,
    'altitude': 28,
    'coffee_id': 28,
    'opened_at': 28,
  },
  'shots': {
    'external_id': 4,
    'machine': 4,
    'profile_color': 4,
    'profile_image_path': 4,
    'brew_temp': 4,
    'profile_temp': 5,
    'deleted_at': 5,
    'taste_finish': 9,
    'taste_body': 9,
    'taste_acidity': 9,
    'taste_sweetness': 9,
    'taste_hollow': 9,
    'taste_salty': 9,
    'taste_astringent': 9,
    'taste_bitter': 9,
    'taste_extras': 10,
    'ai_analysis': 12,
    'ai_analysis_model': 12,
    'ai_analysed_at': 12,
    'profile_json': 13,
    'stage_exits': 14,
    'sync_id': 15,
    'updated_at': 15,
    'device_id': 15,
    'sync_state': 15,
    'grinder': 19,
    'burrs': 19,
    'brewed_with': 20,
    'brew_chain_id': 21,
    'grind_zero': 23,
    'grind_marker': 24,
    'beverage_grams': 26,
  },
  'shot_readings': {'stage': 4, 'temp_mix': 25, 'temp_goal': 25},
  'stored_profiles': {
    'custom_description': 7,
    'custom_image_path': 7,
    'machine': 11,
    'sync_id': 15,
    'updated_at': 15,
    'device_id': 15,
    'sync_state': 15,
    'deleted': 15,
    'custom_image_blob': 17,
  },
};

// Old schemas rebuilt from the CREATE statements of a fresh database: columns
// are removed according to the historical steps, old constraints set by hand.
// They stand in for real old installations, which this does not replace.
List<String> splitColumns(String text) {
  final result = <String>[];
  var depth = 0;
  String? quote;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quote != null) {
      if (c == quote) {
        if (i + 1 < text.length && text[i + 1] == quote) {
          i++;
        } else {
          quote = null;
        }
      }
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
    } else if (c == ',' && depth == 0) {
      result.add(text.substring(start, i).trim());
      start = i + 1;
    }
  }
  result.add(text.substring(start).trim());
  return result;
}

sql.Database oldDatabase(int version, Map<String, String> schema) {
  final raw = sql.sqlite3.openInMemory();
  for (final entry in schema.entries) {
    final table = entry.key;
    if (table == 'stored_profiles' && version < 6) continue;
    if (table == 'synced_settings' && version < 16) continue;
    final statement = entry.value;
    final begin = statement.indexOf('(');
    final parts = splitColumns(
      statement.substring(begin + 1, statement.lastIndexOf(')')),
    );
    final kept = <String>[];
    for (var part in parts) {
      final column = RegExp(r'^"([^"]+)"').firstMatch(part)?.group(1);
      if (column != null) {
        if ((introduced[table]?[column] ?? 1) > version) continue;
        if (table == 'beans' && column == 'variety' && version == 2) continue;
        if (table == 'beans' && column == 'country' && version == 1) {
          part = part.replaceFirst('"country"', '"origin"');
        }
        if (table == 'beans' && column == 'is_blend' && version < 8) {
          part = part.replaceFirst(
            'INTEGER NULL',
            'INTEGER NOT NULL DEFAULT 0',
          );
        }
      } else if (table == 'stored_profiles' &&
          version < 11 &&
          part.startsWith('PRIMARY KEY')) {
        part = 'PRIMARY KEY ("id")';
      }
      kept.add(part);
    }
    raw.execute('${statement.substring(0, begin + 1)}${kept.join(', ')})');
  }
  if (version >= 4) {
    raw.execute(
      'CREATE INDEX shot_readings_shot_id ON shot_readings (shot_id)',
    );
    raw.execute('CREATE UNIQUE INDEX shots_external_id ON shots (external_id)');
  }
  for (final table in schema.keys) {
    final columns = raw.select('PRAGMA table_info("$table")');
    if (columns.isEmpty) continue;
    final names = <String>[];
    final values = <Object?>[];
    for (final c in columns) {
      final name = c['name'] as String;
      names.add('"$name"');
      Object value = switch (c['type']) {
        'INTEGER' => 1,
        'REAL' => 2.5,
        _ => '$table-$name-v$version',
      };
      if (name == 'id' && c['type'] == 'INTEGER' ||
          name == 'bean_id' ||
          name == 'shot_id') {
        value = 7;
      }
      if (name == 'machine') value = 'meticulous';
      if (name == 'sync_state') value = SyncState.synced;
      if (name == 'json') value = '{}';
      values.add(value);
    }
    raw.execute(
      'INSERT INTO "$table" (${names.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
      values,
    );
  }
  raw.execute('PRAGMA user_version=$version');
  return raw;
}

Map<String, Object?> schemaShape(sql.Database raw, List<String> tables) => {
  for (final table in tables)
    table: {
      'columns': {
        for (final c in raw.select('PRAGMA table_info("$table")'))
          c['name']: {
            for (final key in ['type', 'notnull', 'dflt_value', 'pk'])
              key: c[key],
          },
      },
      'indexes': [
        for (final index in raw.select('PRAGMA index_list("$table")'))
          '${index['unique']}:${index['partial']}:${raw.select('PRAGMA index_info("${index['name']}")').map((c) => c['name']).join(',')}',
      ]..sort(),
      'references': [
        for (final fk in raw.select('PRAGMA foreign_key_list("$table")'))
          '${fk['table']}:${fk['from']}:${fk['to']}:${fk['on_update']}:${fk['on_delete']}',
      ]..sort(),
    },
};

class InterruptedMigration extends AppDatabase {
  InterruptedMigration(super.executor);
  @override
  Future<void> customStatement(String statement, [List<dynamic>? args]) {
    if (statement.contains('ADD COLUMN') && statement.contains('burrs')) {
      throw const FileSystemFailure();
    }
    return super.customStatement(statement, args);
  }
}

class FileSystemFailure implements Exception {
  const FileSystemFailure();
  @override
  String toString() => 'Injected write failure before ADD COLUMN burrs';
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Map<String, String> freshSql;
  late Map<String, Object?> expectedSchema;
  setUpAll(() async {
    final raw = sql.sqlite3.openInMemory();
    final db = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await db.customSelect('SELECT 1').get();
    freshSql = {
      for (final r in raw.select(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      ))
        r['name'] as String: r['sql'] as String,
    };
    expectedSchema = schemaShape(raw, freshSql.keys.toList());
    await db.close();
    raw.close();
  });

  for (var version = 1; version <= 27; version++) {
    test(
      'schema $version upgrades to the current schema and keeps all values',
      () async {
        final raw = oldDatabase(version, freshSql);
        final before = <String, List<Map<String, Object?>>>{};
        for (final table in freshSql.keys) {
          if (raw.select('PRAGMA table_info("$table")').isEmpty) continue;
          before[table] = raw
              .select('SELECT * FROM "$table"')
              .map((r) => Map<String, Object?>.from(r))
              .toList();
        }
        final db = AppDatabase(
          NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
        );
        addTearDown(() async {
          await db.close();
          raw.close();
        });
        await db.customSelect('SELECT 1').get();
        expect(raw.select('PRAGMA user_version').first.values.single, 28);
        expect(schemaShape(raw, freshSql.keys.toList()), expectedSchema);
        expect(raw.select('PRAGMA integrity_check').first.values.single, 'ok');
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
        for (final table in before.entries) {
          final after = raw.select('SELECT * FROM "${table.key}"');
          expect(after.length, table.value.length);
          for (var i = 0; i < after.length; i++) {
            for (final column in table.value[i].entries) {
              final name = table.key == 'beans' && column.key == 'origin'
                  ? 'country'
                  : column.key;
              // Schema 1 only existed before the app was public; its unused
              // variety column was dropped in schema 2.
              if (version == 1 && column.key == 'variety') continue;
              expect(
                after[i][name],
                column.value,
                reason: 'v$version: ${table.key}.$name',
              );
            }
          }
        }
      },
    );
  }

  test('an upgrade that breaks off can run again at the next start', () async {
    final raw = oldDatabase(18, freshSql);
    final broken = InterruptedMigration(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await expectLater(
      broken.customSelect('SELECT 1').get(),
      throwsA(isA<FileSystemFailure>()),
    );
    await broken.close();
    expect(raw.select('PRAGMA user_version').first.values.single, 18);
    expect(
      raw.select('PRAGMA table_info(shots)').any((r) => r['name'] == 'grinder'),
      isFalse,
    );
    final retry = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    Object? failure;
    try {
      await retry.customSelect('SELECT 1').get();
    } catch (e) {
      failure = e;
    }
    await retry.close();
    raw.close();
    expect(failure, isNull);
  });

  test(
    'a database from a newer version is refused and left as it is',
    () async {
      final raw = oldDatabase(28, freshSql);
      raw.execute('ALTER TABLE beans ADD COLUMN future_v29 TEXT');
      raw.execute('PRAGMA user_version=29');
      final db = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      Object? failure;
      try {
        await db.customSelect('SELECT 1').get();
      } catch (e) {
        failure = e;
      }
      expect(failure, isA<DatabaseTooNewException>());
      final after = raw.select('PRAGMA user_version').first.values.single;
      await db.close();
      raw.close();
      expect(after, 29);
    },
  );
}
