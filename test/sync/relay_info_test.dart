import 'package:beand/sync/nostr/relay_info.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_relay.dart';

void main() {
  test('NIP-11 address from the relay address', () {
    expect(relayInfoUri('wss://nos.lol').toString(), 'https://nos.lol');
    expect(
      relayInfoUri('wss://relay.example/sync').toString(),
      'https://relay.example/sync',
    );
    expect(
      relayInfoUri('ws://192.168.1.5:7777').toString(),
      'http://192.168.1.5:7777',
    );
  });

  group('RelayLimits.fromNip11', () {
    test('reads the limitation block', () {
      final l = RelayLimits.fromNip11({
        'limitation': {
          'max_message_length': 65536,
          'max_content_length': 8196,
          'auth_required': true,
          'restricted_writes': true,
        },
      });
      expect(l.maxMessageLength, 65536);
      expect(l.maxContentLength, 8196);
      expect(l.authRequired, isTrue);
      expect(l.paymentRequired, isFalse);
      expect(l.restrictedWrites, isTrue);
    });

    test('missing, zero or broken values mean "unknown"', () {
      for (final info in <Map<String, Object?>?>[
        null,
        {},
        {'limitation': 'nope'},
        {
          'limitation': {'max_message_length': 0, 'max_content_length': -1},
        },
        {
          'limitation': {'max_message_length': '65536'},
        },
      ]) {
        final l = RelayLimits.fromNip11(info);
        expect(l.maxMessageLength, isNull, reason: '$info');
        expect(l.maxContentLength, isNull, reason: '$info');
      }
    });

    test('allows() checks message bytes and content length', () {
      const l = RelayLimits(maxMessageLength: 1000, maxContentLength: 500);
      expect(
        l.allows(const EventSize(messageBytes: 1000, contentLength: 500)),
        isTrue,
      );
      expect(
        l.allows(const EventSize(messageBytes: 1001, contentLength: 10)),
        isFalse,
      );
      expect(
        l.allows(const EventSize(messageBytes: 600, contentLength: 501)),
        isFalse,
      );
      expect(
        RelayLimits.unknown.allows(
          const EventSize(messageBytes: 1 << 20, contentLength: 1 << 20),
        ),
        isTrue,
      );
    });
  });

  test('"too large" wording is recognized, rate limits and quotas are not', () {
    for (final m in [
      'invalid: event too large: 66078',
      'error: message too big',
      'invalid: content too long',
      'event exceeds max size',
      'invalid: exceeds max_message_length',
    ]) {
      expect(isTooLargeMessage(m), isTrue, reason: m);
    }
    for (final m in [
      'rate-limited: slow down',
      'banned: too many rate-limit violations',
      'blocked: storage quota exceeded',
      'blocked: pubkey not allowed',
      '',
    ]) {
      expect(isTooLargeMessage(m), isFalse, reason: m);
    }
  });

  group('fetchRelayInfo', () {
    late TestRelay relay;
    setUp(() async => relay = await TestRelay.start());
    tearDown(() => relay.close());

    test('loads the document with the nostr+json Accept header', () async {
      relay.info = {
        'name': 'test',
        'limitation': {'max_message_length': 4096},
      };
      final info = await fetchRelayInfo(relayInfoUri(relay.url));
      expect(info?['name'], 'test');
      expect(RelayLimits.fromNip11(info).maxMessageLength, 4096);
    });

    test('no document or unreachable: null, never an exception', () async {
      expect(await fetchRelayInfo(relayInfoUri(relay.url)), isNull);
      relay.down = true;
      expect(await fetchRelayInfo(relayInfoUri(relay.url)), isNull);
      expect(await fetchRelayInfo(Uri.parse('http://127.0.0.1:1')), isNull);
    });
  });
}
