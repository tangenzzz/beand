import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/sync/blobs/blob_sync.dart';
import 'package:beand/sync/blobs/blossom_client.dart';
import 'package:beand/sync/crypto/bytes.dart';
import 'package:beand/sync/engine/account_wipe.dart';
import 'package:beand/sync/engine/sync_engine.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/relay_pool.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_blossom.dart';
import '../support/test_relay.dart';

// Photos encrypted via Blossom, oversized records as blobs.

var now = DateTime(2026, 10, 10, 12);

Future<T> at<T>(Future<T> Function() body) {
  now = now.add(const Duration(minutes: 1));
  return withClock(Clock.fixed(now), body);
}

class Device {
  Device(this.name, this.identity, String relayUrl, List<String> photoServers)
    : db = AppDatabase(NativeDatabase.memory())..deviceId = name,
      docs = Directory.systemTemp.createTempSync('beand_$name') {
    pool = RelayPool(identity: identity, timeout: const Duration(seconds: 5))
      ..setUrls([relayUrl]);
    blobs = BlobSync(
      client: BlossomClient(identity: identity),
      servers: [...photoServers],
      docsDir: () async => docs,
    );
    engine = SyncEngine(
      // Counts events — device presence is tested in presence_test.dart.
      devicePresence: false,
      db: db,
      identity: identity,
      pool: pool,
      deviceId: name,
      stateStore: InMemorySyncStateStore(),
      blobs: blobs,
      now: () => now,
    );
  }

  final String name;
  final SyncIdentity identity;
  final AppDatabase db;
  final Directory docs;
  late final RelayPool pool;
  late final BlobSync blobs;
  late final SyncEngine engine;

  Future<SyncReport> sync() => at(() => engine.run(force: true));
  Future<Bean> bean() async => (await db.allBeans()).single;

  /// Create a photo like the bean form does (file in the app folder).
  String photo(String name, List<int> bytes) {
    final dir = Directory(p.join(docs.path, 'bean_photos'))
      ..createSync(recursive: true);
    final file = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
    return file.path;
  }

  Future<void> close() async {
    await pool.closeAll();
    await db.close();
    docs.deleteSync(recursive: true);
  }
}

// A "photo": JPEG header + random bytes (incompressible).
List<int> fakeJpeg([int size = 200000]) => [
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  ...secureRandomBytes(size),
];

