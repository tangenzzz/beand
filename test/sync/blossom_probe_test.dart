import 'dart:convert';
import 'dart:io';

import 'package:beand/sync/blobs/blob_crypto.dart';
import 'package:beand/sync/crypto/bytes.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Does a public Blossom server accept encrypted files (not images, but
// random bytes, application/octet-stream)? Uploads a small encrypted test
// file with the test key, fetches it back and deletes it again. Only runs
// on request — this is a publication:
//
//   BEAND_PROBE_BLOSSOM=https://files.v0l.io,https://blossom.primal.net \
//   BEAND_TEST_KEY=~/.config/beand-test/key-a.sec \
//   flutter test test/sync/blossom_probe_test.dart

void main() {
  final servers = Platform.environment['BEAND_PROBE_BLOSSOM'];
  final keyPath = Platform.environment['BEAND_TEST_KEY'];
  final skip = servers == null || keyPath == null
      ? 'BEAND_PROBE_BLOSSOM / BEAND_TEST_KEY not set'
      : false;

  for (final server in (servers ?? '').split(',').where((s) => s.isNotEmpty)) {
    test(
      'Blossom-Probe $server',
      () async {
        final identity = SyncIdentity.fromPrivateKey(
          hexDecode(
            File(keyPath!.replaceFirst('~', Platform.environment['HOME']!))
                .readAsStringSync()
                .trim(),
          ),
        );
        String auth(String verb, String sha) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final event = NostrEvent.sign(
            identity: identity,
            kind: 24242,
            tags: [
              ['t', verb],
              ['x', sha],
              ['expiration', '${now + 300}'],
            ],
            content: "bean'd sync probe $verb",
            createdAt: now,
          );
          return 'Nostr ${base64.encode(utf8.encode(jsonEncode(event.toJson())))}';
        }

        final client = http.Client();
        addTearDown(client.close);
        final result = <String, Object?>{};
        final blob = await encryptBlob(secureRandomBytes(2048));
        final sha = blob.sha256;
        final base = server.endsWith('/') ? server : '$server/';

        // BUD-06: may I? (not every server supports this)
        try {
          final head = await client
              .head(
                Uri.parse('${base}upload'),
                headers: {
                  'Authorization': auth('upload', sha),
                  'X-SHA-256': sha,
                  'X-Content-Length': '${blob.bytes.length}',
                  'X-Content-Type': 'application/octet-stream',
                },
              )
              .timeout(const Duration(seconds: 20));
          result['head'] =
              '${head.statusCode} ${head.headers['x-reason'] ?? ''}'.trim();
        } catch (e) {
          result['head'] = 'error $e';
        }

        String? url;
        try {
          final put = await client
              .put(
                Uri.parse('${base}upload'),
                headers: {
                  'Authorization': auth('upload', sha),
                  'Content-Type': 'application/octet-stream',
                },
                body: blob.bytes,
              )
              .timeout(const Duration(seconds: 30));
          final reason = put.headers['x-reason'] ?? '';
          result['put'] = '${put.statusCode} $reason'.trim();
          if (put.statusCode >= 200 && put.statusCode < 300) {
            final d = jsonDecode(put.body);
            url = d is Map ? d['url'] as String? : null;
            result['returned sha'] = d is Map ? d['sha256'] == sha : null;
            result['type'] = d is Map ? d['type'] : null;
          } else {
            result['body'] = put.body.length > 160
                ? put.body.substring(0, 160)
                : put.body;
          }
        } catch (e) {
          result['put'] = 'error $e';
        }

        if (url != null) {
          try {
            final get = await client
                .get(Uri.parse(url))
                .timeout(const Duration(seconds: 30));
            result['get'] = get.statusCode;
            result['get intact'] = sha256Hex(get.bodyBytes) == sha;
          } catch (e) {
            result['get'] = 'error $e';
          }
          try {
            final del = await client
                .delete(
                  Uri.parse('$base$sha'),
                  headers: {'Authorization': auth('delete', sha)},
                )
                .timeout(const Duration(seconds: 20));
            result['delete'] = del.statusCode;
          } catch (e) {
            result['delete'] = 'error $e';
          }
        }
        // ignore: avoid_print
        print('BLOSSOM $server: ${jsonEncode(result)}');
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
