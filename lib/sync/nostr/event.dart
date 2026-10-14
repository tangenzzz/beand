import 'dart:convert';
import 'dart:typed_data';

import 'package:bip340/bip340.dart' as bip340;
import 'package:pointycastle/digests/sha256.dart';

import '../crypto/bytes.dart';
import '../identity/identity.dart';

// Nostr event per NIP-01: ID = sha256 of the canonical serialization,
// signature = BIP-340 Schnorr over the ID.
// https://github.com/nostr-protocol/nips/blob/master/01.md

/// NIP-78: app data, parameterized replaceable (per author + d tag only the
/// newest event counts).
const kindAppData = 30078;

/// NIP-09: deletion request for own events.
const kindDeletion = 5;

/// NIP-62: "Request to Vanish" — forget everything from this key.
const kindVanish = 62;

/// NIP-42: authentication to the relay.
const kindClientAuth = 22242;

class NostrEvent {
  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  /// New event, signed with [identity]. [createdAt] in Unix seconds.
  factory NostrEvent.sign({
    required SyncIdentity identity,
    required int kind,
    required List<List<String>> tags,
    required String content,
    required int createdAt,
  }) => NostrEvent.signWithKey(
    privateKey: identity.privateKeyBytes,
    publicKeyHex: identity.publicKeyHex,
    kind: kind,
    tags: tags,
    content: content,
    createdAt: createdAt,
  );

  /// Like [NostrEvent.sign], but with the bare key — for background isolates
  /// (event_worker.dart) that do not get a [SyncIdentity].
  factory NostrEvent.signWithKey({
    required Uint8List privateKey,
    required String publicKeyHex,
    required int kind,
    required List<List<String>> tags,
    required String content,
    required int createdAt,
  }) {
    final id = eventId(
      pubkey: publicKeyHex,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
    );
    final sig = bip340.sign(
      hexEncode(privateKey),
      id,
      hexEncode(secureRandomBytes(32)),
    );
    return NostrEvent(
      id: id,
      pubkey: publicKeyHex,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      sig: sig,
    );
  }

  /// From a relay's JSON. Throws [FormatException] if fields are missing or
  /// have the wrong type — only [isValid] checks the signature.
  factory NostrEvent.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Event is not an object');
    final tags = json['tags'];
    if (json['id'] is! String ||
        json['pubkey'] is! String ||
        json['created_at'] is! int ||
        json['kind'] is! int ||
        json['content'] is! String ||
        json['sig'] is! String ||
        tags is! List ||
        tags.any((t) => t is! List || t.any((v) => v is! String))) {
      throw const FormatException('Malformed event');
    }
    return NostrEvent(
      id: json['id'] as String,
      pubkey: json['pubkey'] as String,
      createdAt: json['created_at'] as int,
      kind: json['kind'] as int,
      tags: [for (final t in tags) List<String>.from(t as List)],
      content: json['content'] as String,
      sig: json['sig'] as String,
    );
  }

  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  Map<String, Object> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };

  /// First value of the first tag with this name.
  String? tag(String name) {
    for (final t in tags) {
      if (t.length >= 2 && t[0] == name) return t[1];
    }
    return null;
  }

  /// ID matches the content and the signature matches the author.
  bool get isValid {
    try {
      if (!_hex64.hasMatch(id) || !_hex64.hasMatch(pubkey)) return false;
      final expected = eventId(
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
      );
      return expected == id && bip340.verify(pubkey, id, sig);
    } catch (_) {
      return false;
    }
  }

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');
}

String eventId({
  required String pubkey,
  required int createdAt,
  required int kind,
  required List<List<String>> tags,
  required String content,
}) {
  final serialized = StringBuffer('[0,')
    ..write(_jsonString(pubkey))
    ..write(',$createdAt,$kind,[');
  for (var i = 0; i < tags.length; i++) {
    if (i > 0) serialized.write(',');
    serialized.write('[');
    for (var j = 0; j < tags[i].length; j++) {
      if (j > 0) serialized.write(',');
      serialized.write(_jsonString(tags[i][j]));
    }
    serialized.write(']');
  }
  serialized
    ..write('],')
    ..write(_jsonString(content))
    ..write(']');
  final bytes = Uint8List.fromList(utf8.encode(serialized.toString()));
  return hexEncode(SHA256Digest().process(bytes));
}

// String per NIP-01: only these seven characters are escaped, everything
// else (including non-ASCII) is written raw. jsonEncode additionally escapes
// other control characters — for some content that would produce a
// different ID than the relays compute.
String _jsonString(String value) {
  final out = StringBuffer('"');
  for (final rune in value.runes) {
    switch (rune) {
      case 0x0A:
        out.write(r'\n');
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0C:
        out.write(r'\f');
      default:
        out.writeCharCode(rune);
    }
  }
  out.write('"');
  return out.toString();
}
