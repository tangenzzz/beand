import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beand/sync/nostr/event.dart';

// A small Nostr relay inside the test process (NIP-01 + replacement for
// kind 30000–39999), so two-device scenarios run on every `flutter test`
// without Docker or strfry. Deliberately strict like a real relay: checks
// ID and signature.

class TestRelay {
  TestRelay._(this._server);

  static Future<TestRelay> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = TestRelay._(server);
    server.listen(relay._onRequest);
    return relay;
  }

  final HttpServer _server;
  final _sockets = <WebSocket>{};

  /// Stored events (replaceable ones only in their newest version).
  final events = <NostrEvent>[];

  /// Pubkeys allowed to write; null = all (like a relay whitelist).
  Set<String>? allowedAuthors;

  /// Rejects everything while true — simulates a failed relay.
  bool down = false;

  /// Maximum number of events per response (like maxFilterLimit).
  int maxLimit = 500;

  /// Rejects every event with this message (e.g. 'rate-limited: slow
  /// down') while set.
  String? rejectWith;

  /// Times of received events (for throttling).
  final received = <DateTime>[];

  String get url => 'ws://127.0.0.1:${_server.port}';

  Future<void> _onRequest(HttpRequest request) async {
    if (down) {
      request.response.statusCode = 503;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    _sockets.add(socket);
    socket.listen(
      (raw) => _onMessage(socket, raw as String),
      onDone: () => _sockets.remove(socket),
    );
  }

  void _send(WebSocket socket, List<Object?> message) {
    // During test cleanup the client may already be gone.
    if (socket.closeCode != null) return;
    try {
      socket.add(jsonEncode(message));
    } on StateError {
      // Connection closed in the meantime
    }
  }

  void _onMessage(WebSocket socket, String raw) {
    final message = jsonDecode(raw) as List;
    switch (message[0]) {
      case 'EVENT':
        final NostrEvent event;
        try {
          event = NostrEvent.fromJson(message[1]);
        } on FormatException {
          _send(socket, ['NOTICE', 'invalid: malformed']);
          return;
        }
        received.add(DateTime.now());
        if (rejectWith != null) {
          _send(socket, ['OK', event.id, false, rejectWith]);
          return;
        }
        if (!event.isValid) {
          _send(socket, ['OK', event.id, false, 'invalid: bad signature']);
          return;
        }
        final allowed = allowedAuthors;
        if (allowed != null && !allowed.contains(event.pubkey)) {
          _send(socket, [
            'OK',
            event.id,
            false,
            'blocked: pubkey not allowed on this relay',
          ]);
          return;
        }
        _store(event);
        if (event.kind == 5) _applyDeletion(event);
        _send(socket, ['OK', event.id, true, '']);
      case 'REQ':
        final subId = message[1] as String;
        final filter = Map<String, Object?>.from(message[2] as Map);
        for (final e in query(filter)) {
          _send(socket, ['EVENT', subId, e.toJson()]);
        }
        _send(socket, ['EOSE', subId]);
      case 'CLOSE':
        break;
    }
  }

  // NIP-09: only the sender's own events, via e-tag.
  void _applyDeletion(NostrEvent deletion) {
    final ids = {
      for (final t in deletion.tags)
        if (t.length >= 2 && t[0] == 'e') t[1],
    };
    events.removeWhere(
      (e) => ids.contains(e.id) && e.pubkey == deletion.pubkey,
    );
  }

  void _store(NostrEvent event) {
    if (events.any((e) => e.id == event.id)) return;
    if (event.kind >= 30000 && event.kind < 40000) {
      final d = event.tag('d') ?? '';
      final old = events
          .where(
            (e) =>
                e.kind == event.kind &&
                e.pubkey == event.pubkey &&
                (e.tag('d') ?? '') == d,
          )
          .toList();
      for (final o in old) {
        // NIP-01: the newer one stays; with the same time the smaller ID.
        final keepOld =
            o.createdAt > event.createdAt ||
            (o.createdAt == event.createdAt && o.id.compareTo(event.id) < 0);
        if (keepOld) return;
        events.remove(o);
      }
    }
    events.add(event);
  }

  List<NostrEvent> query(Map<String, Object?> filter) {
    final kinds = (filter['kinds'] as List?)?.cast<int>();
    final authors = (filter['authors'] as List?)?.cast<String>();
    final since = filter['since'] as int?;
    final until = filter['until'] as int?;
    final dTags = (filter['#d'] as List?)?.cast<String>();
    final limit = (filter['limit'] as int? ?? maxLimit).clamp(0, maxLimit);
    final matching =
        events
            .where(
              (e) =>
                  (kinds == null || kinds.contains(e.kind)) &&
                  (authors == null || authors.contains(e.pubkey)) &&
                  (since == null || e.createdAt >= since) &&
                  (until == null || e.createdAt <= until) &&
                  (dTags == null || dTags.contains(e.tag('d'))),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matching.take(limit).toList();
  }

  Future<void> close() async {
    for (final s in _sockets.toList()) {
      await s.close();
    }
    await _server.close(force: true);
  }
}
