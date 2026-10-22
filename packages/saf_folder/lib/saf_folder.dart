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
