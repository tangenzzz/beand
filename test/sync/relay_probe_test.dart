import 'dart:convert';
import 'dart:io';

import 'package:beand/sync/crypto/bytes.dart';
import 'package:beand/sync/crypto/nip44.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/event.dart';
import 'package:beand/sync/nostr/relay_connection.dart';
import 'package:beand/sync/records/sync_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

// Checks whether a relay is suitable: does it accept small and large
// kind-30078 events, does it replace the same record with the newer one,
// does it return it on fetch? Only runs on demand — it PUBLISHES encrypted
// test events (test key, content replaced by tombstones at the end):
//
//   BEAND_PROBE_RELAYS=wss://relay.damus.io,wss://nos.lol \
//   BEAND_TEST_KEY=~/.config/beand-test/key-a.sec \
//   flutter test test/sync/relay_probe_test.dart

void main() {
  final relays = Platform.environment['BEAND_PROBE_RELAYS'];
  final keyPath = Platform.environment['BEAND_TEST_KEY'];
  final skip = relays == null || keyPath == null
      ? 'BEAND_PROBE_RELAYS / BEAND_TEST_KEY not set'
      : false;

  for (final url in (relays ?? '').split(',').where((u) => u.isNotEmpty)) {
    test(
      'Relay-Probe $url',
      () async {
        final identity = SyncIdentity.fromPrivateKey(
          hexDecode(
            File(keyPath!.replaceFirst('~', Platform.environment['HOME']!))
                .readAsStringSync()
                .trim(),
          ),
        );
        final connection = RelayConnection(
          url,
          identity: identity,
          timeout: const Duration(seconds: 20),
        );
        await connection.connect();
        addTearDown(connection.close);
        final results = <String, String>{};
        var clock = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        NostrEvent event(
          String id,
          Map<String, Object?> data, {
          bool deleted = false,
        }) {
          final envelope = SyncEnvelope(
            type: 'probe',
            id: id,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            deviceId: 'probe',
            deleted: deleted,
            data: data,
          );
          return NostrEvent.sign(
            identity: identity,
            kind: kindAppData,
            tags: [
              ['d', identity.dTag('probe', id)],
            ],
            content: nip44Encrypt(
              envelope.encode(),
              identity.selfConversationKey,
            ),
            createdAt: clock++,
          );
        }

        Future<PublishResult> send(NostrEvent e) async {
          final r = await connection.publish(e);
          return r;
        }

        final smallId = 'small-${DateTime.now().microsecondsSinceEpoch}';
        final bigId = 'big-${DateTime.now().microsecondsSinceEpoch}';

        // 1. small (like a bean)
        final small = event(smallId, {'name': 'probe v1'});
        final r1 = await send(small);
        results['small'] = '${r1.accepted} ${r1.message}';

        // 2. large (~30 KB, like the largest shot including its curve)
        final noise = base64.encode(secureRandomBytes(16000));
        final big = event(bigId, {'curve': noise});
        final r2 = await send(big);
        results['big (${big.content.length} chars)'] =
            '${r2.accepted} ${r2.message}';

        // 3. replace: newer version of the same record
        final small2 = event(smallId, {'name': 'probe v2'});
        final r3 = await send(small2);
        results['replace send'] = '${r3.accepted} ${r3.message}';
        await Future<void>.delayed(const Duration(seconds: 2));

        // 4. fetch
        final found = await connection.query({
          'kinds': [kindAppData],
          'authors': [identity.publicKeyHex],
          '#d': [
            identity.dTag('probe', smallId),
            identity.dTag('probe', bigId),
          ],
        });
        final smallVersions = found
            .where((e) => e.tag('d') == identity.dTag('probe', smallId))
            .map(
              (e) => SyncEnvelope.decode(
                nip44Decrypt(e.content, identity.selfConversationKey),
              ).data['name'],
            )
            .toList();
        results['query small'] = '$smallVersions';
        results['query big'] =
            '${found.any((e) => e.tag('d') == identity.dTag('probe', bigId))}';

        // 5. clean up: tombstones replace the contents
        final t1 = await send(event(smallId, {}, deleted: true));
        final t2 = await send(event(bigId, {}, deleted: true));
        results['cleanup'] = '${t1.accepted}/${t2.accepted}';

        // ignore: avoid_print
        print('PROBE $url: ${jsonEncode(results)}');
        expect(r1.accepted, isTrue, reason: r1.message);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
