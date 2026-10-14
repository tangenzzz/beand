import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beand/sync/blobs/blob_crypto.dart';
import 'package:beand/sync/nostr/event.dart';

// A small Blossom server in the test process (BUD-01/02): PUT /upload with
// signed authorization (kind 24242, t=upload, x=sha256), GET /<sha256>.
// Like the real one, it checks the signature and — if set — the allowlist.

class TestBlossom {
  TestBlossom._(this._server);

  static Future<TestBlossom> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final blossom = TestBlossom._(server);
    server.listen(blossom._onRequest);
    return blossom;
  }

  final HttpServer _server;
  final blobs = <String, Uint8List>{};

  /// Who uploaded which file (for /list and DELETE).
  final owners = <String, String>{};
  Set<String>? allowedPubkeys;
  int uploads = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> _onRequest(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    if (request.method == 'PUT' && path == '/upload') {
      final bytes = Uint8List.fromList(
        await request.fold<List<int>>([], (a, b) => a..addAll(b)),
      );
      final sha = sha256Hex(bytes);
      final auth = request.headers.value('authorization') ?? '';
      NostrEvent? event;
      try {
        event = NostrEvent.fromJson(
          jsonDecode(utf8.decode(base64.decode(auth.substring(6)))),
        );
      } catch (_) {}
      final ok =
          auth.startsWith('Nostr ') &&
          event != null &&
          event.isValid &&
          event.kind == 24242 &&
          event.tag('t') == 'upload' &&
          event.tag('x') == sha;
      if (!ok) {
        response.statusCode = 401;
      } else if (allowedPubkeys != null &&
          !allowedPubkeys!.contains(event.pubkey)) {
        response.statusCode = 403;
      } else {
        blobs[sha] = bytes;
        owners[sha] = event.pubkey;
        uploads++;
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({'url': '$url/$sha', 'sha256': sha, 'size': bytes.length}),
        );
      }
    } else if (request.method == 'DELETE') {
      final sha = path.substring(1);
      final event = _authEvent(request);
      if (event == null ||
          event.tag('t') != 'delete' ||
          event.tag('x') != sha ||
          (owners[sha] != null && owners[sha] != event.pubkey)) {
        response.statusCode = 401;
      } else if (blobs.remove(sha) == null) {
        response.statusCode = 404;
      } else {
        owners.remove(sha);
      }
    } else if (request.method == 'GET' && path.startsWith('/list/')) {
      final pubkey = path.substring('/list/'.length);
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode([
          for (final e in owners.entries)
            if (e.value == pubkey) {'sha256': e.key, 'url': '$url/${e.key}'},
        ]),
      );
    } else if (request.method == 'HEAD' && path == '/upload') {
      // BUD-06: may this key upload?
      final auth = request.headers.value('authorization') ?? '';
      NostrEvent? event;
      try {
        event = NostrEvent.fromJson(
          jsonDecode(utf8.decode(base64.decode(auth.substring(6)))),
        );
      } catch (_) {}
      if (event == null || !event.isValid) {
        response.statusCode = 401;
      } else if (allowedPubkeys != null &&
          !allowedPubkeys!.contains(event.pubkey)) {
        response.statusCode = 403;
      }
    } else if (request.method == 'GET') {
      final sha = path.substring(1).split('.').first;
      final bytes = blobs[sha];
      if (bytes == null) {
        response.statusCode = 404;
      } else {
        response.add(bytes);
      }
    } else {
      response.statusCode = 405;
    }
    await response.close();
  }

  Future<void> close() => _server.close(force: true);

  // Signed authorization (kind 24242) from the Authorization header.
  NostrEvent? _authEvent(HttpRequest request) {
    final auth = request.headers.value('authorization') ?? '';
    if (!auth.startsWith('Nostr ')) return null;
    try {
      final event = NostrEvent.fromJson(
        jsonDecode(utf8.decode(base64.decode(auth.substring(6)))),
      );
      return event.isValid && event.kind == 24242 ? event : null;
    } catch (_) {
      return null;
    }
  }
}
