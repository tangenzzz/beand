import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../crypto/dtag.dart';
import '../crypto/nip44.dart';
import '../identity/identity.dart';
import '../nostr/event.dart';
import '../records/sync_envelope.dart';

// The sync's computation runs in a background isolate, otherwise the UI
// freezes. Measured on a PC: signing and verifying a signature ~11 ms each
// (bip340 in pure Dart), NIP-44 at 50 kB ~3 ms. Fetching used to verify all
// events in one go in a loop — 50 events ~0.5 s without a frame, a multiple
// of that on a phone, and on every sync, because the last 10 minutes
// (sinceSlack) are fetched again.

/// What a background isolate needs from the sync key — bytes only, so it
/// can be sent.
class SyncKeys {
  SyncKeys.of(SyncIdentity identity)
    : privateKey = identity.privateKeyBytes,
      publicKeyHex = identity.publicKeyHex,
      conversationKey = identity.selfConversationKey,
      syncSecret = identity.syncSecret;

  final Uint8List privateKey;
  final String publicKeyHex;
  final Uint8List conversationKey;
  final Uint8List syncSecret;
}

/// Verify and open all [events], in the background; null = skip.
/// Same order as [events].
Future<List<SyncEnvelope?>> openEvents(
  List<NostrEvent> events,
  SyncKeys keys,
) async {
  if (events.isEmpty) return const [];
  return Isolate.run(() => [for (final e in events) openEvent(e, keys)]);
}

/// Verify and open an event; null = skip.
SyncEnvelope? openEvent(NostrEvent event, SyncKeys keys) {
  if (event.kind != kindAppData ||
      event.pubkey != keys.publicKeyHex ||
      !event.isValid) {
    return null;
  }
  try {
    final envelope = SyncEnvelope.decode(
      nip44Decrypt(event.content, keys.conversationKey),
    );
    // The d-tag must match the content — otherwise an event could displace
    // another record.
    if (event.tag('d') !=
        syncDTag(keys.syncSecret, envelope.type, envelope.id)) {
      return null;
    }
    return envelope;
  } catch (e) {
    debugPrint('Sync: unreadable event ${event.id}: $e');
    return null;
  }
}

/// Build a record event: encrypt and sign, in the background.
Future<NostrEvent> sealEvent({
  required SyncKeys keys,
  required String dTag,
  required String plain,
  required int createdAt,
}) => Isolate.run(
  () => NostrEvent.signWithKey(
    privateKey: keys.privateKey,
    publicKeyHex: keys.publicKeyHex,
    kind: kindAppData,
    tags: [
      ['d', dTag],
    ],
    content: nip44Encrypt(plain, keys.conversationKey),
    createdAt: createdAt,
  ),
);
