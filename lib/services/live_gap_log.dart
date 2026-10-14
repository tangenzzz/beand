import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// Tracing gaps in the live curve (e.g. the time stood still, or the chart
// had a hole in the last seconds). The machine sends every 100 ms without
// gaps — all captures show that — so the gap arises on the phone. This file
// records WHERE:
//
// - `status`: more than one second passed between two status messages. If
//   the machine time jumped that far too, messages were lost (network,
//   reconnect); if it only advanced ~100 ms, they arrived late in a batch.
// - `stall`: the heartbeat timer fired more than one second late — then the
//   app itself hung (main thread blocked), not the network.
// - `connection`: the socket connection changed during the brew.
//
// Stored as `live_gaps.log` in the app folder (`adb shell run-as … cat
// app_flutter/live_gaps.log`), at most ~64 KB, then it starts over.
class LiveGapLog {
  LiveGapLog._();

  static const fileName = 'live_gaps.log';
  static const _maxBytes = 64 * 1024;

  // Writes in sequence so lines don't overtake each other.
  static Future<void> _queue = Future.value();

  /// For tests: here instead of a file.
  @visibleForTesting
  static void Function(String line)? sink;

  static void write(String kind, String detail) {
    final line = '${DateTime.now().toIso8601String()} $kind $detail';
    debugPrint('LiveGap: $line');
    final testSink = sink;
    if (testSink != null) {
      testSink(line);
      return;
    }
    _queue = _queue.then((_) => _append(line)).catchError((Object _) {});
  }

  static Future<void> _append(String line) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    final tooBig = await file.exists() && await file.length() > _maxBytes;
    await file.writeAsString(
      '$line\n',
      mode: tooBig ? FileMode.write : FileMode.append,
      flush: true,
    );
  }
}
