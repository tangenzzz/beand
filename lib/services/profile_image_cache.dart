import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'meticulous_urls.dart';

// Stores the machine's profile images locally (file named after the name on
// the machine), so history and profiles show images offline too.
class ProfileImageCache {
  ProfileImageCache({
    required this.client,
    required this.imageDir,
    required this.hostname,
  });

  final http.Client client;
  final Directory imageDir;
  final String Function() hostname;

  // Local path, or null without an image / on error (then the profile color
  // remains as fallback).
  Future<String?> cache(String? apiPath) async {
    final uri = profileImageUri(hostname(), apiPath);
    if (uri == null) return null;
    try {
      final file = File(p.join(imageDir.path, p.basename(apiPath!)));
      if (file.existsSync() && file.lengthSync() > 0) return file.path;
      final response = await client
          .send(imageRequest(uri))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final bytes = await readAtMost(response.stream, maxImageBytes);
      if (bytes == null || bytes.isEmpty) return null;
      await imageDir.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}

/// A GET for an image on the machine. It does not follow a redirect: the
/// machine runs actions on a plain GET, and only the checked address may be
/// fetched.
http.Request imageRequest(Uri uri) =>
    http.Request('GET', uri)..followRedirects = false;

/// Larger than any profile photo the machine makes; a bigger answer is not
/// one of them.
const maxImageBytes = 8 << 20;

/// The whole body, or null once it grows past [limit] bytes.
Future<List<int>?> readAtMost(Stream<List<int>> body, int limit) async {
  final out = BytesBuilder(copy: false);
  await for (final chunk in body.timeout(const Duration(seconds: 10))) {
    out.add(chunk);
    if (out.length > limit) return null;
  }
  return out.takeBytes();
}
