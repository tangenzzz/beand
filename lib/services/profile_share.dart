import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a file to the system's share dialog; replaceable in tests.
typedef ProfileFileSharer = Future<void> Function(XFile file, Rect? origin);

Future<void> _systemShare(XFile file, Rect? origin) async {
  await SharePlus.instance.share(
    ShareParams(files: [file], sharePositionOrigin: origin),
  );
}

/// The file name of a shared profile: the profile's name, safe on every
/// system (accents stay).
String profileFileName(String name) {
  final safe = name
      .trim()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${safe.isEmpty ? 'profile' : safe}.json';
}

/// Where the share dialog points to; the iPad needs that, or it fails.
Rect? shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Writes [json] to a temporary .json file and opens the share dialog.
Future<void> shareProfileJson(
  String name,
  Object? json, {
  Rect? origin,
  ProfileFileSharer? share,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, profileFileName(name)));
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  await (share ?? _systemShare)(
    XFile(file.path, mimeType: 'application/json'),
    origin,
  );
}
