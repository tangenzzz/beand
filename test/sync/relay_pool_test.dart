import 'package:beand/services/connection_log.dart';
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

  group('what the server list shows', () {
    RelayPool pool() {
      final p = RelayPool(identity: identity, minSendInterval: Duration.zero)
        ..setUrls([relay.url]);
      addTearDown(p.closeAll);
      return p;
    }

    test('only a lasting refusal asks for action', () {
      for (final (raw, problem) in [
        ('rate-limited: slow down', RelayProblem.throttled),
        ('banned: too many violations', RelayProblem.throttled),
        ('blocked: pubkey not allowed', RelayProblem.rejected),
        ('restricted: sign up first', RelayProblem.rejected),
        ('invalid: created_at too early', RelayProblem.rejected),
        ('Could not connect: 503', RelayProblem.temporary),
        ('No answer from server', RelayProblem.temporary),
        ('invalid: bad event', RelayProblem.temporary),
      ]) {
        expect(relayProblem(raw), problem, reason: raw);
      }
    });

    test('throttled: no action needed, not counted as missed', () async {
      final p = pool();
      relay.rejectWith = 'rate-limited: slow down';
      await p.publish(event(1));
      for (var i = 0; i < missedRunsUntilNoted; i++) {
        p.noteRunFinished();
      }
      final status = p.statusOf(relay.url);
      expect(status.state, RelayState.error);
      expect(status.needsAction, isFalse);
      expect(status.notReachedLately, isFalse);
    });

    test('refused: asks for action, with its message', () async {
      final p = pool();
      relay.rejectWith = 'blocked: pubkey not allowed';
      await p.publish(event(1));
      expect(p.statusOf(relay.url).needsAction, isTrue);
      expect(
        p.statusOf(relay.url).message,
        "This server doesn't accept your device key yet.",
      );
    });

    test(
      'unreachable: mentioned only after several runs, then clears',
      () async {
        final p = pool();
        relay.down = true;
        await p.publish(event(1), force: true);
        for (var i = 1; i < missedRunsUntilNoted; i++) {
          p.noteRunFinished();
          expect(p.statusOf(relay.url).notReachedLately, isFalse);
        }
        p.noteRunFinished();
        expect(p.statusOf(relay.url).notReachedLately, isTrue);
        expect(p.statusOf(relay.url).needsAction, isFalse);

        relay.down = false;
        await p.publish(event(2), force: true);
        p.noteRunFinished();
        expect(p.statusOf(relay.url).state, RelayState.connected);
        expect(p.statusOf(relay.url).notReachedLately, isFalse);
      },
    );

    test('the real reason goes to the connection log, once', () async {
      final lines = <String>[];
      ConnectionLog.sink = lines.add;
      addTearDown(() => ConnectionLog.sink = null);
      final p = pool();
      relay.rejectWith = 'invalid: bad event';
      await p.publish(event(1));
      await p.publish(event(2));
      expect(
        lines.where((l) => l.contains('invalid: bad event')),
        hasLength(1),
      );
    });
  });

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
