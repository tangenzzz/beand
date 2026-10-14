import 'dart:async';

import 'package:flutter/foundation.dart';

import '../identity/identity.dart';
import 'event.dart';
import 'relay_connection.dart';

// Several relays in parallel: connects on demand, remembers the state per
// relay for display and, after an error, waits with growing backoff before
// trying the same relay again.

/// What the display shows: the result of the LAST contact, not whether the
/// connection is currently open (it closes after a minute of idleness —
/// gray then meant "sleeping" and looked like "broken"). idle = no contact
/// yet, connected = last contact ok.
enum RelayState { idle, connecting, connected, error }

class RelayStatus {
  const RelayStatus(this.state, {this.message});
  final RelayState state;

  /// Understandable message for the UI (without Nostr jargon).
  final String? message;
}

class RelayPool extends ChangeNotifier {
  RelayPool({
    required this.identity,
    this.connector,
    this.timeout = const Duration(seconds: 15),
    this.minSendInterval = const Duration(milliseconds: 500),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Interval between two events to the SAME relay. Public relays throttle
  /// (e.g. damus blocked after a first large upload with "too many
  /// rate-limit violations") — at most two per second.
  final Duration minSendInterval;

  /// The relay throttled: leave it completely alone for this long, even on
  /// "Sync now".
  static const rateLimitedPause = Duration(minutes: 15);
  static const bannedPause = Duration(hours: 6);

  final SyncIdentity identity;
  final WebSocketConnector? connector;
  final Duration timeout;
  final DateTime Function() _now;

  final _connections = <String, RelayConnection>{};
  final _statuses = <String, RelayStatus>{};
  final _failures = <String, int>{};
  final _retryAt = <String, DateTime>{};
  final _holdUntil = <String, DateTime>{};
  final _nextSendAt = <String, DateTime>{};
  var _urls = <String>[];

  List<String> get urls => List.unmodifiable(_urls);
  RelayStatus statusOf(String url) =>
      _statuses[url] ?? const RelayStatus(RelayState.idle);

  /// Set the list of relays; removed ones are disconnected.
  void setUrls(List<String> urls) {
    _urls = [...urls];
    for (final url in _connections.keys.toList()) {
      if (!_urls.contains(url)) unawaited(_connections.remove(url)!.close());
    }
    _statuses.removeWhere((url, _) => !_urls.contains(url));
    _notify();
  }

  /// Wartezeit nach dem n-ten Fehlschlag in Folge: 5 s, 10 s, 20 s … 5 min.
  static Duration backoff(int failures) {
    final seconds = 5 * (1 << (failures - 1).clamp(0, 6));
    return Duration(seconds: seconds.clamp(5, 300));
  }

  /// [force]: ignore the backoff after errors (user taps "Sync now").
  Future<RelayConnection?> _connection(String url, {bool force = false}) async {
    final hold = _holdUntil[url];
    if (hold != null && _now().isBefore(hold)) return null;
    final existing = _connections[url];
    if (existing != null && existing.isOpen) return existing;
    final retry = _retryAt[url];
    if (!force && retry != null && _now().isBefore(retry)) return null;

    _set(url, const RelayStatus(RelayState.connecting));
    final connection = RelayConnection(
      url,
      identity: identity,
      connector: connector,
      timeout: timeout,
    );
    try {
      await connection.connect();
    } on RelayException catch (e) {
      _failed(url, e.message);
      return null;
    }
    _connections[url] = connection;
    _failures.remove(url);
    _retryAt.remove(url);
    _set(url, const RelayStatus(RelayState.connected));
    unawaited(
      connection.done.then((_) {
        if (_connections[url] == connection) _connections.remove(url);
      }),
    );
    return connection;
  }

  // Did the relay throttle? Then pause without exception, connection closed.
  bool _maybeHold(String url, String raw) {
    final text = raw.toLowerCase();
    final banned = text.startsWith('banned') || text.contains('banned:');
    final limited =
        text.startsWith('rate-limited') ||
        text.contains('rate-limit') ||
        text.contains('rate limit') ||
        text.contains('too many');
    if (!banned && !limited) return false;
    _holdUntil[url] = _now().add(banned ? bannedPause : rateLimitedPause);
    final connection = _connections.remove(url);
    if (connection != null) unawaited(connection.close());
    _set(url, RelayStatus(RelayState.error, message: friendlyMessage(raw)));
    return true;
  }

  void _failed(String url, String message) {
    if (_maybeHold(url, message)) return;
    final failures = (_failures[url] ?? 0) + 1;
    _failures[url] = failures;
    _retryAt[url] = _now().add(backoff(failures));
    _set(url, RelayStatus(RelayState.error, message: friendlyMessage(message)));
  }

  void _set(String url, RelayStatus status) {
    _statuses[url] = status;
    _notify();
  }

  /// Send to all relays. Result per relay; if a relay is missing from the
  /// map, it was unreachable.
  Future<Map<String, PublishResult>> publish(
    NostrEvent event, {
    bool force = false,
  }) async {
    final results = <String, PublishResult>{};
    await Future.wait([
      for (final url in _urls)
        () async {
          final connection = await _connection(url, force: force);
          if (connection == null) return;
          try {
            await _pace(url);
            final result = await connection.publish(event);
            results[url] = result;
            if (!result.accepted && _maybeHold(url, result.message)) {
              // paused
            } else if (!result.accepted) {
              _set(
                url,
                RelayStatus(
                  RelayState.error,
                  message: friendlyMessage(result.message),
                ),
              );
            } else if (statusOf(url).state != RelayState.connected) {
              _set(url, const RelayStatus(RelayState.connected));
            }
          } on RelayException catch (e) {
            _failed(url, e.message);
          }
        }(),
    ]);
    return results;
  }

  // Send per relay at intervals of [minSendInterval]. Several sends run in
  // parallel; each reserves the next free slot.
  Future<void> _pace(String url) async {
    final now = _now();
    final slot = _nextSendAt[url];
    final at = slot == null || slot.isBefore(now) ? now : slot;
    _nextSendAt[url] = at.add(minSendInterval);
    final wait = at.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  /// A query to exactly one relay (for paginated fetching).
  Future<List<NostrEvent>> queryOne(
    String url,
    Map<String, Object> filter, {
    bool force = false,
  }) async {
    final connection = await _connection(url, force: force);
    if (connection == null) {
      throw RelayException(statusOf(url).message ?? 'Not reachable');
    }
    try {
      return await connection.query(filter);
    } on RelayException catch (e) {
      _failed(url, e.message);
      rethrow;
    }
  }

  Future<void> closeAll() async {
    final all = _connections.values.toList();
    _connections.clear();
    for (final c in all) {
      await c.close();
    }
  }

  bool _disposed = false;

  // After dispose(), connections still close asynchronously — then don't
  // notify anyone anymore.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(closeAll());
    super.dispose();
  }
}

/// Translate relay messages into sentences for the UI. The prefixes come
/// from NIP-01 (`blocked:`, `invalid:` …).
String friendlyMessage(String raw) {
  final text = raw.toLowerCase();
  if (text.startsWith('banned') ||
      text.contains('rate-limit') ||
      text.contains('rate limit') ||
      text.contains('too many')) {
    return 'This server is slowing us down for a while — the others carry '
        'on.';
  }
  if (text.contains('pubkey not allowed') ||
      (text.startsWith('blocked:') && text.contains('pubkey'))) {
    return "This server doesn't accept your device key yet.";
  }
  if (text.startsWith('blocked:') || text.startsWith('restricted:')) {
    return 'This server refused the data.';
  }
  if (text.startsWith('auth-required:')) {
    return 'This server wants a sign-in that did not work.';
  }
  if (text.contains('created_at') ||
      text.contains('too late') ||
      text.contains('too early') ||
      text.contains('in the future')) {
    return "Your device clock seems to be off — check date and time.";
  }
  if (text.startsWith('invalid:')) return 'This server rejected the data.';
  if (text.startsWith('could not connect') ||
      text.startsWith('connection') ||
      text.startsWith('no answer')) {
    return "Can't reach this server.";
  }
  return raw.isEmpty ? 'Unknown error.' : raw;
}
