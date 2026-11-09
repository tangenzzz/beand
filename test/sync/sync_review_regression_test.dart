import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/database/sync_ids.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_service.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/sync/blobs/blob_ref.dart';
import 'package:beand/sync/blobs/blob_sync.dart';
import 'package:beand/sync/blobs/blossom_client.dart';
import 'package:beand/sync/crypto/bytes.dart';
import 'package:beand/sync/engine/event_worker.dart';
import 'package:beand/sync/engine/sync_engine.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/identity/key_store.dart';
import 'package:beand/sync/nostr/event.dart';
import 'package:beand/sync/nostr/relay_connection.dart';
import 'package:beand/sync/nostr/relay_pool.dart';
import 'package:beand/sync/records/setting_codec.dart';
import 'package:beand/sync/records/sync_envelope.dart';
import 'package:beand/sync/sync_service.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_blossom.dart';
import '../support/test_relay.dart';

// Defects found in the independent review of the sync (2026-11-09), each
// reproduced first. Relays and photo servers are real local servers wherever
// the transport matters.

class _Device {
  _Device(
    this.name,
    this.identity,
    String relay,
    List<String> servers, {
    int pageSize = 500,
  }) {
    db = AppDatabase(NativeDatabase.memory())..deviceId = name;
    docs = Directory.systemTemp.createTempSync('beand_review_');
    pool = RelayPool(identity: identity, minSendInterval: Duration.zero)
      ..setUrls([relay]);
    blobs = BlobSync(
      client: BlossomClient(identity: identity),
      servers: servers,
      docsDir: () async => docs,
    );
    engine = SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: name,
      stateStore: state,
      blobs: blobs,
      pageSize: pageSize,
      devicePresence: false,
      now: () => now,
    );
  }

  final String name;
  final SyncIdentity identity;
  DateTime now = DateTime.utc(2026, 11, 1, 12);
  final state = InMemorySyncStateStore();
  late final AppDatabase db;
  late final Directory docs;
  late final RelayPool pool;
  late final BlobSync blobs;
  late final SyncEngine engine;

  Future<T> at<T>(Future<T> Function() f) => withClock(Clock.fixed(now), f);
  Future<SyncReport> run() => at(() => engine.run(force: true));
  Future<Bean> bean() async => (await db.allBeans()).single;

  String photo() {
    final file = File('${docs.path}/photo.jpg')
      ..writeAsBytesSync([255, 216, 1, 2, 3]);
    return file.path;
  }

  Future<void> close() async {
    await pool.closeAll();
    pool.dispose();
    blobs.client.close();
    await db.close();
    docs.deleteSync(recursive: true);
  }
}

// Only the transport answer is scripted; everything after it is the real
// engine.
class _ScriptedPool extends RelayPool {
  _ScriptedPool(SyncIdentity identity, this.answer) : super(identity: identity);

  final Future<List<NostrEvent>> Function(String, Map<String, Object>) answer;

  @override
  Future<List<NostrEvent>> queryOne(
    String url,
    Map<String, Object> filter, {
    bool force = false,
  }) => answer(url, filter);
}

class _OversizedClient extends http.BaseClient {
  _OversizedClient({required this.announceLength});

  final bool announceLength;
  int produced = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> body() async* {
      for (var i = 0; i < 8; i++) {
        produced += 1024 * 1024;
        yield Uint8List(1024 * 1024);
      }
    }

