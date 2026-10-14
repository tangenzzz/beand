import 'package:beand/database/database.dart';
import 'package:beand/sync/engine/sync_engine.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/relay_pool.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_relay.dart';

// Device announcement: when does a device send its whole data set again?

var now = DateTime(2026, 10, 12, 12);

Future<T> at<T>(
  Future<T> Function() body, {
  Duration step = const Duration(minutes: 1),
}) {
  now = now.add(step);
  return withClock(Clock.fixed(now), body);
}

class Device {
  Device(this.name, this.identity, String relayUrl)
    : db = AppDatabase(NativeDatabase.memory())..deviceId = name,
      state = InMemorySyncStateStore() {
    pool = RelayPool(identity: identity, timeout: const Duration(seconds: 5))
      ..setUrls([relayUrl]);
    engine = SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: name,
      stateStore: state,
      now: () => now,
    );
  }

  final String name;
  final SyncIdentity identity;
  final AppDatabase db;
  final InMemorySyncStateStore state;
  late final RelayPool pool;
  late final SyncEngine engine;

  Future<SyncReport> sync({Duration after = const Duration(minutes: 1)}) =>
      at(() => engine.run(force: true), step: after);

  Future<void> addBean(String name) =>
      at(() => db.insertBean(BeansCompanion.insert(name: name)));

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

  // Records from A on the relay (without the announcements): bean events.
  int records() => relay.events.length;

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

  test('first time: announcement goes out, no full upload', () async {
    await a.addBean('Guji');
    final report = await a.sync();
    expect(report.resentAll, isNull);
    expect(records(), 2, reason: 'bean + announcement');
    final p = (await a.state.load()).presence!;
    expect(p.initialized, isTrue);
    expect(p.relays, {relay.url});

    // Next sync shortly after: announcement is still fresh, nothing new.
    final before = relay.received.length;
    await a.sync();
    expect(relay.received.length, before);
  });

  test('relay loses everything → device resends its data', () async {
    await a.addBean('Guji');
    await a.addBean('Kiambu');
    await a.sync();
    expect(records(), 3);

    relay.events.clear(); // cleaned up or "Delete synced data"
    final report = await a.sync();
    expect(report.resentAll, contains('data gone'));
    expect(report.sent, 2);
    expect(records(), 3, reason: 'both beans + announcement back');

    // Gone again right away: no second full upload within 6 h, only the
    // announcement comes back.
    relay.events.clear();
    final again = await a.sync();
    expect(again.resentAll, isNull);
    expect(records(), 1);

    // Again after the pause.
    relay.events.clear();
    final later = await a.sync(after: const Duration(hours: 7));
    expect(later.resentAll, contains('data gone'));
    expect(records(), 3);
  });

  test('relay empties and then rejects → only one full upload', () async {
    await a.addBean('Guji');
    await a.sync();
    relay.events.clear();
    relay.allowedAuthors = {}; // key removed from the whitelist
    final first = await a.sync();
    expect(first.resentAll, contains('data gone'));
    // The announcement no longer arrives — no further upload, not even
    // after the 6 h pause.
    final later = await a.sync(after: const Duration(hours: 7));
    expect(later.resentAll, isNull);
    final evenLater = await a.sync(after: const Duration(days: 2));
    expect(evenLater.resentAll, isNull);
  });

  test('new device appears → the others send their data', () async {
    await a.addBean('Guji');
    await a.sync(); // A knows no one yet
    final first = await b.sync(); // B is new: fetches Guji, remembers A
    expect(first.resentAll, isNull);
    expect((await b.db.allBeans()).map((x) => x.name), ['Guji']);

    final report = await a.sync(); // A sees B for the first time
    expect(report.resentAll, 'device device-b');
    expect(report.sent, 1);

    // B is known now — no further full upload.
    final quiet = await a.sync(after: const Duration(hours: 7));
    expect(quiet.resentAll, isNull);
  });

  test('device was gone for over 14 days → data resent', () async {
    await a.addBean('Guji');
    await a.sync();
    await b.sync();
    await a.sync(); // B new → once in full
    await a.sync(after: const Duration(hours: 7));

    // B stays silent for 15 days, A keeps syncing.
    await a.sync(after: const Duration(days: 15));
    final back = await b.sync(after: const Duration(minutes: 1));
    // B sends too: within 15 days the relays may have cleaned up its old
    // data.
    expect(back.resentAll, 'device device-a');
    final report = await a.sync();
    expect(report.resentAll, 'device device-b');
  });

  test('different key: announcement starts over', () async {
    await a.sync();
    final data = await a.state.load();
    expect(data.presence!.pubkey, identity.publicKeyHex);
    final other = SyncIdentity.generate();
    expect(data.presenceFor(other.publicKeyHex).initialized, isFalse);
    expect(data.presence!.relays, isEmpty);
  });
}
