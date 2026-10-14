import 'dart:convert';

import 'package:beand/database/database.dart';
import 'package:beand/database/sync_ids.dart';
import 'package:beand/models/taste_profile.dart';
import 'package:beand/sync/crypto/bytes.dart';
import 'package:beand/sync/crypto/nip44.dart';
import 'package:beand/sync/engine/sync_engine.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/relay_pool.dart';
import 'package:beand/sync/records/setting_codec.dart';
import 'package:beand/sync/records/sync_envelope.dart';
import 'package:beand/services/app_settings.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_relay.dart';

// Shots including curve, profiles and settings between two simulated
// devices.

var now = DateTime(2026, 10, 10, 12);

Future<T> at<T>(Future<T> Function() body) {
  now = now.add(const Duration(minutes: 1));
  return withClock(Clock.fixed(now), body);
}

class MapSettingsStore implements SettingsStore {
  final values = <String, Object>{};
  @override
  Object? get(String key) => values[key];
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<void> set(String key, Object value) async => values[key] = value;
}

class Device {
  Device(this.name, this.identity, String relayUrl)
    : db = AppDatabase(NativeDatabase.memory())..deviceId = name {
    pool = RelayPool(identity: identity, timeout: const Duration(seconds: 5))
      ..setUrls([relayUrl]);
    engine = SyncEngine(
      // Counts events — device presence is tested in presence_test.dart.
      devicePresence: false,
      db: db,
      identity: identity,
      pool: pool,
      deviceId: name,
      stateStore: state,
      settings: SettingsBridge(
        prefs: () async => prefs,
        reload: () async => reloads++,
      ),
      now: () => now,
    );
  }

  final String name;
  final SyncIdentity identity;
  final AppDatabase db;
  final state = InMemorySyncStateStore();
  final prefs = MapSettingsStore();
  var reloads = 0;
  late final RelayPool pool;
  late final SyncEngine engine;

  Future<SyncReport> sync() => at(() => engine.run(force: true));

  Future<List<ShotEntry>> shots() => db.watchShotEntries().first;

  Future<void> close() async {
    await pool.closeAll();
    await db.close();
  }
}

List<ShotReadingsCompanion Function(int)> curve(int n) => [
  for (var i = 0; i < n; i++)
    (id) => ShotReadingsCompanion.insert(
      shotId: id,
      timeMs: i * 100,
      pressure: Value(i / 10),
      flow: Value(i % 7 / 3),
      weight: Value(i * 0.2),
      stage: Value(i < n / 2 ? 'Preinfusion' : 'Extraction'),
    ),
];

