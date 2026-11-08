import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'event.dart';

// What a relay says about itself (NIP-11): fetched over HTTP from the same
// address with `Accept: application/nostr+json`. Only the limits matter
// here — so that an event a relay cannot take is not sent to it at all,
// and the relay is not shown as broken because of it.

/// Loads the NIP-11 document; null if the relay has none or is unreachable.
/// Must never throw.
typedef RelayInfoFetcher = Future<Map<String, Object?>?> Function(Uri uri);

/// wss://host/path → https://host/path, ws:// → http://.
Uri relayInfoUri(String relayUrl) {
  final uri = Uri.parse(relayUrl);
  final scheme = switch (uri.scheme) {
    'wss' => 'https',
    'ws' => 'http',
    final other => other,
  };
  return uri.replace(scheme: scheme);
}

/// Default fetcher with package:http. [client] null = a fresh one per call.
Future<Map<String, Object?>?> fetchRelayInfo(
  Uri uri, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(uri, headers: const {'Accept': 'application/nostr+json'})
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    return json is Map ? Map<String, Object?>.from(json) : null;
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

class RelayLimits {
  const RelayLimits({
    this.maxMessageLength,
    this.maxContentLength,
    this.authRequired = false,
    this.paymentRequired = false,
    this.restrictedWrites = false,
  });

  /// Nothing known: everything is sent, the relay decides.
  static const unknown = RelayLimits();

  /// Bytes of one incoming WebSocket message (`["EVENT",{…}]`).
  final int? maxMessageLength;

  /// Characters in an event's `content`.
  final int? maxContentLength;

  // Informative for now (relay probe, later perhaps the server list).
  final bool authRequired;
  final bool paymentRequired;
  final bool restrictedWrites;

  /// Reads `limitation` from a NIP-11 document. Missing, zero, negative or
  /// non-numeric values count as "no limit known".
  factory RelayLimits.fromNip11(Map<String, Object?>? info) {
    final raw = info?['limitation'];
    if (raw is! Map) return unknown;
    int? positive(Object? v) => v is num && v > 0 ? v.toInt() : null;
    return RelayLimits(
      maxMessageLength: positive(raw['max_message_length']),
      maxContentLength: positive(raw['max_content_length']),
      authRequired: raw['auth_required'] == true,
      paymentRequired: raw['payment_required'] == true,
      restrictedWrites: raw['restricted_writes'] == true,
    );
  }

  bool allows(EventSize size) {
    final message = maxMessageLength;
    if (message != null && size.messageBytes > message) return false;
    final content = maxContentLength;
    if (content != null && size.contentLength > content) return false;
    return true;
  }

  Map<String, Object?> toJson() => {
    if (maxMessageLength != null) 'max_message_length': maxMessageLength,
    if (maxContentLength != null) 'max_content_length': maxContentLength,
    if (authRequired) 'auth_required': true,
    if (paymentRequired) 'payment_required': true,
    if (restrictedWrites) 'restricted_writes': true,
  };
}

/// Size of an event as a relay sees it.
class EventSize {
  const EventSize({required this.messageBytes, required this.contentLength});

  factory EventSize.of(NostrEvent event) => EventSize(
    messageBytes: utf8.encode(jsonEncode(['EVENT', event.toJson()])).length,
    contentLength: event.content.length,
  );

  final int messageBytes;
  final int contentLength;
}

/// Does a rejection mean "too large" (and not "broken" or "not allowed")?
/// Covers strfry ("invalid: event too large: 66078"), nostr-rs-relay and
/// khatru-style wording. "too many" (rate limit) and "quota exceeded"
/// (storage, not size) deliberately do not match.
bool isTooLargeMessage(String raw) {
  final text = raw.toLowerCase();
  return text.contains('too large') ||
      text.contains('too big') ||
      text.contains('too long') ||
      (text.contains('exceed') &&
          (text.contains('size') ||
              text.contains('length') ||
              text.contains('bytes'))) ||
      text.contains('max_message_length') ||
      text.contains('max_content_length') ||
      text.contains('maximum size') ||
      text.contains('payload size');
}
