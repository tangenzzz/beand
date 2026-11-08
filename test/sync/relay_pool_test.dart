import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/event.dart';
import 'package:beand/sync/nostr/relay_info.dart';
import 'package:beand/sync/nostr/relay_pool.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_relay.dart';

// Consideration for public relays: spacing between events, pause after
// "rate-limited"/"banned" (damus blocked after the first large upload).

void main() {
  late TestRelay relay;
  late SyncIdentity identity;
  var clock = DateTime(2026, 10, 10, 12);

  NostrEvent event(int i, {int contentLength = 1}) => NostrEvent.sign(
    identity: identity,
    kind: kindAppData,
    tags: [
      ['d', 'x$i'],
    ],
    content: 'x' * contentLength,
    createdAt: 1790000000 + i,
  );

  setUp(() async {
    relay = await TestRelay.start();
    identity = SyncIdentity.generate();
  });
  tearDown(() => relay.close());

  test(
    'events to the same relay are spaced, even when sent in parallel',
    () async {
      final pool = RelayPool(
        identity: identity,
        minSendInterval: const Duration(milliseconds: 100),
      )..setUrls([relay.url]);
      addTearDown(pool.closeAll);
      final watch = Stopwatch()..start();
      await Future.wait([for (var i = 0; i < 5; i++) pool.publish(event(i))]);
      watch.stop();
      expect(relay.events, hasLength(5));
      // 5 events, 4 gaps of 100 ms each (individual gaps vary under load,
      // the sum does not).
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(390));
    },
  );

  test('after closing, the last state (green) remains', () async {
    final pool = RelayPool(identity: identity, minSendInterval: Duration.zero)
      ..setUrls([relay.url]);
    expect(pool.statusOf(relay.url).state, RelayState.idle);
    await pool.publish(event(1));
    expect(pool.statusOf(relay.url).state, RelayState.connected);
    await pool.closeAll();
    expect(pool.statusOf(relay.url).state, RelayState.connected);
  });

  for (final (message, pause) in [
    ('rate-limited: slow down', RelayPool.rateLimitedPause),
    (
      'banned: too many rate-limit violations, try again later',
      RelayPool.bannedPause,
    ),
  ]) {
    test('"$message" → pause, also on Sync now, readable message', () async {
      final pool = RelayPool(
        identity: identity,
        minSendInterval: Duration.zero,
        now: () => clock,
      )..setUrls([relay.url]);
      addTearDown(pool.closeAll);
      relay.rejectWith = message;
      await pool.publish(event(1));
      expect(
        pool.statusOf(relay.url).message,
        'This server is slowing us down for a while — the others carry on.',
      );
      relay.rejectWith = null;
      final count = relay.received.length;
      await pool.publish(event(2), force: true);
      expect(relay.received.length, count, reason: 'not touched');
      clock = clock.add(pause + const Duration(seconds: 1));
      final after = await pool.publish(event(3), force: true);
      expect(after[relay.url]?.accepted, isTrue);
    });
  }

  group('size limits', () {
    test('NIP-11 limit: too large is skipped, not sent, not red', () async {
      relay.info = {
        'name': 'small',
        'limitation': {'max_message_length': 2000},
      };
      final pool = RelayPool(
        identity: identity,
        minSendInterval: Duration.zero,
        infoFetcher: fetchRelayInfo,
      )..setUrls([relay.url]);
      addTearDown(pool.closeAll);

      final small = await pool.publish(event(1));
      expect(small[relay.url]?.accepted, isTrue);
      final count = relay.received.length;

      final big = await pool.publish(event(2, contentLength: 5000));
      expect(big[relay.url]?.accepted, isFalse);
      expect(big[relay.url]?.tooLarge, isTrue);
      expect(relay.received.length, count, reason: 'not sent at all');
      expect(pool.statusOf(relay.url).state, RelayState.connected);

      await pool.publish(event(3));
      expect(relay.infoRequests, 1, reason: 'NIP-11 is cached');
    });

    test('learns the limit from a "too large" rejection', () async {
      relay.maxMessageBytes = 2000;
      final pool = RelayPool(identity: identity, minSendInterval: Duration.zero)
        ..setUrls([relay.url]);
      addTearDown(pool.closeAll);

      final first = await pool.publish(event(1, contentLength: 5000));
      expect(first[relay.url]?.tooLarge, isTrue);
      expect(pool.statusOf(relay.url).state, RelayState.connected);
      final count = relay.received.length;

      final second = await pool.publish(event(2, contentLength: 6000));
      expect(second[relay.url]?.tooLarge, isTrue);
      expect(relay.received.length, count, reason: 'known too large');

      final small = await pool.publish(event(3));
      expect(small[relay.url]?.accepted, isTrue);
    });

    test('relay without NIP-11: everything is sent', () async {
      final pool = RelayPool(
        identity: identity,
        minSendInterval: Duration.zero,
        infoFetcher: fetchRelayInfo,
      )..setUrls([relay.url]);
      addTearDown(pool.closeAll);
      final r = await pool.publish(event(1, contentLength: 5000));
      expect(r[relay.url]?.accepted, isTrue);
    });
  });
}
