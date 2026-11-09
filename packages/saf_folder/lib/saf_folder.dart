import 'package:flutter/services.dart';

/// A folder the user picked once through the system dialog (Android: Storage
/// Access Framework, iOS: document picker, kept as a bookmark). The
/// permission is kept across restarts, so files can be written there later —
/// also from a background task.
class SafFolder {
  const SafFolder({required this.uri, this.name});

  /// Tree URI (`content://…/tree/…`) on Android, `bookmark:…` on iOS — the
  /// handle for later writes.
  final String uri;

  /// Display name of the folder, e.g. "Download"; null if unknown.
  final String? name;

  static const _channel = MethodChannel('beand/saf_folder');

  /// Opens the system folder picker. Null if cancelled.
  static Future<SafFolder?> pick() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickFolder',
    );
    if (result == null) return null;
    return SafFolder(
      uri: result['uri']! as String,
      name: result['name'] as String?,
    );
  }

  /// The whole path of the folder behind [uri], as a file manager shows it.
  /// Null where the URI does not spell it out: cloud providers use opaque IDs
  /// and an iOS bookmark holds no readable path.
  static String? pathOf(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null ||
        parsed.pathSegments.length != 2 ||
        parsed.pathSegments.first != 'tree') {
      return null;
    }
    final id = parsed.pathSegments.last;
    switch (parsed.authority) {
      case 'com.android.externalstorage.documents':
        final colon = id.indexOf(':');
        if (colon < 0) return null;
        final volume = id.substring(0, colon);
        return _joinPath(
          volume == 'primary' ? _internalStorage : volume,
          id.substring(colon + 1),
        );
      case 'com.android.providers.downloads.documents':
        if (id == 'downloads') return _joinPath(_internalStorage, 'Download');
        final raw = RegExp(r'^raw:/storage/emulated/\d+/(.*)$').firstMatch(id);
        return raw == null ? null : _joinPath(_internalStorage, raw.group(1)!);
    }
    return null;
  }

  static const _internalStorage = 'Internal storage';

  static String _joinPath(String root, String rest) =>
      rest.isEmpty ? root : '$root/$rest';

  /// The folder's name if it is still writable, else null (permission
  /// revoked, folder deleted, SD card removed).
  static Future<String?> nameIfWritable(String uri) =>
      _channel.invokeMethod<String>('folderName', {'uri': uri});

  /// Copies [sourcePath] into the folder as [name]. An existing file of
  /// that name is replaced only once the new one is complete. Throws a
  /// [PlatformException] if that fails.
  static Future<void> writeFile(
    String uri, {
    required String name,
    required String sourcePath,
  }) => _channel.invokeMethod<void>('writeFile', {
    'uri': uri,
    'name': name,
    'source': sourcePath,
  });

  /// Gives the folder permission back (when another folder is chosen).
  static Future<void> release(String uri) =>
      _channel.invokeMethod<void>('release', {'uri': uri});
}