    return http.StreamedResponse(
      body(),
      200,
      contentLength: announceLength ? 8 * 1024 * 1024 : null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Only loopback servers and injected clients are used here.
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('with a local relay and photo server', () {
    late TestRelay relay;
    late TestBlossom blossom;
    late SyncIdentity identity;
    late _Device a;
    late _Device b;

    setUp(() async {
      relay = await TestRelay.start();
      blossom = await TestBlossom.start();
      identity = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 1);
      a = _Device('a', identity, relay.url, [blossom.url]);
      b = _Device('b', identity, relay.url, [blossom.url]);
      await a.state.save(SyncStateData(relays: [relay.url]));
      await b.state.save(SyncStateData(relays: [relay.url]));
    });

    tearDown(() async {
      await a.close();
      await b.close();
      await relay.close();
      await blossom.close();
    });

    test(
      'a relay capping pages below ours still delivers everything',
      () async {
        for (var i = 0; i < 4; i++) {
          await a.at(
            () => a.db.insertBean(BeansCompanion.insert(name: 'Bean $i')),
          );
        }
        await a.run();
        expect(relay.events.length, 4);
        relay.maxLimit = 3;

        await b.run();

        expect((await b.db.allBeans()).length, 4);
      },
    );

    test('a second with more events than a page holds is read whole', () async {
      final c = _Device('c', identity, relay.url, [], pageSize: 3);
      addTearDown(c.close);
      for (var i = 0; i < 4; i++) {
        final envelope = SyncEnvelope(
          type: 'bean',
          id: 'same-second-$i',
          updatedAt: a.now.millisecondsSinceEpoch,
          deviceId: 'a',
          deleted: false,
          data: {'name': 'Bean $i'},
        );
        relay.events.add(
          await sealEvent(
            keys: SyncKeys.of(identity),
            dTag: identity.dTag(envelope.type, envelope.id),
            plain: envelope.encode(),
            createdAt: a.now.millisecondsSinceEpoch ~/ 1000,
          ),
        );
      }

      await c.run();

      expect((await c.db.allBeans()).length, 4);
    });

    Future<Map<String, Uint8List>> publishLargeShot() async {
      final notes = base64.encode(secureRandomBytes(60000));
      await a.at(
        () => a.db.insertShotWithReadings(
          ShotsCompanion.insert(timestamp: a.now, notes: Value(notes)),
          [],
        ),
      );
      await a.run();
      expect(blossom.blobs.length, 1);
      final saved = Map<String, Uint8List>.of(blossom.blobs);
      blossom.blobs.clear();
      // Well after the event's created_at, so the cursor would pass it.
      b.now = a.now.add(const Duration(hours: 1));
      return saved;
    }

    test(
      'an outsourced record is fetched again after a failed download',
      () async {
        final saved = await publishLargeShot();
        final first = await b.run();
        expect(first.skipped, 1);

        blossom.blobs.addAll(saved);
        b.now = b.now.add(const Duration(minutes: 1));
        await b.run();

        expect(await b.db.select(b.db.shots).get(), hasLength(1));
        expect((await b.state.load()).blobRetries, isEmpty);
      },
    );

    test('a blob that stays gone stops holding the cursor', () async {
      await publishLargeShot();
      final state = await b.state.load();
      state.blobRetries[relay.events.single.id] = SyncEngine.maxBlobRetries - 1;
      await b.state.save(state);

      await b.run();

      final after = await b.state.load();
      expect(after.blobRetries, isEmpty);
      expect(after.lastSync[relay.url], b.now.millisecondsSinceEpoch ~/ 1000);
    });

    test(
      'a re-uploaded photo reference reaches a device already in sync',
      () async {
        await a.at(
          () => a.db.insertBean(
            BeansCompanion.insert(name: 'Guji', photoPath: Value(a.photo())),
          ),
        );
        await a.run();
        final old = Map<String, Uint8List>.of(blossom.blobs);
        blossom.blobs.clear();
        await b.run();
        expect((await b.bean()).photoBlob, isNotNull);
        expect((await b.bean()).photoPath, isNull);

        blossom.blobs.addAll(old);
        await a.db.syncDao.reuploadLocalPhotos();
        a.now = a.now.add(const Duration(minutes: 1));
        await a.run();
        for (final sha in old.keys) {
          blossom.blobs.remove(sha);
        }
        b.now = a.now;
        await b.run();

        expect((await b.bean()).photoBlob, (await a.bean()).photoBlob);
        expect((await b.bean()).photoPath, isNotNull);
      },
    );

    Future<void> editAfterClockCorrection(DateTime wrong) async {
      a.now = wrong;
      final bean = await a.at(
        () => a.db.insertBean(BeansCompanion.insert(name: 'old')),
      );
      await a.run();
      a.now = DateTime.utc(2026, 11, 1, 12);
      await a.at(
        () =>
            a.db.updateBean(bean.id, const BeansCompanion(name: Value('new'))),
      );
      await a.run();
    }

    test(
      'a corrected clock does not undo an edit waiting to be sent',
      () async {
        await editAfterClockCorrection(DateTime.utc(2026, 11, 1, 13));
        expect((await a.bean()).name, 'new');
      },
    );

    test(
      'an edit after a small clock correction reaches other devices',
      () async {
        await editAfterClockCorrection(DateTime.utc(2026, 11, 1, 12, 1));
        b.now = a.now;
        await b.run();
        expect((await b.bean()).name, 'new');
      },
    );

    Future<
      ({SyncService sync, Completer<void> started, Completer<void> release})
    >
    serviceWithHangingUpload() async {
      final state = InMemorySyncStateStore();
      await state.save(
        SyncStateData(
          relays: [relay.url],
          blobServers: ['https://review.invalid'],
          blobDefaultsApplied: true,
        ),
      );
      final keys = InMemorySyncKeyStore();
      await keys.writeIdentity(identity);
      final started = Completer<void>();
      final release = Completer<void>();
      final client = MockClient((request) async {
        if (request.method == 'PUT') {
          if (!started.isCompleted) started.complete();
          await release.future;
          return http.Response('{}', 200);
        }
        return http.Response('', request.method == 'HEAD' ? 200 : 404);
      });
      final sync = SyncService(
        db: a.db,
        keyStore: keys,
        stateStore: state,
        httpClient: client,
        docsDir: () async => a.docs,
        devicePresence: false,
        changeDelay: const Duration(days: 1),
      );
      addTearDown(sync.dispose);
      await sync.init();
      await a.at(
        () => a.db.insertBean(
          BeansCompanion.insert(name: 'Guji', photoPath: Value(a.photo())),
        ),
      );
      return (sync: sync, started: started, release: release);
    }

    test('nothing goes out after sync is turned off', () async {
      final s = await serviceWithHangingUpload();
      final running = s.sync.enable();
      await s.started.future.timeout(const Duration(seconds: 5));

      await s.sync.disable();
      s.release.complete();
      await running;

      expect(relay.events, isEmpty);
      expect(s.sync.phase, SyncPhase.off);
    });

    test('a key change during an upload still fills the new account', () async {
      final s = await serviceWithHangingUpload();
      final running = s.sync.enable();
      await s.started.future.timeout(const Duration(seconds: 5));

      final next = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 2);
      final adopting = s.sync.adoptIdentity(next);
      for (var i = 0; i < 100 && s.sync.identity?.npub != next.npub; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(s.sync.identity?.npub, next.npub);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      s.release.complete();
      await running;
      await adopting;
      await s.sync.syncNow();
      for (var i = 0; i < 100 && s.sync.phase == SyncPhase.syncing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(s.sync.phase, isNot(SyncPhase.syncing));
      expect(
        relay.events.where((e) => e.pubkey == next.publicKeyHex),
        hasLength(1),
      );
    });
  });

  test('a forged copy does not displace the real event', () async {
    final identity = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 1);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const envelope = SyncEnvelope(
      type: 'bean',
      id: 'record',
      updatedAt: 1,
      deviceId: 'a',
      deleted: false,
      data: {'name': 'real'},
    );
    final good = await sealEvent(
      keys: SyncKeys.of(identity),
      dTag: identity.dTag('bean', 'record'),
      plain: envelope.encode(),
      createdAt: 1,
    );
    final bad = NostrEvent.fromJson({...good.toJson(), 'content': 'forged'});
    expect(bad.isValid, isFalse);
    final firstReturned = Completer<void>();
    final pool = _ScriptedPool(identity, (url, filter) async {
      if (url.endsWith('bad')) {
        if (!firstReturned.isCompleted) firstReturned.complete();
        return [bad];
      }
      await firstReturned.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return [good];
    })..setUrls(['wss://review.invalid/bad', 'wss://review.invalid/good']);
    addTearDown(pool.dispose);
    final engine = SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: 'b',
      stateStore: InMemorySyncStateStore(),
      devicePresence: false,
    );

    await engine.pull(SyncReport());

    expect(await db.allBeans(), hasLength(1));
  });

  test('a relay repeating the same full page ends the fetch', () async {
    final identity = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 1);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final forged = NostrEvent(
      id: '0' * 64,
      pubkey: identity.publicKeyHex,
      createdAt: 1,
      kind: kindAppData,
      tags: const [],
      content: '',
      sig: '0' * 128,
    );
    var calls = 0;
    final pool = _ScriptedPool(identity, (_, _) async {
      calls++;
      if (calls == 6) throw const RelayException('test safety stop');
      return List.filled(500, forged);
    })..setUrls(['wss://review.invalid']);
    addTearDown(pool.dispose);
    final engine = SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: 'b',
      stateStore: InMemorySyncStateStore(),
      devicePresence: false,
    );

    await engine.pull(SyncReport());

    expect(calls, lessThanOrEqualTo(2));
  });

  for (final announced in [true, false]) {
    test('a download larger than its reference is dropped '
        '(length ${announced ? 'announced' : 'unknown'})', () async {
      final client = _OversizedClient(announceLength: announced);
      final blossom = BlossomClient(
        identity: SyncIdentity.generate(),
        client: client,
      );
      addTearDown(blossom.close);
      final store = BlobSync(
        client: blossom,
        servers: [],
        docsDir: () async => throw UnimplementedError(),
      );
      final ref = BlobRef(
        sha256: '0' * 64,
        size: 32,
        key: base64.encode(Uint8List(32)),
        nonce: base64.encode(Uint8List(24)),
        urls: ['https://review.invalid/blob'],
      );

      expect(await store.downloadBytes(ref), isNull);
      expect(client.produced, lessThanOrEqualTo(1024 * 1024));
    });
  }

  test('a Custom AI address from another device is not taken over', () async {
    SharedPreferences.setMockInitialValues({
      AiSettings.enabledPrefKey: true,
      AiSettings.providerPrefKey: AiProvider.compatible.name,
      AiSettings.baseUrlPrefKey: 'https://old-provider.invalid/v1',
      AiSettings.modelPrefKey(AiProvider.compatible): 'model',
    });
    final keys = InMemoryAiKeyStore();
    await keys.write(AiProvider.compatible, 'test-api-key');
    final settings = await AiSettings.load(keyStore: keys);
    final identity = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 1);
    const key = AiSettings.baseUrlPrefKey;
    final envelope = SyncEnvelope(
      type: settingType,
      id: settingSyncId(key),
      updatedAt: 100,
      deviceId: 'other-device',
      deleted: false,
      data: {
        'key': key,
        'value': jsonEncode('https://new-provider.invalid/v1'),
      },
    );
    final signed = await sealEvent(
      keys: SyncKeys.of(identity),
      dTag: identity.dTag(envelope.type, envelope.id),
      plain: envelope.encode(),
      createdAt: 100,
    );
    final pool = _ScriptedPool(identity, (_, _) async => [signed])
      ..setUrls(['wss://review.invalid']);
    addTearDown(pool.dispose);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final engine = SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: 'local',
      stateStore: InMemorySyncStateStore(),
      devicePresence: false,
      settings: SettingsBridge(
        prefs: () async => SharedPreferencesSettingsStore(
          await SharedPreferences.getInstance(),
        ),
        reload: settings.reload,
      ),
    );

    await engine.pull(SyncReport());

    expect(settings.baseUrl, 'https://old-provider.invalid/v1');
    final requests = <http.Request>[];
    final client = MockClient((r) async {
      requests.add(r);
      return http.Response('{"data":[]}', 200);
    });
    addTearDown(client.close);
    await AiService(settings, httpClient: client).listModels();
    expect(requests.single.url.host, 'old-provider.invalid');
  });

  group('IPv6 addresses', () {
    const public = '[2606:4700:4700::1111]';

    test('a public one gets TLS by default', () {
      expect(
        SyncService.normalizeRelayUrl('$public:7777'),
        'wss://$public:7777',
      );
      expect(
        SyncService.normalizeBlobServerUrl('$public:3000'),
        'https://$public:3000',
      );
    });

    test('loopback, unique local and link local count as local', () {
      expect(SyncService.isLocalHost('::1'), isTrue);
      expect(SyncService.isLocalHost('fd7a:115c:a1e0::1'), isTrue);
      expect(SyncService.isLocalHost('fe80::1'), isTrue);
      expect(SyncService.isLocalHost('2606:4700:4700::1111'), isFalse);
    });

    test('a bare host name stays local', () {
      expect(SyncService.isLocalHost('beand'), isTrue);
    });
  });
}
