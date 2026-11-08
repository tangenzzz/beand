import 'dart:convert';

import 'package:beand/sync/crypto/nip44.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/event.dart';
import 'package:beand/sync/records/sync_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

// strfry (relay.damus.io, nos.lol, relay.primal.net, …) rejects events
// whose JSON is larger than this by default (strfry.conf:
// events.maxEventSize). Inline sync events must stay below it.
const _strfryMaxEventSize = 65536;

void main() {
  final identity = SyncIdentity.generate();

  int eventJsonBytes(int plainBytes) {
    final event = NostrEvent.sign(
      identity: identity,
      kind: kindAppData,
      tags: [
        // A real d-tag: same length as for every record.
        ['d', identity.dTag('shot', '0b7c5e0e-6a43-4c39-9f1e-2d9a8c3b1f00')],
      ],
      content: nip44Encrypt('x' * plainBytes, identity.selfConversationKey),
      createdAt: 1790000000,
    );
    return utf8.encode(jsonEncode(event.toJson())).length;
  }

  test('largest inline envelope fits into a default strfry relay', () {
    expect(
      eventJsonBytes(maxInlineEnvelopeBytes),
      lessThanOrEqualTo(_strfryMaxEventSize),
    );
  });

  test('one byte more would not (padding jumps to the next step)', () {
    // Documents why the limit is exactly here and not higher: if this
    // fails, NIP-44 padding changed and the limit can be revisited.
    expect(
      eventJsonBytes(maxInlineEnvelopeBytes + 1),
      greaterThan(_strfryMaxEventSize),
    );
  });

  test('padding step matches the limit', () {
    expect(calcPaddedLength(maxInlineEnvelopeBytes), maxInlineEnvelopeBytes);
    expect(calcPaddedLength(maxInlineEnvelopeBytes + 1), 49152);
  });
}
