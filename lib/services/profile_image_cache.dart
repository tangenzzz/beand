import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

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
    if (apiPath == null || apiPath.isEmpty) return null;
    try {
      final file = File(p.join(imageDir.path, p.basename(apiPath)));
      if (file.existsSync() && file.lengthSync() > 0) return file.path;
      final response = await client
          .get(Uri.parse('http://${hostname()}$apiPath'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await imageDir.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
