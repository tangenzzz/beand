import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// What happened to the connection to the Meticulous, with time and reason —
// to tell a shaky Wi-Fi from a hanging app (Settings → Connections →
// Connection log, where it can be shared). Began as the trace of gaps in
// the live curve (until 2026-10-21 "live_gaps.log"); it now writes all the
// time:
//
// - `connect` / `connected` / `disconnected` / `error`: the socket.
// - `reconnect`: the watchdog found no status for a while and rebuilt the
//   connection (the dot turns yellow for a few seconds).
// - `address`: the stored address did not answer, another one was found.
// - `action`: a command (start, stop, purge, …) — ok with its time, or why
//   it failed (timeout = the machine did not answer, network error, HTTP
//   code).
// - `stall`: the app itself was blocked (main thread), not the network.
// - `app`: to the background / back in front (gaps there are normal).
// - During a brew also `status` (more than one second between two status
//   messages) and `connection` (the socket changed mid-brew).
//
// - `crash`: an error nothing caught, with where it happened.
// - `failed`: a job that went wrong in the background (backup, import, sync).
//
// Users can send this file, so nothing private may end up in it: every line
// goes through [ConnectionLog.sanitize], on writing and again on reading
// (older lines were written without it).
//
// At most ~64 KB, then it starts over.
class ConnectionLog {
  ConnectionLog._();

  static const fileName = 'connection.log';
  static const _maxBytes = 64 * 1024;

  // Writes in sequence so lines don't overtake each other.
  static Future<void> _queue = Future.value();

  // What the app is busy with right now (sync, import, …) — named in a
  // `stall` line, so a freeze points at its cause.
  static final _busy = <String>[];

  /// Runs [body] marked as [label] for the stall lines.
  static Future<T> track<T>(String label, Future<T> Function() body) async {
    _busy.add(label);
    try {
      return await body();
    } finally {
      _busy.remove(label);
    }
  }

  /// Labels of the work running now, for a stall line.
  static String get busy => _busy.isEmpty ? '' : ' during ${_busy.join(', ')}';

  /// For tests: here instead of a file.
  @visibleForTesting
  static void Function(String line)? sink;

  static final _shareableHosts = <String>{};

  /// Public servers whose names may appear (the app's defaults). Anything
  /// else could be the user's own server.
  static void allowHosts(Iterable<String> urls) {
    for (final url in urls) {
      final host = Uri.tryParse(url)?.host ?? '';
      if (host.isNotEmpty) _shareableHosts.add(host);
    }
  }

  /// A server's name for a log line.
  static String hostLabel(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return _shareableHosts.contains(host) ? host : '<own server>';
  }

  /// A machine's address for a log line. The default names and anything the
  /// filter already shortens stay readable; a name the user chose is theirs.
  static String machineLabel(String host) {
    final shown = sanitize(host);
    if (shown != host) return shown;
    const generic = {'meticulous.local', 'gaggimate.local'};
    return generic.contains(host.toLowerCase()) ? host : '<machine>';
  }

  static const _maxDetail = 2000;
  static const _maxMessage = 200;