void main() {
  late TestRelay relay;
  late TestBlossom blossom;
  late SyncIdentity identity;
  late Device a;
  late Device b;

  setUp(() async {
    relay = await TestRelay.start();
    blossom = await TestBlossom.start();
    identity = SyncIdentity.generate();
    a = Device('device-a', identity, relay.url, [blossom.url]);
    b = Device('device-b', SyncIdentity.fromNsec(identity.nsec), relay.url, [
      blossom.url,
    ]);
  });

  tearDown(() async {
    await a.close();
    await b.close();
    await relay.close();
    await blossom.close();
  });

  test('bean photo arrives encrypted via the photo server', () async {
    final bytes = fakeJpeg();
    await at(
      () => a.db.insertBean(
        BeansCompanion.insert(
          name: 'Guji',
          photoPath: Value(a.photo('guji.jpg', bytes)),
        ),
      ),
    );
    await a.sync();
    expect(blossom.blobs, hasLength(1));
    final stored = blossom.blobs.values.single;
    expect(
      stored.sublist(0, 4),
      isNot([0xFF, 0xD8, 0xFF, 0xE0]),
      reason: 'server sees only ciphertext',
    );
    expect((await a.bean()).photoBlob, isNotNull);

    final report = await b.sync();
    expect(report.photosFetched, 1);
    final onB = await b.bean();
    expect(onB.photoPath, startsWith(b.docs.path));
    expect(File(onB.photoPath!).readAsBytesSync(), bytes);
    expect(onB.syncState, SyncState.synced);
  });

  test(
    'Delete synced data: relay and photo server empty, foreign data stays',
    () async {
      await at(
        () => a.db.insertBean(
          BeansCompanion.insert(
            name: 'Guji',
            photoPath: Value(a.photo('guji.jpg', fakeJpeg(1000))),
          ),
        ),
      );
      await at(() => a.db.insertBean(BeansCompanion.insert(name: 'Kiambu')));
      await a.sync();
      expect(relay.events, hasLength(2));
      expect(blossom.blobs, hasLength(1));

      // Another account on the same servers must not lose anything.
      final other = Device('device-c', SyncIdentity.generate(), relay.url, [
        blossom.url,
      ]);
      addTearDown(other.close);
      await at(
        () => other.db.insertBean(
          BeansCompanion.insert(
            name: 'Fremd',
            photoPath: Value(other.photo('x.jpg', fakeJpeg(1000))),
          ),
        ),
      );
      await other.sync();

      final report = await AccountWipe(
        identity: identity,
        pool: a.pool,
        blossom: BlossomClient(identity: identity),
        blobServers: [blossom.url],
        knownBlobShas: await a.db.syncDao.uploadedBlobShas(),
        chunkSize: 1, // two batches — splitting is tested too
      ).run();

      expect(report.events, 2);
      expect(report.relaysOk, {relay.url});
      expect(report.relaysFailed, isEmpty);
      expect(report.photosDeleted, 1);
      expect(
        relay.events.where(
          (e) => e.pubkey == identity.publicKeyHex && e.kind == 30078,
        ),
        isEmpty,
      );
      expect(
        relay.events.where((e) => e.pubkey == other.identity.publicKeyHex),
        hasLength(1),
      );
      expect(blossom.blobs, hasLength(1), reason: 'only the foreign photo');
      expect(blossom.owners.values.single, other.identity.publicKeyHex);
    },
  );

  test('photo replaced and removed: B follows', () async {
    final bean = await at(
      () => a.db.insertBean(
        BeansCompanion.insert(
          name: 'Guji',
          photoPath: Value(a.photo('1.jpg', fakeJpeg(1000))),
        ),
      ),
    );
    await a.sync();
    await b.sync();

    final second = fakeJpeg(2000);
    await at(
      () => a.db.updateBean(
        bean.id,
        BeansCompanion(photoPath: Value(a.photo('2.jpg', second))),
      ),
    );
    expect((await a.bean()).photoBlob, isNull, reason: 'new photo → upload');
    await a.sync();
    await b.sync();
    expect(File((await b.bean()).photoPath!).readAsBytesSync(), second);

    await at(
      () => a.db.updateBean(
        bean.id,
        const BeansCompanion(photoPath: Value(null)),
      ),
    );
    await a.sync();
    await b.sync();
    expect((await b.bean()).photoPath, isNull);
    expect((await b.bean()).photoBlob, isNull);
  });

  test('a photo on no server deletes nothing elsewhere', () async {
    final c = Device(
      'device-c',
      SyncIdentity.fromNsec(identity.nsec),
      relay.url,
      const [],
    );
    addTearDown(c.close);
    await at(() => a.db.insertBean(BeansCompanion.insert(name: 'Guji')));
    await a.sync();
    await c.sync();
    final idC = (await c.db.allBeans()).single.id;
    final idA = (await a.bean()).id;

    // A sets a photo (gets uploaded), C its own afterwards — which C can't
    // upload for lack of a photo server.
    await at(
      () => a.db.updateBean(
        idA,
        BeansCompanion(photoPath: Value(a.photo('a.jpg', fakeJpeg(1000)))),
      ),
    );
    await a.sync();
    await at(
      () => c.db.updateBean(
        idC,
        BeansCompanion(
          photoPath: Value(c.photo('c.jpg', fakeJpeg(1000))),
          cost: const Value(12),
        ),
      ),
    );
    await c.sync();
    await a.sync();
    final onA = await a.bean();
    expect(onA.cost, 12, reason: "C's change is newer");
    expect(onA.photoPath, isNotNull, reason: 'photo on A stays');
    expect(onA.photoBlob, isNotNull);
  });

  test(
    'photo server rejects: record waits instead of sending "no photo"',
    () async {
      blossom.allowedPubkeys = {'0' * 64};
      await at(
        () => a.db.insertBean(
          BeansCompanion.insert(
            name: 'Guji',
            photoPath: Value(a.photo('g.jpg', fakeJpeg(1000))),
          ),
        ),
      );
      final report = await a.sync();
      expect(report.notSent, 1);
      expect(relay.events, isEmpty);
      expect((await a.bean()).syncState, SyncState.pending);
      expect(
        a.blobs.errors[blossom.url],
        "This photo server doesn't accept your device key yet.",
      );
      blossom.allowedPubkeys = null;
      expect((await a.sync()).sent, 1);
    },
  );

  test('a modified file on the server is not accepted', () async {
    await at(
      () => a.db.insertBean(
        BeansCompanion.insert(
          name: 'Guji',
          photoPath: Value(a.photo('g.jpg', fakeJpeg(1000))),
        ),
      ),
    );
    await a.sync();
    final sha = blossom.blobs.keys.single;
    blossom.blobs[sha]![10] ^= 0xFF;
    await b.sync();
    expect((await b.bean()).photoPath, isNull);
    expect((await b.bean()).photoBlob, isNotNull, reason: 'retry later');
  });

  test('shot over 60 KB goes as a blob and arrives complete', () async {
    final notes = base64.encode(secureRandomBytes(60000));
    await at(
      () => a.db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 10, 9),
          notes: Value(notes),
        ),
        const [],
      ),
    );
    final report = await a.sync();
    expect(report.tooLarge, 0);
    expect(report.sent, 1);
    expect(relay.events.single.content.length, lessThan(2000));
    await b.sync();
    final onB = (await b.db.watchShotEntries().first).single.shot;
    expect(onB.notes, notes);
  });

  test('photo server added later: existing photos are uploaded then', () async {
    a.blobs.servers.clear();
    await at(
      () => a.db.insertBean(
        BeansCompanion.insert(
          name: 'Guji',
          photoPath: Value(a.photo('g.jpg', fakeJpeg(1000))),
        ),
      ),
    );
    await a.sync();
    expect(blossom.blobs, isEmpty);
    expect((await a.bean()).syncState, SyncState.synced);

    a.blobs.servers.add(blossom.url);
    await a.db.syncDao.markUnsentPhotosPending();
    await a.sync();
    expect(blossom.blobs, hasLength(1));
    await b.sync();
    expect((await b.bean()).photoPath, isNotNull);
  });

  test('photo server state: reachable, key rejected, gone', () async {
    await a.blobs.checkServers();
    expect(a.blobs.ok, {blossom.url});
    blossom.allowedPubkeys = {'0' * 64};
    await a.blobs.checkServers();
    expect(a.blobs.ok, isEmpty);
    expect(
      a.blobs.errors[blossom.url],
      "This photo server doesn't accept your device key yet.",
    );
    a.blobs.servers.add('http://127.0.0.1:1');
    await a.blobs.checkServers();
    expect(
      a.blobs.errors['http://127.0.0.1:1'],
      "Can't reach this photo server.",
    );
  });

  test('another photo server: existing photos go to all servers', () async {
    await at(
      () => a.db.insertBean(
        BeansCompanion.insert(
          name: 'Guji',
          photoPath: Value(a.photo('g.jpg', fakeJpeg(1000))),
        ),
      ),
    );
    await a.sync();
    await b.sync();
    final second = await TestBlossom.start();
    addTearDown(second.close);
    a.blobs.servers.add(second.url);
    await a.db.syncDao.reuploadLocalPhotos();
    await a.sync();
    expect(second.blobs, hasLength(1), reason: 'new server has the photo');
    expect((await a.bean()).photoBlob, contains(second.url));
    // B loads the new reference (same photo) and still has it.
    await b.sync();
    expect((await b.bean()).photoPath, isNotNull);
  });

  test('custom profile image arrives', () async {
    await a.db.upsertStoredProfile(
      StoredProfilesCompanion.insert(
        id: 'p1',
        name: 'Turbo',
        json: '{}',
        fetchedAt: DateTime(2026, 10, 1),
      ),
    );
    final bytes = fakeJpeg(3000);
    final dir = Directory(p.join(a.docs.path, 'profile_photos'))
      ..createSync(recursive: true);
    final path = p.join(dir.path, 'mine.jpg');
    File(path).writeAsBytesSync(bytes);
    await at(
      () => a.db.setProfileCustomImage('p1', path, machine: 'meticulous'),
    );
    await a.sync();
    await b.sync();
    final onB = await b.db.storedProfile('p1', machine: 'meticulous');
    expect(File(onB!.customImagePath!).readAsBytesSync(), bytes);
  });
}
