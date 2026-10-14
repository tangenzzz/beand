// Standalone connection test for a Meticulous machine, independent of the app.
// Usage: dart run tool/socket_test.dart [hostname] [--port=8080] [--duration=60]
//        [--out=capture.jsonl] [--note="cold start, fresh water"]
//
// Connects via Socket.IO and logs all known events (`status`, `sensors`,
// `heater_status`, `water_status`, `button`, `notification`, `profileHover`,
// `profile`, `OSUpdate`, `communication`, `actuators`). Without --out only a
// shortened console output. With --out EVERY event is written to the file as
// a full JSON line, e.g. to trigger preheat/heating/brewing on the real
// machine during the capture and look for `setpoints`/target temperature
// fields afterwards.
//
// With --out the process runs until SIGINT/SIGTERM or until --duration ends;
// in both cases the output file is flushed and closed cleanly instead of
// being cut off by a hard kill. --note becomes the first line of the file
// (event `_meta`), so context like water state stays with the data.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:socket_io_client/socket_io_client.dart' as io;

const _defaultHost = 'meticulous.local';

const _extraEvents = [
  'water_status',
  'button',
  'notification',
  'profileHover',
  'profile',
  'OSUpdate',
  'communication',
  'actuators',
];

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final host = positional.isNotEmpty ? positional.first : _defaultHost;

  String? flag(String name) {
    final match = args.firstWhere(
      (a) => a.startsWith('--$name='),
      orElse: () => '',
    );
    return match.isEmpty ? null : match.split('=').last;
  }

  final port = flag('port');
  final durationSeconds = int.tryParse(flag('duration') ?? '') ?? 15;
  final outPath = flag('out');
  final note = flag('note');

  final url = port == null ? 'http://$host' : 'http://$host:$port';
  final runDuration = Duration(seconds: durationSeconds);

  IOSink? sink;
  if (outPath != null) {
    sink = File(outPath).openWrite();
    stdout.writeln('Writing full events to $outPath');
    sink.writeln(
      jsonEncode({
        't': DateTime.now().toIso8601String(),
        'event': '_meta',
        'data': {'host': host, 'port': port, 'note': note ?? ''},
      }),
    );
  }

  stdout.writeln('Connecting to $url (duration: ${durationSeconds}s) ...');

  final socket = io.io(
    url,
    io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setTimeout(8000)
        .build(),
  );

  var statusCount = 0;
  var sensorsCount = 0;
  final completer = Completer<void>();

  void logEvent(String event, dynamic data) {
    if (sink == null) return;
    final line = jsonEncode({
      't': DateTime.now().toIso8601String(),
      'event': event,
      'data': data,
    });
    sink.writeln(line);
  }

  socket.onConnect((_) {
    stdout.writeln('✓ connected (socket ID: ${socket.id})');
  });

  socket.onConnectError((err) {
    stdout.writeln('✗ connection error: $err');
  });

  socket.onConnectTimeout((_) {
    stdout.writeln('✗ connection timeout');
  });

  socket.onError((err) {
    stdout.writeln('✗ error: $err');
  });

  socket.onDisconnect((_) {
    stdout.writeln('disconnected');
  });

  socket.on('status', (data) {
    statusCount++;
    logEvent('status', data);
    if (statusCount == 1 || statusCount % 20 == 0) {
      stdout.writeln('status #$statusCount: $data');
    }
  });

  socket.on('sensors', (data) {
    sensorsCount++;
    logEvent('sensors', data);
    if (sensorsCount == 1) {
      stdout.writeln('sensors #$sensorsCount: $data');
    }
  });

  socket.on('heater_status', (data) {
    logEvent('heater_status', data);
    stdout.writeln('heater_status: $data');
  });

  for (final event in _extraEvents) {
    socket.on(event, (data) {
      logEvent(event, data);
      stdout.writeln('$event: $data');
    });
  }

  socket.connect();

  var shuttingDown = false;
  Future<void> shutdown(String reason) async {
    if (shuttingDown) return;
    shuttingDown = true;
    stdout.writeln('---');
    stdout.writeln(
      '$reason. status-Events: $statusCount, sensors-Events: $sensorsCount',
    );
    socket.dispose();
    final s = sink;
    if (s != null) {
      await s.flush();
      await s.close();
      stdout.writeln('Log written: $outPath');
    }
    if (!completer.isCompleted) completer.complete();
  }

  final durationTimer = Timer(runDuration, () {
    unawaited(shutdown('done after ${runDuration.inSeconds}s'));
  });

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) {
      durationTimer.cancel();
      unawaited(shutdown('aborted by $signal'));
    });
  }

  completer.future.then((_) => exit(0));
}
