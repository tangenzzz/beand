import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'blob_crypto.dart';
import 'blob_ref.dart';
import 'blossom_client.dart';

// Files between device and photo servers: encrypt + upload to ALL
// configured servers (one is enough), or fetch, verify, decrypt and store in
// the app folder.

class BlobSync {
  BlobSync({
    required this.client,
    required this.servers,
    required this.docsDir,
  });

  final BlossomClient client;
  final List<String> servers;

  /// The app's documents folder; photos go into subfolders of it (like the
  /// ones taken in the app, so the backup includes them).
  final Future<Directory> Function() docsDir;

  /// Last error message per server (for display).
  final errors = <String, String>{};

  /// Servers that worked last time (display: green).
  final ok = <String>{};

  /// Briefly ask each server whether it accepts uploads.
  Future<void> checkServers() async {
    await Future.wait([
      for (final server in [...servers]) checkServer(server),
    ]);
  }

  /// Query one server (e.g. right after adding it).
  Future<void> checkServer(String server) async {
    final problem = await client.check(server);
    if (problem == null) {
      ok.add(server);
      errors.remove(server);
    } else {
      ok.remove(server);
      errors[server] = problem;
    }
  }

  bool get hasServers => servers.isNotEmpty;

  /// Upload a file. null = no server accepted it.
  Future<BlobRef?> uploadBytes(Uint8List plain, {String extension = ''}) async {
    if (servers.isEmpty) return null;
    final encrypted = await encryptBlob(plain);
    final urls = <String>[];
    await Future.wait([
      for (final server in servers)
        () async {
          try {
            urls.add(await client.upload(server, encrypted.bytes));
            errors.remove(server);
            ok.add(server);
          } on BlossomException catch (e) {
            errors[server] = e.message;
            ok.remove(server);
            debugPrint('Blob upload to $server failed: $e');
          }
        }(),
    ]);
    if (urls.isEmpty) return null;
    return BlobRef(
      sha256: encrypted.sha256,
      size: encrypted.bytes.length,
      key: encrypted.key,
      nonce: encrypted.nonce,
      urls: urls,
      extension: extension,
    );
  }

  Future<BlobRef?> uploadFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    return uploadBytes(await file.readAsBytes(), extension: p.extension(path));
  }

  /// Fetch content and decrypt it. Tries the URLs in the reference first,
  /// then every configured server. null = not found (intact) anywhere.
  Future<Uint8List?> downloadBytes(BlobRef ref) async {
    final candidates = <Uri>{
      for (final u in ref.urls)
        if (Uri.tryParse(u) != null) Uri.parse(u),
      for (final s in servers) BlossomClient.addressOn(s, ref.sha256),
    };
    for (final url in candidates) {
      final bytes = await client.download(url, ref.sha256);
      if (bytes == null) continue;
      try {
        return await decryptBlob(bytes, ref.key, ref.nonce);
      } catch (e) {
        debugPrint('Blob ${ref.sha256} from $url not decryptable: $e');
      }
    }
    return null;
  }

  /// Fetch and store as a file in `<docs>/<folder>/`; the result is the
  /// path, or null.
  Future<String?> downloadFile(BlobRef ref, String folder) async {
    final bytes = await downloadBytes(ref);
    if (bytes == null) return null;
    final dir = Directory(p.join((await docsDir()).path, folder))
      ..createSync(recursive: true);
    final path = p.join(
      dir.path,
      'sync_${ref.sha256.substring(0, 16)}${ref.extension}',
    );
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}
