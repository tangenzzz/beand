import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beand/sync/crypto/bytes.dart';
import 'package:beand/sync/crypto/nip44.dart';
import 'package:beand/sync/crypto/secp256k1.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/sha256.dart';

// NIP-44 v2 against the official test vectors
// (test/fixtures/nip44.vectors.README.md).

String _sha256Hex(List<int> data) =>
    hexEncode(SHA256Digest().process(Uint8List.fromList(data)));

void main() {
  final file = File('test/fixtures/nip44.vectors.json');
  final v2 = (jsonDecode(file.readAsStringSync()) as Map)['v2'] as Map;
  final valid = v2['valid'] as Map;
  final invalid = v2['invalid'] as Map;
  Uint8List h(Object? s) => hexDecode(s as String);

  test('vector file is the one from the spec (checksum)', () {
    expect(
      _sha256Hex(file.readAsBytesSync()),
      '269ed0f69e4c192512cc779e78c555090cebc7c785b609e338a62afc3ce25040',
    );
  });

  test('valid.get_conversation_key', () {
    final cases = valid['get_conversation_key'] as List;
    expect(cases, isNotEmpty);
    for (final c in cases.cast<Map>()) {
      expect(
        hexEncode(conversationKey(h(c['sec1']), h(c['pub2']))),
        c['conversation_key'],
        reason: c['note']?.toString(),
      );
    }
  });

  test('valid.get_message_keys', () {
    final data = valid['get_message_keys'] as Map;
    final key = h(data['conversation_key']);
    for (final c in (data['keys'] as List).cast<Map>()) {
      final keys = messageKeys(key, h(c['nonce']));
      expect(hexEncode(keys.chachaKey), c['chacha_key']);
      expect(hexEncode(keys.chachaNonce), c['chacha_nonce']);
      expect(hexEncode(keys.hmacKey), c['hmac_key']);
    }
  });

  test('valid.calc_padded_len', () {
    for (final c in (valid['calc_padded_len'] as List).cast<List>()) {
      expect(calcPaddedLength(c[0] as int), c[1], reason: 'len ${c[0]}');
    }
  });

  test('valid.encrypt_decrypt (both directions)', () {
    for (final c in (valid['encrypt_decrypt'] as List).cast<Map>()) {
      final sec1 = h(c['sec1']);
      final sec2 = h(c['sec2']);
      final key = conversationKey(sec1, publicKeyOf(sec2));
      expect(hexEncode(key), c['conversation_key']);
      final payload = nip44Encrypt(
        c['plaintext'] as String,
        key,
        nonce: h(c['nonce']),
      );
      expect(payload, c['payload']);
      final back = conversationKey(sec2, publicKeyOf(sec1));
      expect(hexEncode(back), c['conversation_key']);
      expect(nip44Decrypt(payload, back), c['plaintext']);
    }
  });

  test('valid.encrypt_decrypt_long_msg (checksums)', () {
    for (final c in (valid['encrypt_decrypt_long_msg'] as List).cast<Map>()) {
      final plaintext = (c['pattern'] as String) * (c['repeat'] as int);
      expect(_sha256Hex(utf8.encode(plaintext)), c['plaintext_sha256']);
      final key = h(c['conversation_key']);
      final payload = nip44Encrypt(plaintext, key, nonce: h(c['nonce']));
      expect(_sha256Hex(utf8.encode(payload)), c['payload_sha256']);
      expect(nip44Decrypt(payload, key), plaintext);
    }
  });

  test('invalid.encrypt_msg_lengths', () {
    final key = Uint8List(32)..fillRange(0, 32, 1);
    for (final length in (invalid['encrypt_msg_lengths'] as List).cast<int>()) {
      expect(
        () => nip44Encrypt('a' * length, key),
        throwsA(isA<Nip44Exception>()),
        reason: 'length $length',
      );
    }
  });

  test('invalid.get_conversation_key', () {
    for (final c in (invalid['get_conversation_key'] as List).cast<Map>()) {
      expect(
        () => conversationKey(h(c['sec1']), h(c['pub2'])),
        throwsA(isA<InvalidKeyException>()),
        reason: c['note']?.toString(),
      );
    }
  });

  test('invalid.decrypt', () {
    for (final c in (invalid['decrypt'] as List).cast<Map>()) {
      expect(
        () => nip44Decrypt(c['payload'] as String, h(c['conversation_key'])),
        throwsA(isA<Nip44Exception>()),
        reason: c['note']?.toString(),
      );
    }
  });

  test('without a given nonce: different every time, both readable', () {
    final key = conversationKey(
      h('0000000000000000000000000000000000000000000000000000000000000001'),
      publicKeyOf(
        h('0000000000000000000000000000000000000000000000000000000000000002'),
      ),
    );
    final a = nip44Encrypt('Guji Natural ☕', key);
    final b = nip44Encrypt('Guji Natural ☕', key);
    expect(a, isNot(b));
    expect(nip44Decrypt(a, key), 'Guji Natural ☕');
    expect(nip44Decrypt(b, key), 'Guji Natural ☕');
  });
}
