import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../identity/identity.dart';
import '../nostr/event.dart';
import 'blob_crypto.dart';

// Blossom (BUD-01/02): files are stored under their sha256. Upload via
// PUT /upload with a signed authorization (kind 24242) in the
// Authorization header, download via GET /<sha256>.
// https://github.com/hzrd149/blossom

const kindBlossomAuth = 24242;

class BlossomException implements Exception {
  const BlossomException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BlossomClient {
  BlossomClient({
    required this.identity,
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final SyncIdentity identity;
  final http.Client _client;
  final DateTime Function() _now;
  static const timeout = Duration(seconds: 60);

  // Signs in a background isolate (~11 ms on a PC), like the relay login.
  Future<String> _auth(String verb, [String? sha256]) async {
    final now = _now().millisecondsSinceEpoch ~/ 1000;
    final privateKey = identity.privateKeyBytes;
    final publicKeyHex = identity.publicKeyHex;
    final event = await Isolate.run(
      () => NostrEvent.signWithKey(
        privateKey: privateKey,
        publicKeyHex: publicKeyHex,
        kind: kindBlossomAuth,
        tags: [
          ['t', verb],
          if (sha256 != null) ['x', sha256],
          ['expiration', '${now + 300}'],
        ],
        content: "bean'd sync $verb",
        createdAt: now,
      ),
    );
    return 'Nostr ${base64.encode(utf8.encode(jsonEncode(event.toJson())))}';
  }

  static Uri _endpoint(String server, String path) {
    final base = server.endsWith('/') ? server : '$server/';
    return Uri.parse(base).resolve(path);
  }

  /// Uploads [bytes]; the result is the URL according to the server. Throws
  /// [BlossomException] with a readable message.
  Future<String> upload(String server, Uint8List bytes) async {
    // In the background: hashing a photo on the main isolate froze the app.
    final sha = await sha256HexInBackground(bytes);
    final http.Response response;
    try {
      response = await _client
          .put(
            _endpoint(server, 'upload'),
            headers: {
              'Authorization': await _auth('upload', sha),
              'Content-Type': 'application/octet-stream',
            },
            body: bytes,
          )
          .timeout(timeout);
    } catch (e) {
      throw const BlossomException("Can't reach this photo server.");
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const BlossomException(
        "This photo server doesn't accept your device key yet.",
      );
    }
    if (response.statusCode == 413) {
      throw const BlossomException('The photo is too large for this server.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BlossomException('Photo server error ${response.statusCode}.');
    }
    try {
      final descriptor = jsonDecode(response.body);
      if (descriptor is Map &&
          descriptor['sha256'] != null &&
          descriptor['sha256'] != sha) {
        throw const BlossomException('Photo server stored something else.');
      }
      final url = descriptor is Map ? descriptor['url'] : null;
      return url is String ? url : _endpoint(server, sha).toString();
    } on FormatException {
      return _endpoint(server, sha).toString();
    }
  }

  /// Fetches a file; null if it is not (or no longer) there or does not
  /// match the sha256.
  Future<Uint8List?> download(Uri url, String sha256) async {
    try {
      final response = await _client.get(url).timeout(timeout);
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      return await sha256HexInBackground(bytes) == sha256 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  /// May I upload here? (BUD-06: HEAD /upload with authorization.) null =
  /// yes, or server reachable but does not support the query; otherwise the
  /// message for display.
  Future<String?> check(String server) async {
    const sha =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    try {
      final response = await _client
          .head(
            _endpoint(server, 'upload'),
            headers: {
              'Authorization': await _auth('upload', sha),
              'X-SHA-256': sha,
              'X-Content-Length': '1024',
              'X-Content-Type': 'application/octet-stream',
            },
          )
          .timeout(const Duration(seconds: 15));
      return switch (response.statusCode) {
        401 || 403 => "This photo server doesn't accept your device key yet.",
        415 || 400 => "This photo server doesn't take encrypted files.",
        _ => null,
      };
    } catch (_) {
      return "Can't reach this photo server.";
    }
  }

  /// All files of this key on [server] (BUD-02: `GET /list/<pubkey>`, some
  /// servers require an authorization for it). null = server does not
  /// support the query or is unreachable.
  Future<List<String>?> list(String server) async {
    try {
      final response = await _client
          .get(
            _endpoint(server, 'list/${identity.publicKeyHex}'),
            headers: {'Authorization': await _auth('list')},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! List) return null;
      return [
        for (final d in body)
          if (d is Map && d['sha256'] is String) d['sha256'] as String,
      ];
    } catch (_) {
      return null;
    }
  }

  /// Delete a file (BUD-02: `DELETE /<sha256>`). true = gone or never there.
  Future<bool> delete(String server, String sha256) async {
    try {
      final response = await _client
          .delete(
            _endpoint(server, sha256),
            headers: {'Authorization': await _auth('delete', sha256)},
          )
          .timeout(timeout);
      return response.statusCode == 404 ||
          (response.statusCode >= 200 && response.statusCode < 300);
    } catch (_) {
      return false;
    }
  }

  /// URL of the same file on another server.
  static Uri addressOn(String server, String sha256) =>
      _endpoint(server, sha256);

  void close() => _client.close();
}
