import 'package:beand/database/database.dart';
import 'package:beand/sync/crypto/nip44.dart';
import 'package:beand/sync/engine/sync_engine.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/event.dart';
import 'package:beand/sync/nostr/relay_pool.dart';
import 'package:beand/sync/records/sync_envelope.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_relay.dart';

// Two simulated devices with the same sync key against an in-process relay
// (required tests: change A → B, concurrent change, deletion).

// Clock of all devices in the test: each change and each sync one minute
// later so "newer" is unambiguous and the relay can order by time.
var now = DateTime(2026, 10, 10, 12);

Future<T> at<T>(Future<T> Function() body) {
  now = now.add(const Duration(minutes: 1));
  return withClock(Clock.fixed(now), body);
}

class Device {
  Device(this.name, this.identity, String relayUrl, {int pageSize = 500})
    : db = AppDatabase(NativeDatabase.memory())..deviceId = name,
      state = InMemorySyncStateStore() {
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
      pageSize: pageSize,
      now: () => now,
    );
  }

  final String name;
  final SyncIdentity identity;
  final AppDatabase db;
  final InMemorySyncStateStore state;
  late final RelayPool pool;
  late final SyncEngine engine;

  Future<SyncReport> sync() => at(() => engine.run(force: true));

  Future<List<Bean>> beans() => db.allBeans();

  Future<void> close() async {
    await pool.closeAll();
    await db.close();
  }
}

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

  test('bean created on A → appears on B, both synced afterwards', () async {
    await at(
      () => a.db.insertBean(
        BeansCompanion.insert(
          name: 'Guji Natural',
          roaster: const Value('Bonanza'),
          roastDate: Value(DateTime(2026, 9, 30)),
          weightGrams: const Value(250),
          isBlend: const Value(false),
          taste: const Value('blueberry, jasmine'),
        ),
      ),
    );
    final sentReport = await a.sync();
    expect(sentReport.sent, 1);
    expect(relay.events, hasLength(1));

    final report = await b.sync();
    expect(report.applied, 1);
    final onB = (await b.beans()).single;
    final onA = (await a.beans()).single;
    expect(onB.name, 'Guji Natural');
    expect(onB.roaster, 'Bonanza');
    expect(onB.roastDate, DateTime(2026, 9, 30));
    expect(onB.weightGrams, 250);
    expect(onB.isBlend, false);
    expect(onB.taste, 'blueberry, jasmine');
    expect(onB.syncId, onA.syncId);
    expect(onB.updatedAt, onA.updatedAt);
    expect(onB.deviceId, 'device-a');
    expect(onB.syncState, SyncState.synced);
    expect(onA.syncState, SyncState.synced);

    // B has nothing of its own to send; its own echo changes nothing.
    expect((await b.sync()).sent, 0);
    expect((await a.sync()).applied, 0);
  });

  test('relay sees only encrypted data and a meaningless d tag', () async {
    await a.db.insertBean(BeansCompanion.insert(name: 'Kiambu AA'));
    await a.sync();
    final event = relay.events.single;
    expect(event.kind, kindAppData);
    expect(event.content, isNot(contains('Kiambu')));
    expect(event.tags, hasLength(1));
    expect(event.tag('d'), matches(RegExp(r'^[0-9a-f]{64}$')));
    final envelope = SyncEnvelope.decode(
      nip44Decrypt(event.content, identity.selfConversationKey),
    );
    expect(envelope.type, 'bean');
    expect(envelope.data['name'], 'Kiambu AA');
  });

  test('change on B comes back to A', () async {
    final bean = await at(
      () => a.db.insertBean(BeansCompanion.insert(name: 'Guji')),
    );
    await a.sync();
    await b.sync();
    final onB = (await b.beans()).single;
    await at(
      () => b.db.updateBean(onB.id, const BeansCompanion(cost: Value(16.5))),
    );
    await b.sync();
    await a.sync();
    final back = (await a.beans()).single;
    expect(back.id, bean.id, reason: 'local ID stays');
    expect(back.cost, 16.5);
    expect(back.deviceId, 'device-b');
    expect(back.syncState, SyncState.synced);
  });

  test('changed concurrently: the newer state wins on both devices', () async {
    await at(() => a.db.insertBean(BeansCompanion.insert(name: 'Guji')));
    await a.sync();
    await b.sync();
    final idA = (await a.beans()).single.id;
    final idB = (await b.beans()).single.id;

    // Both changed offline, B later.
    await at(
      () => a.db.updateBean(idA, const BeansCompanion(roaster: Value('A'))),
    );
    await at(
      () => b.db.updateBean(idB, const BeansCompanion(roaster: Value('B'))),
    );
    // B sends first, A after — the relay then has A's OLDER state.
    await b.sync();
    await a.sync(); // A holt B's neueren Stand, bevor es sendet
    expect((await a.beans()).single.roaster, 'B');
    expect(relay.events, hasLength(1));
    await b.sync();
    expect((await b.beans()).single.roaster, 'B');
  });

  test(
    'relay keeps the older state → the device with the newer one resends',
    () async {
      await at(() => a.db.insertBean(BeansCompanion.insert(name: 'Guji')));
      await a.sync();
      await b.sync();
      final idA = (await a.beans()).single.id;
      final idB = (await b.beans()).single.id;

      await at(
        () => b.db.updateBean(idB, const BeansCompanion(roaster: Value('new'))),
      );
      await b.sync(); // relay: new (B)
      // A made an OLDER state offline (clock turned back) and only sends
      // now without fetching first → relay replaces B's state.
      final old = now.subtract(const Duration(minutes: 30));
      await withClock(
        Clock.fixed(old),
        () => a.db.updateBean(idA, const BeansCompanion(roaster: Value('old'))),
      );
      await at(() => a.engine.push(SyncReport(), force: true));
      String relayRoaster() =>
          SyncEnvelope.decode(
                nip44Decrypt(
                  relay.events.single.content,
                  identity.selfConversationKey,
                ),
              ).data['roaster']
              as String;
      expect(relayRoaster(), 'old', reason: 'relay now has the older state');

      // B fetches A's old state, keeps its own and resends it.
      await b.sync();
      expect((await b.beans()).single.roaster, 'new');
      expect(relayRoaster(), 'new', reason: 'B resent its state');
      await a.sync();
      expect((await a.beans()).single.roaster, 'new');
    },
  );

  test('delete on A: B gets the tombstone, bean disappears', () async {
    await at(() => a.db.insertBean(BeansCompanion.insert(name: 'Guji')));
    await a.sync();
    await b.sync();
    expect(await b.beans(), hasLength(1));

    final id = (await a.beans()).single.id;
    await at(() => a.db.deleteBean(id));
    await a.sync();
    final report = await b.sync();
    expect(report.applied, 1);
    expect(await b.beans(), isEmpty);
    final tomb = (await b.db.select(b.db.beans).get()).single;
    expect(tomb.deleted, isTrue);
    expect(tomb.syncState, SyncState.synced);
  });

  test(
    'tombstone beats older state; newer state beats older tombstone',
    () async {
      await at(() => a.db.insertBean(BeansCompanion.insert(name: 'Guji')));
      await a.sync();
      await b.sync();
      final idA = (await a.beans()).single.id;
      final idB = (await b.beans()).single.id;

      // A deletes (earlier), B changes (later) → B's change wins.
      await at(() => a.db.deleteBean(idA));
      await at(
        () => b.db.updateBean(idB, const BeansCompanion(roaster: Value('B'))),
      );
      await a.sync();
      await b.sync();
      await a.sync();
      expect((await a.beans()).single.roaster, 'B');
      expect((await b.beans()).single.roaster, 'B');

      // Now B deletes (later than everything else) → gone on both.
      await at(() => b.db.deleteBean(idB));
      await b.sync();
      await a.sync();
      expect(await a.beans(), isEmpty);
      expect(await b.beans(), isEmpty);
    },
  );

  test('first sync fetches everything paginated, more than one page', () async {
    final c = Device(
      'device-c',
      SyncIdentity.fromNsec(identity.nsec),
      relay.url,
      pageSize: 3,
    );
    addTearDown(c.close);
    for (var i = 0; i < 8; i++) {
      // All sent in one sync: they still get different seconds, otherwise
      // pagination wouldn't progress.
      await a.db.insertBean(BeansCompanion.insert(name: 'Bean $i'));
    }
    await a.sync();
    expect(relay.events, hasLength(8));
    expect(relay.events.map((e) => e.createdAt).toSet(), hasLength(8));
    final report = await c.sync();
    expect(report.applied, 8);
    expect((await c.beans()).map((b) => b.name).toSet(), {
      for (var i = 0; i < 8; i++) 'Bean $i',
    });
  });

  test('foreign key: events are ignored', () async {
    final stranger = Device('stranger', SyncIdentity.generate(), relay.url);
    addTearDown(stranger.close);
    await stranger.db.insertBean(BeansCompanion.insert(name: 'Fremd'));
    await stranger.sync();
    await b.sync();
    expect(await b.beans(), isEmpty);
  });

  test(
    'relay rejects the key: stays pending, message understandable',
    () async {
      relay.allowedAuthors = {'0' * 64};
      await a.db.insertBean(BeansCompanion.insert(name: 'Guji'));
      final report = await a.sync();
      expect(report.sent, 0);
      expect(report.notSent, 1);
      expect((await a.beans()).single.syncState, SyncState.pending);
      expect(
        a.pool.statusOf(relay.url).message,
        "This server doesn't accept your device key yet.",
      );

      relay.allowedAuthors = null;
      expect((await a.sync()).sent, 1);
      expect((await a.beans()).single.syncState, SyncState.synced);
    },
  );

  test('relay unreachable: nothing is lost, it works later', () async {
    await relay.close();
    await a.db.insertBean(BeansCompanion.insert(name: 'Guji'));
    final report = await a.sync();
    expect(report.failedRelays, isNotEmpty);
    expect((await a.beans()).single.syncState, SyncState.pending);
    expect(a.pool.statusOf(a.pool.urls.single).state, RelayState.error);
  });

  test('change during sending stays pending', () async {
    final bean = await at(
      () => a.db.insertBean(BeansCompanion.insert(name: 'Guji')),
    );
    final pending = await a.db.syncDao.pendingBeans();
    // Between reading and OK the user changes the bean.
    await at(
      () => a.db.updateBean(bean.id, const BeansCompanion(cost: Value(9))),
    );
    await a.db.syncDao.markSynced(
      'beans',
      pending.single.syncId,
      pending.single.updatedAt,
    );
    expect((await a.beans()).single.syncState, SyncState.pending);
  });
}
