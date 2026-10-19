import 'dart:io';
import 'dart:typed_data';

import 'package:beand/database/database.dart';
import 'package:beand/models/gear.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/sync/blobs/blob_ref.dart';
import 'package:beand/sync/blobs/blob_sync.dart';
import 'package:beand/sync/blobs/blossom_client.dart';
import 'package:beand/sync/engine/sync_engine.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/records/setting_codec.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/relay_pool.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_blossom.dart';
import '../support/test_relay.dart';

// Gear photos (My Coffee Desk) live in a synced setting; the files travel
// encrypted via the photo servers like the bean photos.

void main() {
  late TestBlossom blossom;
  late SyncIdentity identity;
  late Directory docsA;
  late Directory docsB;

  BlobSync blobsFor(SyncIdentity id, Directory docs) => BlobSync(
    client: BlossomClient(identity: id),
    servers: [blossom.url],
    docsDir: () async => docs,
  );

  setUp(() async {
    blossom = await TestBlossom.start();
    identity = SyncIdentity.generate();
    docsA = Directory.systemTemp.createTempSync('gear_a');
    docsB = Directory.systemTemp.createTempSync('gear_b');
  });

  tearDown(() async {
    await blossom.close();
    docsA.deleteSync(recursive: true);
    docsB.deleteSync(recursive: true);
  });

  test(
    'cut-out and original go up once and arrive on the other phone',
    () async {
      final a = GearStore.inMemory(
        docsPath: docsA.path,
        gear: const [Gear(id: 'm', type: GearType.machine, model: 'Lelit')],
      );
      final picked = File(p.join(docsA.path, 'picked.jpg'))
        ..writeAsBytesSync([0xFF, 0xD8, 1, 2, 3]);
      await a.setPhoto('m', picked.path, cutout: Uint8List.fromList([9, 8, 7]));
      expect(a.byId('m')!.photoBlob, isNull, reason: 'not uploaded yet');

      final blobsA = blobsFor(identity, docsA);
      await a.upload(blobsA);
      final g = a.byId('m')!;
      expect(BlobRef.tryDecode(g.photoBlob), isNotNull);
      expect(BlobRef.tryDecode(g.photoOriginalBlob), isNotNull);
      expect(blossom.blobs, hasLength(2));
      // Nothing new: no second upload.
      await a.upload(blobsA);
      expect(blossom.uploads, 2);

      // Phone B gets the gear setting (same JSON) but not the files.
      final b = GearStore.inMemory(
        docsPath: docsB.path,
        gear: [Gear.fromJson(g.toJson())!],
      );
      expect(b.photoFile(b.byId('m')!), isNull);
      final fetched = await b.fetch(
        blobsFor(SyncIdentity.fromNsec(identity.nsec), docsB),
      );
      expect(fetched, 2);
      expect(b.photoFile(b.byId('m')!)!.readAsBytesSync(), [9, 8, 7]);
      expect(b.originalPhotoFile(b.byId('m')!)!.readAsBytesSync(), [
        0xFF,
        0xD8,
        1,
        2,
        3,
      ]);
      // Already there: nothing to fetch.
      expect(await b.fetch(blobsFor(identity, docsB)), 0);
    },
  );

  test(
    'back to the original keeps its reference, a new photo has none',
    () async {
      final a = GearStore.inMemory(
        docsPath: docsA.path,
        gear: const [Gear(id: 'm', type: GearType.machine, model: 'Lelit')],
      );
      final picked = File(p.join(docsA.path, 'picked.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      await a.setPhoto('m', picked.path, cutout: Uint8List.fromList([4, 5]));
      await a.upload(blobsFor(identity, docsA));
      final originalBlob = a.byId('m')!.photoOriginalBlob;

      a.useOriginalPhoto('m');
      expect(a.byId('m')!.photoBlob, originalBlob, reason: 'no new upload');
      expect(a.byId('m')!.photoOriginalBlob, isNull);

      await a.setPhoto('m', picked.path);
      expect(a.byId('m')!.photoBlob, isNull);

      await a.forget();
      await a.upload(blobsFor(identity, docsA));
      expect(a.byId('m')!.photoBlob, isNotNull);
    },
  );

  test(
    'the sync run uploads setting photos first, fetches them last',
    () async {
      final relay = await TestRelay.start();
      addTearDown(relay.close);
      final db = AppDatabase(NativeDatabase.memory())..deviceId = 'a';
      addTearDown(db.close);
      final pool = RelayPool(identity: identity)..setUrls([relay.url]);
      addTearDown(pool.closeAll);
      final calls = <String>[];
      final engine = SyncEngine(
        devicePresence: false,
        db: db,
        identity: identity,
        pool: pool,
        deviceId: 'a',
        stateStore: InMemorySyncStateStore(),
        blobs: blobsFor(identity, docsA),
        settings: SettingsBridge(
          prefs: () async => _Prefs(calls),
          reload: () async {},
          keys: const ['k'],
          photos: _Photos(calls),
        ),
      );
      await engine.run(force: true);
      expect(calls.first, 'upload');
      expect(calls.last, 'fetch');
      expect(calls, contains('read'));
    },
  );
}

class _Photos implements SettingsPhotos {
  _Photos(this.calls);
  final List<String> calls;
  @override
  Future<void> upload(BlobSync blobs) async => calls.add('upload');
  @override
  Future<int> fetch(BlobSync blobs) async {
    calls.add('fetch');
    return 0;
  }

  @override
  Future<void> forget() async => calls.add('forget');
}

// Records that the settings were read (= captured) in between.
class _Prefs implements SettingsStore {
  _Prefs(this.calls);
  final List<String> calls;
  @override
  Object? get(String key) {
    calls.add('read');
    return null;
  }

  @override
  Future<void> remove(String key) async {}
  @override
  Future<void> set(String key, Object value) async {}
}
