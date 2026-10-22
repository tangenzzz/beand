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

  static void write(String kind, String detail) {
    final line = '${DateTime.now().toIso8601String()} $kind $detail';
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
    return (await f.readAsLines()).where((l) => l.trim().isNotEmpty).toList();
  }

  static Future<void> clear() async {
    await _queue;
    final f = await file();
    if (await f.exists()) await f.delete();
  }
}