  static final _urls = RegExp(
    r'''\b(wss?|https?)://[^\s,'"()\[\]<>]+''',
    caseSensitive: false,
  );
  static final _hostLookup = RegExp(r"host lookup: '([^']+)'");
  static final _paths = RegExp(
    r'''(?:file://)?/(?:data|storage|var|private|Users|home|mnt|sdcard)/[^\s'",)]+''',
  );
  static final _named = RegExp(
    r'\b(api[_-]?key|access[_-]?token|token|password|passwd|secret|authorization)\b\s*[=:]\s*(?:bearer\s+|nostr\s+)?[^\s,;&]+',
    caseSensitive: false,
  );
  static final _replacements = <(RegExp, String)>[
    (RegExp(r'\b(?:nsec|npub|ncryptsec)1[a-z0-9]{10,}\b'), '<key>'),
    (RegExp(r'\bsk-[A-Za-z0-9_-]{8,}'), '<secret>'),
    (RegExp(r'\bAIza[0-9A-Za-z_-]{20,}'), '<secret>'),
    (RegExp(r'\bBearer\s+[^\s,;]+', caseSensitive: false), '<secret>'),
    (RegExp(r'\bNostr\s+[A-Za-z0-9+/=]{16,}'), '<secret>'),
    (RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '<email>'),
    (
      RegExp(r'\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b', caseSensitive: false),
      '<device>',
    ),
    (
      RegExp(
        r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
        caseSensitive: false,
      ),
      '<id>',
    ),
    (RegExp(r'\b[0-9a-fA-F]{32,}\b'), '<hex>'),
    (RegExp(r'[A-Za-z0-9+/_-]{48,}={0,2}'), '<data>'),
    (
      RegExp(r'\b[0-9a-f]{1,4}(?::[0-9a-f]{0,4}){3,7}\b', caseSensitive: false),
      '<ip>',
    ),
    (RegExp(r'[0-9a-f]{0,4}::[0-9a-f:]+', caseSensitive: false), '<ip>'),
    (RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b'), '<ip>'),
    (
      RegExp(
        r'\b(?!meticulous\.local\b|gaggimate\.local\b)[a-z0-9-]+\.local\b',
        caseSensitive: false,
      ),
      '<machine>.local',
    ),
    (RegExp(r'\b[a-z0-9.-]+\.ts\.net\b', caseSensitive: false), '<server>'),
    // The machine's own name carries its serial number.
    (
      RegExp(
        r'\b(?:meticulous|gaggimate)-?(?=[a-z0-9]*\d)[a-z0-9]+\b',
        caseSensitive: false,
      ),
      '<machine>',
    ),
  ];

  /// Takes out what is nobody else's business: keys, addresses, the machine's
  /// serial number, the user's own servers and file paths.
  static String sanitize(String text) {
    var out = text
        .replaceAllMapped(_urls, (m) {
          final host = Uri.tryParse(m[0]!)?.host ?? '';
          final shown = _shareableHosts.contains(host) ? host : '<server>';
          return '${m[1]}://$shown';
        })
        .replaceAllMapped(
          _hostLookup,
          (m) => _shareableHosts.contains(m[1])
              ? m[0]!
              : "host lookup: '<server>'",
        )
        .replaceAll(_paths, '<path>')
        .replaceAllMapped(_named, (m) => '${m[1]}=<hidden>');
    for (final (pattern, replacement) in _replacements) {
      out = out.replaceAll(pattern, replacement);
    }
    return out.length > _maxDetail ? out.substring(0, _maxDetail) : out;
  }

  // Time and kind stay as they are.
  static String _sanitizeLine(String line) {
    final parts = line.split(' ');
    if (parts.length < 3) return line;
    final head = '${parts[0]} ${parts[1]} ';
    return head + sanitize(line.substring(head.length));
  }

  static String _describe(Object error) {
    // A FormatException quotes the text it could not read: the user's data.
    final text = error is FormatException
        ? 'FormatException: ${error.message}'
        : '$error';
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length > _maxMessage
        ? oneLine.substring(0, _maxMessage)
        : oneLine;
  }

  /// A job in the background went wrong.
  static void failure(String what, Object error) =>
      write('failed', '$what: ${_describe(error)}');

  static String? _lastCrash;
  static DateTime? _lastCrashAt;

  /// An error nothing caught. A broken widget throws on every frame, so the
  /// same one is written only once in a while.
  static void crash(Object error, StackTrace? stack, {String? source}) {
    final message = _describe(error);
    final now = DateTime.now();
    final last = _lastCrashAt;
    if (message == _lastCrash &&
        last != null &&
        now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastCrash = message;
    _lastCrashAt = now;
    final frames = '${stack ?? ''}'
        .split('\n')
        .map((f) => f.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((f) => f.isNotEmpty)
        .take(12)
        .join(' | ');
    write(
      'crash',
      '${source == null ? '' : '$source: '}$message'
          '${frames.isEmpty ? '' : ' @ $frames'}',
    );
  }

  /// For tests: forgets the last crash.
  @visibleForTesting
  static void resetCrashes() {
    _lastCrash = null;
    _lastCrashAt = null;
  }

  /// [header] and all lines, as sent to someone.
  static Future<String> shareText(String header) async =>
      '$header\n\n${(await read()).join('\n')}\n';

  static void write(String kind, String detail) {
    final line =
        '${DateTime.now().toIso8601String()} $kind ${sanitize(detail)}';
    debugPrint('ConnectionLog: $line');
    final testSink = sink;
    if (testSink != null) {
      testSink(line);
      return;
    }
    _queue = _queue.then((_) => _append(line)).catchError((Object _) {});
  }

  static bool _legacyChecked = false;

  static Future<File> file() async {
    final dir = await getApplicationDocumentsDirectory();
    // The old brew-only trace: no longer written, so it goes once.
    if (!_legacyChecked) {
      _legacyChecked = true;
      try {
        final old = File('${dir.path}/live_gaps.log');
        if (await old.exists()) await old.delete();
      } catch (_) {}
    }
    return File('${dir.path}/$fileName');
  }

  static Future<void> _append(String line) async {
    final f = await file();
    final tooBig = await f.exists() && await f.length() > _maxBytes;
    await f.writeAsString(
      '$line\n',
      mode: tooBig ? FileMode.write : FileMode.append,
      flush: true,
    );
  }

  /// All lines, oldest first (waits for pending writes).
  static Future<List<String>> read() async {
    await _queue;
    final f = await file();
    if (!await f.exists()) return const [];
    return (await f.readAsLines())
        .where((l) => l.trim().isNotEmpty)
        .map(_sanitizeLine)
        .toList();
  }

  static Future<void> clear() async {
    await _queue;
    final f = await file();
    if (await f.exists()) await f.delete();
  }
}
