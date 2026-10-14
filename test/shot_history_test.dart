import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/models/history_import.dart';
import 'package:beand/models/shot_phases.dart';
import 'package:beand/screens/history/history_logic.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'support/legacy_shot_tables.dart';

Map<String, dynamic> _fixture() => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/history_entry_bailey.json').readAsStringSync())
      as Map,
);

ShotEntry _entry(
  int id,
  DateTime at, {
  String machine = 'meticulous',
  String? profile,
  int? rating,
  int? beanId,
  Bean? bean,
  String? notes,
}) => ShotEntry(
  Shot(
    syncId: 'test',
    updatedAt: 0,
    syncState: SyncState.pending,
    id: id,
    timestamp: at,
    beanId: beanId,
    profileName: profile,
    rating: rating,
    notes: notes,
    createdAt: at,
    machine: machine,
  ),
  bean,
);

Bean _bean(int id, String name, String roaster) => Bean(
  syncId: 'test',
  updatedAt: 0,
  syncState: SyncState.pending,
  deleted: false,
  id: id,
  name: name,
  roaster: roaster,
  isBlend: false,
  isFrozen: false,
  createdAt: DateTime(2026),
);

void main() {
  group('parseHistoryEntry (real shot from the machine)', () {
    test('reads ID, time, profile, weight, duration without retraction and temperature', () {
      final parsed = parseHistoryEntry(_fixture())!;
      expect(parsed.externalId, 'c638dc37-dc02-4f63-ab03-92001c201757');
      expect(parsed.timestamp.millisecondsSinceEpoch, 1789914283236);
      expect(parsed.profileName, 'Bailey - PSPH / Soup');
      expect(parsed.profileColor, startsWith('#'));
      expect(parsed.profileImageApiPath, startsWith('/api/v1/profile/image/'));
      // Final weight = last data point (it keeps dripping during retraction).
      expect(parsed.finalWeight, closeTo(51.48, 0.3));
      // Duration ends before "retracting" (~14 s), not at the last data
      // point (~19 s).
      expect(parsed.durationMs, inInclusiveRange(12000, 16000));
      // Mean of the bar sensors, clearly below the profile target 87.5 °C.
      expect(parsed.brewTemp, inInclusiveRange(75, 90));
      // The profile's target temperature is displayed.
      expect(parsed.profileTemp, 87.5);
      expect(parsed.readings, hasLength(40));
    });

    test('unusable entries yield null', () {
      expect(parseHistoryEntry({'id': 'x', 'time': 1.0, 'data': []}), isNull);
      expect(
        parseHistoryEntry({
          'time': 1.0,
          'data': [{}],
        }),
        isNull,
      );
      expect(
        parseHistoryEntry({
          'id': 'x',
          'data': [{}],
        }),
        isNull,
      );
    });

    test('readings contain stage, pressure, flow and weight', () async {
      final parsed = parseHistoryEntry(_fixture())!;
      final db = AppDatabase(NativeDatabase.memory());
      final id = await db.insertShotWithReadings(
        ShotsCompanion.insert(timestamp: parsed.timestamp),
        parsed.readings,
      );
      final readings = await db.readingsFor(id);
      expect(readings, hasLength(40));
      expect(readings.first.stage, 'Initial Saturation');
      expect(readings.last.stage, 'retracting');
      // Flow-controlled profile: the actual pressure stays below 1 bar.
      expect(
        readings.map((r) => r.pressure!).reduce((a, b) => a > b ? a : b),
        closeTo(0.89, 0.2),
      );
      expect(readings.any((r) => r.flow != null && r.flow! > 3), isTrue);
      expect(readings.last.weight!, greaterThan(40));
      expect(
        readings.map((r) => r.timeMs),
        orderedEquals([...readings.map((r) => r.timeMs)]..sort()),
      );
      await db.close();
    });
  });

  group('computePhases', () {
    test(
      'groups data points into phases, retraction at the end in gray',
      () async {
        final parsed = parseHistoryEntry(_fixture())!;
        final db = AppDatabase(NativeDatabase.memory());
        final id = await db.insertShotWithReadings(
          ShotsCompanion.insert(timestamp: parsed.timestamp),
          parsed.readings,
        );
        final phases = computePhases(await db.readingsFor(id));
        expect(phases.map((p) => p.name), [
          'Initial Saturation',
          'Puck Saturation',
          'Percolation Ramp',
          'Percolation',
          'Retraction',
        ]);
        expect(phases.first.startMs, lessThan(1000));
        // Without gaps: each phase starts where the previous one ends.
        for (var i = 1; i < phases.length; i++) {
          expect(phases[i].startMs, phases[i - 1].endMs);
        }
        expect(phases.last.isRetraction, isTrue);
        expect(phases.last.color, retractionColor);
        expect(phases.first.color, phasePalette[0]);
        expect(phases[3].color, phasePalette[3]);
        expect(phaseAt(phases, phases[3].startMs + 10)!.name, 'Percolation');
        await db.close();
      },
    );

    test('without stage names (legacy data) no phases', () {
      expect(computePhases(const []), isEmpty);
    });
  });

  group('migration v3 -> v4', () {
    test('keeps beans and shots, new columns have default values', () async {
      final raw = sql.sqlite3.openInMemory();
      raw.execute('''
        CREATE TABLE beans (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, roaster TEXT NULL,
          roast_date INTEGER NULL, is_blend INTEGER NOT NULL DEFAULT 0, country TEXT NULL,
          processing TEXT NULL, variety TEXT NULL, producer TEXT NULL, weight_grams REAL NULL,
          taste TEXT NULL, cost REAL NULL, photo_path TEXT NULL,
          is_frozen INTEGER NOT NULL DEFAULT 0, thawed_date INTEGER NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', CURRENT_TIMESTAMP))
        );
      ''');
      raw.execute(legacyShotTables);
      raw.execute(
        "INSERT INTO beans (name, roaster) VALUES ('Guji', 'La Cabra')",
      );
      raw.execute(
        "INSERT INTO shots (timestamp, bean_id, profile_name, rating) VALUES (1780000000, 1, 'Soup', 4)",
      );
      raw.execute(
        'INSERT INTO shot_readings (shot_id, time_ms, pressure) VALUES (1, 100, 3.5)',
      );
      raw.execute('PRAGMA user_version = 3');

      final db = AppDatabase(NativeDatabase.opened(raw));
      final beans = await db.select(db.beans).get();
      expect(beans.single.name, 'Guji');
      final shots = await db.select(db.shots).get();
      expect(shots.single.rating, 4);
      expect(shots.single.machine, 'meticulous');
      expect(shots.single.externalId, isNull);
      expect(shots.single.brewTemp, isNull);
      expect(shots.single.profileTemp, isNull);
      expect(shots.single.deletedAt, isNull);
      // Schema v6: table for stored profiles exists and is empty.
      expect(await db.select(db.storedProfiles).get(), isEmpty);
      final readings = await db.readingsFor(1);
      expect(readings.single.pressure, 3.5);
      expect(readings.single.stage, isNull);

      // New: import + unique externalId.
      final parsed = parseHistoryEntry(_fixture())!;
      await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: parsed.timestamp,
          externalId: Value(parsed.externalId),
        ),
        parsed.readings,
      );
      expect(await db.knownExternalIds(), {parsed.externalId});
      await expectLater(
        db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: parsed.timestamp,
            externalId: Value(parsed.externalId),
          ),
          parsed.readings,
        ),
        throwsA(anything),
      );
      await db.close();
    });
  });

  group('migration v6 -> v7', () {
    test('profiles keep their data; custom description/photo are empty and not overwritten by sync', () async {
      final raw = sql.sqlite3.openInMemory();
      raw.execute('''
        CREATE TABLE stored_profiles (
          id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, json TEXT NOT NULL,
          image_path TEXT NULL, position INTEGER NOT NULL DEFAULT 0, fetched_at INTEGER NOT NULL
        );
      ''');
      // Bean and shot tables belong in a v6 database too — the migration to
      // v8 touches the beans, the one to v9 the shots.
      raw.execute(legacyBeansTable);
      raw.execute(legacyShotTables);
      raw.execute(legacyShotColumnsV5);
      raw.execute(
        "INSERT INTO stored_profiles (id, name, json, position, fetched_at) VALUES ('p1', 'Turbo', '{}', 2, 1780000000)",
      );
      raw.execute('PRAGMA user_version = 6');

      final db = AppDatabase(NativeDatabase.opened(raw));
      var profile = (await db.storedProfilesById())['p1']!;
      expect(profile.name, 'Turbo');
      expect(profile.position, 2);
      expect(profile.customDescription, isNull);
      expect(profile.customImagePath, isNull);

      await db.setProfileCustomDescription(
        'p1',
        '  my text ',
        machine: 'meticulous',
      );
      await db.setProfileCustomImage('p1', '/x/y.jpg', machine: 'meticulous');
      // A sync (upsert without the custom fields) leaves them alone.
      await db.upsertStoredProfile(
        StoredProfilesCompanion(
          id: const Value('p1'),
          name: const Value('Turbo'),
          json: const Value('{"x":1}'),
          position: const Value(0),
          fetchedAt: Value(DateTime(2026, 9, 21)),
        ),
      );
      profile = (await db.storedProfilesById())['p1']!;
      expect(profile.json, '{"x":1}');
      expect(profile.customDescription, 'my text');
      expect(profile.customImagePath, '/x/y.jpg');
      await db.setProfileCustomDescription('p1', '   ', machine: 'meticulous');
      expect((await db.storedProfilesById())['p1']!.customDescription, isNull);
      await db.close();
    });
  });

  group('rating and notes', () {
    test('set stars, 0 clears; empty note becomes null', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final id = await db.insertShotWithReadings(
        ShotsCompanion.insert(timestamp: DateTime(2026, 9, 21)),
        const [],
      );
      await db.setShotRating(id, 4);
      await db.setShotNotes(id, '  Sweet, a bit sour ');
      var shot = (await db.watchShotEntry(id).first)!.shot;
      expect(shot.rating, 4);
      expect(shot.notes, contains('Sweet'));
      await db.setShotRating(id, 0);
      await db.setShotNotes(id, '   ');
      shot = (await db.watchShotEntry(id).first)!.shot;
      expect(shot.rating, isNull);
      expect(shot.notes, isNull);
      await db.close();
    });
  });

  group('deleting shots', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> imported(String externalId) async {
      final parsed = parseHistoryEntry(_fixture())!;
      return db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: parsed.timestamp,
          externalId: Value(externalId),
          rating: const Value(4),
          notes: const Value('keep?'),
        ),
        parsed.readings,
      );
    }

    test(
      'imported shot disappears from the list, tombstone prevents re-import',
      () async {
        final id = await imported('machine-1');
        final other = await imported('machine-2');
        await db.deleteShots([id]);

        final visible = await db.watchShotEntries().first;
        expect(visible.map((e) => e.shot.id), [other]);
        expect(await db.watchShotEntry(id).first, isNull);
        expect(await db.readingsFor(id), isEmpty);
        // Tombstone stays, without personal data.
        expect(await db.knownExternalIds(), {'machine-1', 'machine-2'});
        final tomb = await (db.select(
          db.shots,
        )..where((s) => s.id.equals(id))).getSingle();
        expect(tomb.deletedAt, isNotNull);
        expect(tomb.rating, isNull);
        expect(tomb.notes, isNull);
        // Editing a tombstone changes nothing (e.g. a late note save).
        await db.setShotNotes(id, 'late');
        await db.setShotRating(id, 5);
        final again = await (db.select(
          db.shots,
        )..where((s) => s.id.equals(id))).getSingle();
        expect(again.notes, isNull);
        expect(again.rating, isNull);
        // The other one stays untouched.
        expect(visible.single.shot.rating, 4);
        expect(await db.readingsFor(other), isNotEmpty);
      },
    );

    test('a shot without a machine ID also stays as a tombstone (sync); several at once', () async {
      final manual = await db.insertShotWithReadings(
        ShotsCompanion.insert(timestamp: DateTime(2026, 9, 21)),
        const [],
      );
      final a = await imported('a');
      final b = await imported('b');
      await db.deleteShots([manual, a, b]);
      expect(await db.watchShotEntries().first, isEmpty);
      expect(
        await db.select(db.shots).get(),
        hasLength(3),
        reason: 'three tombstones — the deletion must reach other devices',
      );
      final rows = await db.select(db.shots).get();
      expect(rows.every((s) => s.deletedAt != null), isTrue);
      expect(rows.every((s) => s.syncState == SyncState.pending), isTrue);
      expect(await db.readingsFor(manual), isEmpty);
      await db.deleteShots(const []); // empty is fine
    });

    test(
      'target temperature is backfilled for known shots, existing ones stay',
      () async {
        final without = await imported('old');
        final withTemp = await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 9, 21),
            externalId: const Value('new'),
            profileTemp: const Value(93),
          ),
          const [],
        );
        await db.backfillProfileTemps({'old': 87.5, 'new': 50, 'unknown': 10});
        Future<double?> temp(int id) async => (await (db.select(
          db.shots,
        )..where((s) => s.id.equals(id))).getSingle()).profileTemp;
        expect(await temp(without), 87.5);
        expect(await temp(withTemp), 93);
      },
    );
  });

  group('grouping and formatting', () {
    final now = DateTime(2026, 9, 21, 12);

    test('day headings', () {
      expect(dayGroupLabel(DateTime(2026, 9, 21, 8), now), 'TODAY');
      expect(dayGroupLabel(DateTime(2026, 9, 20, 23, 59), now), 'YESTERDAY');
      expect(dayGroupLabel(DateTime(2026, 9, 19, 9), now), 'SAT · 19 SEP');
      expect(dayGroupLabel(DateTime(2025, 12, 31), now), 'WED · 31 DEC 2025');
    });

    test('groupShotsByDay keeps order and separates days', () {
      final groups = groupShotsByDay([
        _entry(4, DateTime(2026, 9, 21, 8)),
        _entry(3, DateTime(2026, 9, 20, 17)),
        _entry(2, DateTime(2026, 9, 20, 8)),
        _entry(1, DateTime(2026, 9, 19, 9)),
      ], now);
      expect(groups.map((g) => g.label), [
        'TODAY',
        'YESTERDAY',
        'SAT · 19 SEP',
      ]);
      expect(groups[1].entries.map((e) => e.shot.id), [3, 2]);
    });

    test('number format', () {
      expect(grams(18), '18');
      expect(grams(17.5), '17.5');
      expect(grams(38.43), '38.4');
      expect(seconds(34040), '34.0');
    });
  });

  group('search and filter', () {
    final now = DateTime(2026, 9, 21, 12);
    final guji = _bean(1, 'Guji Natural', 'La Cabra');
    final kiambu = _bean(2, 'Kiambu AA', 'Friedhats');
    final entries = [
      _entry(
        1,
        DateTime(2026, 9, 21, 8),
        profile: "Damian's LRv2",
        rating: 4,
        beanId: 1,
        bean: guji,
      ),
      _entry(
        2,
        DateTime(2026, 9, 20, 17),
        profile: 'V60',
        machine: 'pourover',
        rating: 5,
        beanId: 2,
        bean: kiambu,
      ),
      _entry(
        3,
        DateTime(2026, 9, 10, 8),
        profile: 'Soup',
        rating: 2,
        beanId: 1,
        bean: guji,
        notes: 'too sour',
      ),
      _entry(4, DateTime(2026, 8, 1, 8), profile: 'Soup'),
    ];

    List<int> ids(String q, HistoryFilter f) => filterShots(
      entries,
      query: q,
      filter: f,
      now: now,
    ).map((e) => e.shot.id).toList();

    test(
      'everything without search/filter',
      () => expect(ids('', HistoryFilter.empty), [1, 2, 3, 4]),
    );

    test('free text searches bean, roaster, profile, note and machine', () {
      expect(ids('cabra', HistoryFilter.empty), [1, 3]);
      expect(ids('soup', HistoryFilter.empty), [3, 4]);
      expect(ids('SOUR', HistoryFilter.empty), [3]);
      expect(ids('pour over', HistoryFilter.empty), [2]);
    });

    test('filter fields: OR within, AND between fields', () {
      expect(ids('', const HistoryFilter(machines: {'pourover'})), [2]);
      expect(ids('', const HistoryFilter(beanIds: {1})), [1, 3]);
      expect(
        ids('', const HistoryFilter(roasters: {'friedhats', 'la cabra'})),
        [1, 2, 3],
      );
      expect(ids('', const HistoryFilter(profiles: {'Soup'})), [3, 4]);
      expect(ids('', const HistoryFilter(beanIds: {1}, profiles: {'Soup'})), [
        3,
      ]);
    });

    test('minimum rating: unrated ones drop out', () {
      expect(ids('', const HistoryFilter(minRating: 4)), [1, 2]);
      expect(ids('', const HistoryFilter(minRating: 5)), [2]);
    });

    test('time range', () {
      expect(ids('', const HistoryFilter(dateRange: HistoryDateRange.today)), [
        1,
      ]);
      expect(ids('', const HistoryFilter(dateRange: HistoryDateRange.week)), [
        1,
        2,
      ]);
      expect(ids('', const HistoryFilter(dateRange: HistoryDateRange.month)), [
        1,
        2,
        3,
      ]);
      expect(
        ids(
          '',
          HistoryFilter(
            dateRange: HistoryDateRange.custom,
            customRange: DateTimeRange(
              start: DateTime(2026, 9, 10),
              end: DateTime(2026, 9, 20),
            ),
          ),
        ),
        [2, 3],
      );
    });

    test('activeCount and options', () {
      expect(const HistoryFilter(minRating: 3, beanIds: {1}).activeCount, 2);
      final options = HistoryFilterOptions(
        entries,
        enabledMachines: const [ShotMachine.meticulous, ShotMachine.pourOver],
      );
      expect(options.machines, [ShotMachine.meticulous, ShotMachine.pourOver]);
      expect(options.beans.map((b) => b.name), ['Guji Natural', 'Kiambu AA']);
      expect(options.roasters, ['Friedhats', 'La Cabra']);
      expect(options.profiles, ["Damian's LRv2", 'Soup', 'V60']);
    });
  });
}
