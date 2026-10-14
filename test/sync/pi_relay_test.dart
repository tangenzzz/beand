import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/sync/blobs/blob_sync.dart';
import 'package:beand/sync/blobs/blossom_client.dart';
import 'package:beand/sync/crypto/bytes.dart';
import 'package:beand/sync/engine/sync_engine.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/relay_pool.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Two devices against a REAL relay (a self-hosted strfry). Only runs on
// request and only with a test key allowed there (policy/pubkeys.txt):
//
//   BEAND_TEST_RELAY=ws://<relay-host>:7777 \
//   BEAND_TEST_KEY=~/.config/beand-test/key-a.sec \
//   flutter test test/sync/pi_relay_test.dart
//
// With BEAND_TEST_BLOSSOM=http://<relay-host>:3000 additionally an
// encrypted test photo goes over Blossom and back.
//
// Leaves only encrypted events of the test key on the relay (the test bean
// ends up as a tombstone).

void main() {
  final url = Platform.environment['BEAND_TEST_RELAY'];
  final keyPath = Platform.environment['BEAND_TEST_KEY'];
  final skip = url == null || keyPath == null
      ? 'BEAND_TEST_RELAY / BEAND_TEST_KEY not set'
      : false;

  test(
    'A creates, changes, deletes → B follows via the real relay',
    () async {
      final key = hexDecode(
        File(keyPath!.replaceFirst('~', Platform.environment['HOME']!))
            .readAsStringSync()
            .trim(),
      );
      final identity = SyncIdentity.fromPrivateKey(key);

      (AppDatabase, RelayPool, SyncEngine) device(String name) {
        final db = AppDatabase(NativeDatabase.memory())..deviceId = name;
        final pool = RelayPool(identity: identity)..setUrls([url!]);
        final engine = SyncEngine(
          db: db,
          identity: identity,
          pool: pool,
          deviceId: name,
          stateStore: InMemorySyncStateStore(),
        );
        return (db, pool, engine);
      }

      final (dbA, poolA, a) = device('pi-test-a');
      final (dbB, poolB, b) = device('pi-test-b');
      addTearDown(() async {
        await poolA.closeAll();
        await poolB.closeAll();
        await dbA.close();
        await dbB.close();
      });

      final name = 'Pi test ${DateTime.now().toIso8601String()}';
      final bean = await dbA.insertBean(BeansCompanion.insert(name: name));
      final sent = await a.run(force: true);
      expect(sent.sent, 1, reason: '$sent ${poolA.statusOf(url!).message}');

      // B fetches everything (first sync, including events from earlier
      // test runs).
      final first = await b.run(force: true);
      expect(first.failedRelays, isEmpty, reason: '$first');
      final onB = (await dbB.allBeans()).where((x) => x.syncId == bean.syncId);
      expect(onB.single.name, name);
      // ignore: avoid_print
      print('Pi: $first');

      await Future<void>.delayed(const Duration(seconds: 1));
      await dbB.updateBean(
        onB.single.id,
        const BeansCompanion(roaster: Value('Pi roaster')),
      );
      await b.run(force: true);
      await a.run(force: true);
      final back = (await dbA.allBeans()).firstWhere(
        (x) => x.syncId == bean.syncId,
      );
      expect(back.roaster, 'Pi roaster');

      await Future<void>.delayed(const Duration(seconds: 1));
      await dbA.deleteBean(back.id);
      await a.run(force: true);
      await b.run(force: true);
      expect(
        (await dbB.allBeans()).where((x) => x.syncId == bean.syncId),
        isEmpty,
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  final blossom = Platform.environment['BEAND_TEST_BLOSSOM'];
  test(
    'photo over the real Blossom and back',
    () async {
      final identity = SyncIdentity.fromPrivateKey(
        hexDecode(
          File(keyPath!.replaceFirst('~', Platform.environment['HOME']!))
              .readAsStringSync()
              .trim(),
        ),
      );
      final docs = Directory.systemTemp.createTempSync('beand_pi_blob');
      addTearDown(() => docs.deleteSync(recursive: true));
      final store = BlobSync(
        client: BlossomClient(identity: identity),
        servers: [blossom!],
        docsDir: () async => docs,
      );
      final photo = secureRandomBytes(150000);
      final ref = await store.uploadBytes(photo, extension: '.jpg');
      expect(ref, isNotNull, reason: '${store.errors}');
      final back = await store.downloadBytes(ref!);
      expect(back, photo);
      // ignore: avoid_print
      print('Pi Blossom: ${ref.size} B at ${ref.urls}');
    },
    skip: blossom == null || keyPath == null
        ? 'BEAND_TEST_BLOSSOM / BEAND_TEST_KEY not set'
        : false,
  );
}
