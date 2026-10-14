import 'package:beand/sync/engine/event_worker.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/event.dart';
import 'package:beand/sync/records/sync_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

// Signing/verifying/encrypting/decrypting and key derivation in the
// background isolate: the same result as before in the main isolate.

void main() {
  final identity = SyncIdentity.generate();
  final keys = SyncKeys.of(identity);
  const envelope = SyncEnvelope(
    type: 'bean',
    id: 'abc',
    updatedAt: 1,
    deviceId: 'dev',
    deleted: false,
    data: {'name': 'Guji'},
  );

  Future<NostrEvent> seal({String? dTag, SyncKeys? withKeys}) => sealEvent(
    keys: withKeys ?? keys,
    dTag: dTag ?? identity.dTag('bean', 'abc'),
    plain: envelope.encode(),
    createdAt: 1790000000,
  );

  NostrEvent copy(NostrEvent e, {String? content, int? createdAt}) =>
      NostrEvent(
        id: e.id,
        pubkey: e.pubkey,
        createdAt: createdAt ?? e.createdAt,
        kind: e.kind,
        tags: e.tags,
        content: content ?? e.content,
        sig: e.sig,
      );

  test('seals in the background, opens in the background', () async {
    final event = await seal();
    expect(event.isValid, isTrue);
    expect(event.kind, kindAppData);
    final opened = await openEvents([event], keys);
    expect(opened.single?.data, {'name': 'Guji'});
    expect(opened.single?.id, 'abc');
  });

  test('tampered, foreign and wrongly tagged events are dropped', () async {
    final good = await seal();
    final other = SyncKeys.of(SyncIdentity.generate());
    final opened = await openEvents([
      copy(good, createdAt: good.createdAt + 1),
      await seal(withKeys: other),
      await seal(dTag: identity.dTag('bean', 'other')),
      good,
    ], keys);
    expect(opened.take(3), everyElement(isNull));
    expect(opened.last, isNotNull, reason: 'order is preserved');
  });

  test('deriving the key in the background: same as directly', () async {
    final bg = await SyncIdentity.fromPrivateKeyInBackground(
      identity.privateKeyBytes,
    );
    expect(bg.publicKeyHex, identity.publicKeyHex);
    expect(bg.syncSecret, identity.syncSecret);
    expect(bg.selfConversationKey, identity.selfConversationKey);
    expect(bg.nsec, identity.nsec);
  });

  test('no events: no isolate, empty list', () async {
    expect(await openEvents(const [], keys), isEmpty);
  });
}
