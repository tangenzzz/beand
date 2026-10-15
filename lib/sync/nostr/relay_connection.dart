import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../identity/identity.dart';
import 'event.dart';

// A WebSocket connection to a relay (NIP-01), plus NIP-42 authentication if
// the relay requires it. Deliberately narrow: send an event and wait for
// OK, collect a query until EOSE. Reconnecting and multiple relays are
// handled by the RelayPool.

typedef WebSocketConnector = WebSocketChannel Function(Uri uri);

WebSocketChannel defaultConnector(Uri uri) => WebSocketChannel.connect(uri);

/// A relay's response to a sent event.
class PublishResult {
  const PublishResult(this.accepted, this.message);
  final bool accepted;

  /// The relay's reason (prefix like `blocked:`, `invalid:` …), empty on
  /// success.
  final String message;
}

class RelayException implements Exception {
  const RelayException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RelayConnection {
  RelayConnection(
    this.url, {
    this.identity,
    WebSocketConnector? connector,
    this.timeout = const Duration(seconds: 15),
  }) : _connector = connector ?? defaultConnector;

  final String url;

  /// For NIP-42 authentication; without it the connection stays anonymous.
  final SyncIdentity? identity;
  final Duration timeout;
  final WebSocketConnector _connector;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _publishes = <String, Completer<PublishResult>>{};
  final _queries = <String, _Query>{};
  Completer<void>? _authenticated;
  String? _authEventId;
  var _subCounter = 0;
  bool _closed = false;
  bool _closedLocally = false;

  /// Reports the end of the connection (by the relay or due to an error).
  final _done = Completer<void>();
  Future<void> get done => _done.future;
  bool get isOpen => _channel != null && !_closed;

  /// Closed by us ([close]), not by the relay or the network — errors of
  /// requests still running then say nothing about the relay.
  bool get closedLocally => _closedLocally;

  Future<void> connect() async {
    final channel = _connector(Uri.parse(url));
    _channel = channel;
    try {
      await channel.ready.timeout(timeout);
    } catch (e) {
      _closed = true;
      throw RelayException('Could not connect: ${_short(e)}');
    }
    _subscription = channel.stream.listen(
      _onMessage,
      onError: (Object e) => _fail('Connection error: ${_short(e)}'),
      onDone: () => _fail('Connection closed'),
    );
  }

  /// Send an event; waits for the relay's OK. If the relay first requires
  /// authentication, the connection authenticates and resends once.
  Future<PublishResult> publish(NostrEvent event) async {
    var result = await _send(event);
    if (!result.accepted &&
        result.message.startsWith('auth-required:') &&
        _authenticated != null) {
      await _authenticated!.future.timeout(timeout);
      result = await _send(event);
    }
    return result;
  }

  Future<PublishResult> _send(NostrEvent event) {
    final completer = Completer<PublishResult>();
    _publishes[event.id] = completer;
    _write(['EVENT', event.toJson()]);
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _publishes.remove(event.id);
        throw const RelayException('No answer from server');
      },
    );
  }

  /// All stored events for [filter], until the relay reports EOSE.
  Future<List<NostrEvent>> query(Map<String, Object> filter) async {
    var result = await _query(filter);
    if (result.closedReason != null &&
        result.closedReason!.startsWith('auth-required:') &&
        _authenticated != null) {
      await _authenticated!.future.timeout(timeout);
      result = await _query(filter);
    }
    if (result.closedReason != null) {
      throw RelayException(result.closedReason!);
    }
    return result.events;
  }

  Future<_Query> _query(Map<String, Object> filter) async {
    final id = 'beand${_subCounter++}';
    final q = _Query();
    _queries[id] = q;
    _write(['REQ', id, filter]);
    try {
      await q.completer.future.timeout(timeout);
    } on TimeoutException {
      throw const RelayException('No answer from server');
    } finally {
      _queries.remove(id);
      if (q.closedReason == null && isOpen) _write(['CLOSE', id]);
    }
    return q;
  }

  void _onMessage(dynamic raw) {
    final List<dynamic> message;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! List || decoded.isEmpty) return;
      message = decoded;
    } catch (_) {
      return; // Skip unreadable data from the relay, never crash.
    }
    switch (message[0]) {
      case 'OK' when message.length >= 3:
        final id = message[1];
        final ok = message[2] == true;
        final text = message.length > 3 ? '${message[3]}' : '';
        if (id == _authEventId) {
          if (ok) {
            _authenticated?.complete();
          } else {
            debugPrint('Relay $url rejected AUTH: $text');
          }
          return;
        }
        _publishes.remove(id)?.complete(PublishResult(ok, text));
      case 'EVENT' when message.length >= 3:
        final q = _queries[message[1]];
        if (q == null) return;
        try {
          q.events.add(NostrEvent.fromJson(message[2]));
        } on FormatException {
          // broken event: skip
        }
      case 'EOSE' when message.length >= 2:
        final q = _queries[message[1]];
        if (q != null && !q.completer.isCompleted) q.completer.complete();
      case 'CLOSED' when message.length >= 2:
        final q = _queries[message[1]];
        if (q != null && !q.completer.isCompleted) {
          q.closedReason = message.length > 2 ? '${message[2]}' : 'closed';
          q.completer.complete();
        }
      case 'AUTH' when message.length >= 2:
        unawaited(_authenticate('${message[1]}'));
      case 'NOTICE':
        debugPrint(
          'Relay $url notice: ${message.length > 1 ? message[1] : ''}',
        );
    }
  }

  // NIP-42: answer the relay's challenge with a signed kind-22242 event.
  // Signed in a background isolate (~11 ms on a PC per relay, for all
  // relays at once at app start). The completer is set immediately so
  // requests wait for the authentication.
  Future<void> _authenticate(String challenge) async {
    final id = identity;
    if (id == null) return;
    _authenticated = Completer<void>();
    final privateKey = id.privateKeyBytes;
    final publicKeyHex = id.publicKeyHex;
    final relay = url;
    final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final event = await Isolate.run(
      () => NostrEvent.signWithKey(
        privateKey: privateKey,
        publicKeyHex: publicKeyHex,
        kind: kindClientAuth,
        tags: [
          ['relay', relay],
          ['challenge', challenge],
        ],
        content: '',
        createdAt: createdAt,
      ),
    );
    if (_closed || !isOpen) return;
    _authEventId = event.id;
    _write(['AUTH', event.toJson()]);
  }

  void _write(List<Object> message) {
    if (!isOpen) throw const RelayException('Not connected');
    _channel!.sink.add(jsonEncode(message));
  }

  void _fail(String reason) {
    if (_closed) return;
    _closed = true;
    final error = RelayException(reason);
    for (final c in _publishes.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _publishes.clear();
    for (final q in _queries.values) {
      if (!q.completer.isCompleted) q.completer.completeError(error);
    }
    _queries.clear();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> close() async {
    if (!_closed) _closedLocally = true;
    _fail('Closed');
    await _subscription?.cancel();
    await _channel?.sink.close();
  }

  static String _short(Object e) {
    final text = '$e';
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }
}

class _Query {
  final events = <NostrEvent>[];
  final completer = Completer<void>();
  String? closedReason;
}