void main() {
  late TestRelay relay;
  late SyncIdentity identity;
  late Device a;
  late Device b;

  setUp(() async {
    relay = await TestRelay.start();
    identity = SyncIdentity.generate();
    a = Device('device-a', identity, relay.url);
    b = Device('device-b', SyncIdentity.fromNsec(identity.nsec), relay.url);
  });

  tearDown(() async {
    await a.close();
    await b.close();
    await relay.close();
  });

  group('Shots', () {
    test('shot with curve, rating and bean arrives completely', () async {
      final bean = await at(
        () => a.db.insertBean(BeansCompanion.insert(name: 'Guji')),
      );
      final id = await at(
        () => a.db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 9, 8, 30),
            machine: const Value('pourover'),
            beanId: Value(bean.id),
            profileName: const Value('Tetsu 4:6'),
            doseGrams: const Value(15),
            finalWeight: const Value(250.4),
            durationMs: const Value(210000),
            grindSize: const Value('6.5'),
            shotPhotoPath: const Value('/lokal/foto.jpg'),
          ),
          curve(300),
        ),
      );
      await at(() => a.db.setShotRating(id, 4));
      await at(() => a.db.setShotTaste(id, TasteAxis.sweetness, 3));
      await at(() => a.db.setShotTasteExtras(id, ['Erdbeere']));
      await at(() => a.db.setShotNotes(id, 'süß, rund'));
      await a.sync();
      final report = await b.sync();
      expect(report.applied, 2, reason: 'bean + shot');

      final entry = (await b.shots()).single;
      final s = entry.shot;
      final orig = (await a.shots()).single.shot;
      expect(s.syncId, orig.syncId);
      expect(entry.bean?.name, 'Guji', reason: 'linked via syncId');
      expect(s.timestamp, DateTime(2026, 10, 9, 8, 30));
      expect(s.profileName, 'Tetsu 4:6');
      expect(s.doseGrams, 15);
      expect(s.finalWeight, 250.4);
      expect(s.rating, 4);
      expect(s.tasteSweetness, 3);
      expect(s.tasteExtras, 'Erdbeere');
      expect(s.notes, 'süß, rund');
      expect(s.shotPhotoPath, isNull, reason: 'local path stays local');
      expect(s.machine, 'pourover');

      final readings = await b.db.readingsFor(s.id);
      final original = await a.db.readingsFor(orig.id);
      expect(readings, hasLength(300));
      for (var i = 0; i < 300; i++) {
        expect(readings[i].timeMs, original[i].timeMs);
        expect(readings[i].pressure, original[i].pressure);
        expect(readings[i].flow, original[i].flow);
        expect(readings[i].weight, original[i].weight);
        expect(readings[i].stage, original[i].stage);
        expect(readings[i].barUp, isNull);
      }
    });

    test(
      'deleting a bean does not overwrite a shot change from the other device',
      () async {
        // Reproduction: B rates, A then deletes the bean without knowing
        // B's version. Previously deleting re-stamped the shot on A — A's
        // empty version won and B's rating was gone.
        final bean = await at(
          () => a.db.insertBean(BeansCompanion.insert(name: 'Guji')),
        );
        await at(
          () => a.db.insertShotWithReadings(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 10, 11, 8),
              beanId: Value(bean.id),
            ),
            const [],
          ),
        );
        await a.sync();
        await b.sync();

        final onB = (await b.shots()).single.shot;
        await at(() => b.db.setShotRating(onB.id, 5));
        await at(() => a.db.deleteBean(bean.id));
        await a.sync();
        await b.sync();
        await a.sync();

        for (final d in [a, b]) {
          final entry = (await d.shots()).single;
          expect(entry.shot.rating, 5, reason: '${d.name}: rating stays');
          expect(entry.bean, isNull, reason: '${d.name}: bean is gone');
          expect(await d.db.allBeans(), isEmpty);
        }
      },
    );

    test('shot before its bean: link is backfilled', () async {
      final bean = await at(
        () => a.db.insertBean(BeansCompanion.insert(name: 'Kiambu')),
      );
      await at(
        () => a.db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 9),
            beanId: Value(bean.id),
          ),
          curve(5),
        ),
      );
      await a.sync();
      // The relay doesn't have the bean event yet.
      String typeOf(e) => SyncEnvelope.decode(
        nip44Decrypt(e.content as String, identity.selfConversationKey),
      ).type;
      final beanEvent = relay.events.firstWhere((e) => typeOf(e) == 'bean');
      relay.events.remove(beanEvent);

      await b.sync();
      expect((await b.shots()).single.bean, isNull);
      expect((await b.state.load()).pendingLinks, hasLength(1));

      relay.events.add(beanEvent);
      await b.sync();
      expect((await b.shots()).single.bean?.name, 'Kiambu');
      expect((await b.state.load()).pendingLinks, isEmpty);
      expect(
        (await b.shots()).single.shot.syncState,
        SyncState.synced,
        reason: 'backfill is not a change of its own',
      );
    });

    test('same machine shot on both devices: no duplicate, '
        'rating from A wins over the fresh import on B', () async {
      Future<int> import(Device d) => d.db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 10, 9, 7),
          externalId: const Value('m-42'),
          finalWeight: const Value(36),
        ),
        curve(10),
        untouchedImport: true,
      );
      final idA = await import(a);
      await import(b);
      await at(() => a.db.setShotRating(idA, 5));
      await a.sync();
      await b.sync();
      final onB = await b.shots();
      expect(onB, hasLength(1));
      expect(onB.single.shot.rating, 5);
      expect(onB.single.shot.syncId, machineShotSyncId('meticulous', 'm-42'));
      await a.sync();
      expect((await a.shots()).single.shot.rating, 5);
    });

    test(
      'delete: tombstone with machine ID, curve gone, no re-import',
      () async {
        final id = await at(
          () => a.db.insertShotWithReadings(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 10, 9, 7),
              externalId: const Value('m-7'),
            ),
            curve(10),
          ),
        );
        await a.sync();
        await b.sync();
        expect(await b.shots(), hasLength(1));

        await at(() => a.db.deleteShots([id]));
        await a.sync();
        await b.sync();
        expect(await b.shots(), isEmpty);
        expect(await b.db.knownExternalIds(), contains('m-7'));
        final tomb = (await b.db.select(b.db.shots).get()).single;
        expect(tomb.deletedAt, isNotNull);
        expect(await b.db.readingsFor(tomb.id), isEmpty);
      },
    );

    test('shot over 60 KB: waits, does not count as pending', () async {
      await a.db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 10, 9),
          // Random data can't be compressed.
          notes: Value(base64.encode(secureRandomBytes(60000))),
        ),
        const [],
      );
      final report = await a.sync();
      expect(report.tooLarge, 1);
      expect(relay.events, isEmpty);
      expect(await a.db.syncDao.watchPendingCount().first, 0);
      expect(
        (await a.db.select(a.db.shots).getSingle()).syncState,
        SyncState.tooLarge,
      );
    });
  });

  test('own echo from before sync (without device) is not rewritten', () async {
    final id = await a.db.insertShotWithReadings(
      ShotsCompanion.insert(timestamp: DateTime(2026, 10, 1)),
      curve(20),
    );
    // Like after the migration: no device recorded.
    await (a.db.update(a.db.shots)..where((s) => s.id.equals(id))).write(
      const ShotsCompanion(deviceId: Value(null)),
    );
    final readingIds = (await a.db.readingsFor(id)).map((r) => r.id).toList();
    await a.sync();
    final echo = await a.sync();
    expect(echo.applied, 0);
    expect(
      (await a.db.readingsFor(id)).map((r) => r.id).toList(),
      readingIds,
      reason: 'curve not deleted and reinserted',
    );
    expect(await a.db.syncDao.watchPendingCount().first, 0);
  });

  group('Profiles', () {
    StoredProfilesCompanion profile(String json) =>
        StoredProfilesCompanion.insert(
          id: 'p1',
          machine: const Value('gaggimate'),
          name: 'Turbo',
          json: json,
          fetchedAt: DateTime(2026, 10, 1),
          imagePath: const Value('/lokal/bild.png'),
        );

    Future<StoredProfile?> onB() =>
        b.db.storedProfile('p1', machine: 'gaggimate');

    test('profile, custom description and deletion arrive', () async {
      await at(() => a.db.upsertStoredProfile(profile('{"v":1}')));
      await at(
        () => a.db.setProfileCustomDescription(
          'p1',
          'mein Turbo',
          machine: 'gaggimate',
        ),
      );
      await a.sync();
      await b.sync();
      final p = (await onB())!;
      expect(p.json, '{"v":1}');
      expect(p.customDescription, 'mein Turbo');
      expect(p.imagePath, isNull, reason: 'image path stays local');
      expect(p.syncId, machineProfileSyncId('gaggimate', 'p1'));

      await at(() => a.db.deleteStoredProfile('p1', machine: 'gaggimate'));
      await a.sync();
      await b.sync();
      expect(await onB(), isNull);
    });
  });

  group('Settings', () {
    test('changed on A → taken over on B, app re-reads', () async {
      await a.sync(); // first capture: everything "never set"
      a.prefs.values[AppSettings.themeModePrefKey] = 'light';
      a.prefs.values[AppSettings.beanFormHiddenPrefKey] = ['cost', 'variety'];
      await a.sync();
      await b.sync();
      expect(b.prefs.values[AppSettings.themeModePrefKey], 'light');
      expect(b.prefs.values[AppSettings.beanFormHiddenPrefKey], [
        'cost',
        'variety',
      ]);
      expect(b.reloads, 1);
      // B doesn't treat the taken-over values as its own change.
      await b.sync();
      expect(await b.db.syncDao.watchPendingCount().first, 0);
    });

    test('a set value beats a fresh device with default values', () async {
      a.prefs.values[AppSettings.accentPrefKey] = 'amber';
      await a.sync();
      await b.sync(); // B: nothing set, first capture
      expect(b.prefs.values[AppSettings.accentPrefKey], 'amber');
    });

    test('newer change wins; removal syncs too', () async {
      a.prefs.values[AppSettings.historyAvatarPrefKey] = 'bean';
      await a.sync();
      await b.sync();
      b.prefs.values.remove(AppSettings.historyAvatarPrefKey);
      await b.sync();
      await a.sync();
      expect(
        a.prefs.values.containsKey(AppSettings.historyAvatarPrefKey),
        isFalse,
      );
    });

    test(
      'whitelist only: machine address and main switch stay local',
      () async {
        a.prefs.values['meticulous_hostname'] = 'meticulous.local';
        a.prefs.values['ai_enabled'] = true;
        await a.sync();
        await b.sync();
        expect(b.prefs.values, isEmpty);
        expect(syncedSettingKeys(), isNot(contains('ai_enabled')));
      },
    );
  });
}
