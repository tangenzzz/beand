import 'dart:typed_data';

import 'package:beand/sync/crypto/bytes.dart';
import 'package:beand/sync/crypto/dtag.dart';
import 'package:beand/sync/crypto/nip44.dart';
import 'package:beand/sync/crypto/nip49.dart';
import 'package:beand/sync/crypto/nostr_bech32.dart';
import 'package:beand/sync/crypto/secp256k1.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/identity/key_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NIP-19 (npub/nsec), example from the spec', () {
    const pubHex =
        '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';
    const npub =
        'npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg';
    const secHex =
        '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
    const nsec =
        'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5';

    test('encode and decode', () {
      expect(bech32Encode(npubPrefix, hexDecode(pubHex)), npub);
      expect(bech32Encode(nsecPrefix, hexDecode(secHex)), nsec);
      expect(hexEncode(bech32Decode(npubPrefix, npub)), pubHex);
      expect(hexEncode(bech32Decode(nsecPrefix, nsec)), secHex);
    });

    test('wrong prefix and broken checksum are rejected', () {
      expect(() => bech32Decode(nsecPrefix, npub), throwsFormatException);
      final broken = '${npub.substring(0, npub.length - 1)}q';
      expect(() => bech32Decode(npubPrefix, broken), throwsFormatException);
    });
  });

  group('NIP-49 (ncryptsec)', () {
    test('vector from the spec (password "nostr", log_n 16)', () async {
      final key = await nip49Decrypt(
        'ncryptsec1qgg9947rlpvqu76pj5ecreduf9jxhselq2nae2kghhvd5g7dgjtcxfqtd67p9m0w57lspw8gsq6yphnm8623nsl8xn9j4jdzz84zm3frztj3z7s35vpzmqf6ksu8r89qk5z2zxfmu5gv8th8wclt0h4p',
        'nostr',
      );
      expect(
        hexEncode(key),
        '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683',
      );
    });

    test('round trip; wrong password is detected', () async {
      final key = generatePrivateKey();
      // Small cost factor so the test stays fast.
      final encrypted = await nip49Encrypt(key, 'Kaffee', logN: 4);
      expect(encrypted, startsWith('ncryptsec1'));
      expect(await nip49Decrypt(encrypted, 'Kaffee'), key);
      await expectLater(
        nip49Decrypt(encrypted, 'Tee'),
        throwsA(isA<Nip49Exception>()),
      );
    });

    test('password is NFKC-normalized (example from the spec)', () async {
      final key = generatePrivateKey();
      // "ÅΩẛ̣" in two different Unicode forms.
      const composed = 'ÅΩẛ̣';
      const normalized = 'ÅΩṩ';
      final encrypted = await nip49Encrypt(key, composed, logN: 4);
      expect(await nip49Decrypt(encrypted, normalized), key);
    });

    test('invalid input', () async {
      await expectLater(
        nip49Decrypt(
          'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5',
          'x',
        ),
        throwsA(isA<Nip49Exception>()),
      );
    });
  });

  group('Keys', () {
    test('range is checked', () {
      expect(isValidPrivateKey(Uint8List(32)), isFalse);
      expect(isValidPrivateKey(Uint8List(31)..[30] = 1), isFalse);
      expect(isValidPrivateKey(bigIntToBytes(secp256k1Order, 32)), isFalse);
      expect(
        isValidPrivateKey(bigIntToBytes(secp256k1Order - BigInt.one, 32)),
        isTrue,
      );
    });

    test('public key of 1 is the generator (x)', () {
      expect(
        hexEncode(publicKeyOf(bigIntToBytes(BigInt.one, 32))),
        '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
      );
    });
  });

  group('SyncIdentity', () {
    test('never shows the private key when printed', () {
      final id = SyncIdentity.generate();
      expect(id.toString(), contains(id.npub));
      expect(id.toString(), isNot(contains(id.nsec)));
      expect(id.toString(), isNot(contains(hexEncode(id.privateKeyBytes))));
    });

    test('nsec round trip yields the same identity', () {
      final id = SyncIdentity.generate();
      final again = SyncIdentity.fromNsec(id.nsec);
      expect(again.publicKeyHex, id.publicKeyHex);
      expect(again.syncSecret, id.syncSecret);
    });

    test('message to self: only the same key can read it', () {
      final me = SyncIdentity.generate();
      final otherDevice = SyncIdentity.fromNsec(me.nsec);
      final stranger = SyncIdentity.generate();
      final payload = nip44Encrypt('{"type":"bean"}', me.selfConversationKey);
      expect(
        nip44Decrypt(payload, otherDevice.selfConversationKey),
        '{"type":"bean"}',
      );
      expect(
        () => nip44Decrypt(payload, stranger.selfConversationKey),
        throwsA(isA<Nip44Exception>()),
      );
    });
  });

  group('d-Tags', () {
    final secret = deriveSyncSecret(
      hexDecode(
        '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa',
      ),
    );

    test('stable per record, different per type/ID, 64 hex chars', () {
      final a = syncDTag(
        secret,
        'bean',
        'f0c1e0b8-0000-4000-8000-000000000001',
      );
      expect(
        a,
        syncDTag(secret, 'bean', 'f0c1e0b8-0000-4000-8000-000000000001'),
      );
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        a,
        isNot(syncDTag(secret, 'shot', 'f0c1e0b8-0000-4000-8000-000000000001')),
      );
      expect(
        a,
        isNot(syncDTag(secret, 'bean', 'f0c1e0b8-0000-4000-8000-000000000002')),
      );
      // Reveals neither type nor ID in plain text.
      expect(a, isNot(contains('bean')));
    });

    test('different key → different d tags; secret ≠ key', () {
      final other = deriveSyncSecret(generatePrivateKey());
      expect(
        syncDTag(other, 'bean', 'x'),
        isNot(syncDTag(secret, 'bean', 'x')),
      );
      expect(
        hexEncode(secret),
        isNot(
          '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa',
        ),
      );
    });
  });

  group('Key store', () {
    test('device ID stays the same, key can be deleted', () async {
      final store = InMemorySyncKeyStore();
      final device = await store.deviceId();
      expect(await store.deviceId(), device);
      expect(await store.readIdentity(), isNull);
      final id = SyncIdentity.generate();
      await store.writeIdentity(id);
      expect((await store.readIdentity())!.npub, id.npub);
      await store.deleteIdentity();
      expect(await store.readIdentity(), isNull);
      expect(await store.deviceId(), device);
    });
  });
}
